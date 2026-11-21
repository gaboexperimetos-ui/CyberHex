package com.gaboexperimetos.cyberhex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log

/**
 * Servicio en primer plano de reproducción.
 *
 * **No reproduce nada**: el motor de audio vive en Dart. Este servicio existe
 * para tres cosas:
 *  1. mantener el proceso vivo con `foregroundServiceType="mediaPlayback"`
 *     (audio con la pantalla apagada, app minimizada, pantalla de bloqueo);
 *  2. publicar una [MediaSession] + notificación `MediaStyle` con los controles;
 *  3. traducir los estímulos del sistema (botones del casco, pantalla de
 *     bloqueo, audio focus, desconexión de auriculares) a comandos del canal
 *     `cyberhex/media` que ejecuta Dart.
 *
 * Ciclo de notificación:
 *  * suena → `startForeground()` con notificación `ongoing` (no se puede
 *    deslizar);
 *  * pausa → `stopForeground(STOP_FOREGROUND_DETACH)` (en API < 24,
 *    `stopForeground(false)`): la notificación **sigue** ahí, pero ya no es
 *    obligatoria, se repinta con `setOngoing(false)` y `deleteIntent`, así que
 *    deslizarla cierra la reproducción;
 *  * deslizar en pausa o `onStop` → se manda `pause` a Dart y `stopSelf()`.
 */
class MediaSessionService : Service() {

    companion object {
        private const val TAG = "CyberHex.Media"

        private const val CHANNEL_ID = "cyberhex_playback"
        private const val NOTIFICATION_ID = 0x0C0DE

        /** Arranca el servicio (primer plano si el sistema lo exige). */
        fun start(context: Context) {
            val intent = Intent(context, MediaSessionService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private lateinit var session: MediaSession
    private lateinit var audioManager: AudioManager

    private var focusRequest: AudioFocusRequest? = null
    private var noisyReceiver: BroadcastReceiver? = null

    private var metadata: TrackMetadata? = null
    private var state = PlayerState(false, 0L, 0L, false)

    private var foregroundStarted = false
    private var pausedForFocus = false

    // -------------------------------------------------------------------------
    // Ciclo de vida
    // -------------------------------------------------------------------------

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        session = MediaSession(this, "CyberHex")
        session.setCallback(sessionCallback)
        session.setSessionActivity(contentPendingIntent())
        session.isActive = true

        createNotificationChannel()
        registerNoisyReceiver()

        // El puente repinta metadatos/estado en cuanto exista.
        MediaBridge.attach(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        when {
            action == ACTION_STOP -> {
                shutdownPlayback()
                return START_NOT_STICKY
            }

            action == ACTION_START -> {
                // Viene de startForegroundService: hay 5 s para entrar en
                // primer plano, aunque el estado aún no haya llegado.
                if (!foregroundStarted) {
                    startForegroundCompat(buildNotification())
                    foregroundStarted = true
                }
            }

            action != null && action.startsWith(ACTION_PREFIX) -> {
                dispatch(action.removePrefix(ACTION_PREFIX))
            }
        }

        ensureForeground()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        noisyReceiver?.let {
            runCatching { unregisterReceiver(it) }
            noisyReceiver = null
        }
        abandonFocus()

        if (foregroundStarted) {
            stopForegroundCompat(remove = true)
            foregroundStarted = false
        }
        notificationManager().cancel(NOTIFICATION_ID)

        session.isActive = false
        session.release()

        MediaBridge.detachService(this)
        super.onDestroy()
    }

    // -------------------------------------------------------------------------
    // Entradas desde Dart (vía MediaBridge)
    // -------------------------------------------------------------------------

    fun onMetadata(newMetadata: TrackMetadata) {
        metadata = newMetadata
        session.setMetadata(buildMediaMetadata())
        updateNotification()
    }

    fun onState(newState: PlayerState) {
        val previous = state
        state = newState
        session.setPlaybackState(buildPlaybackState())

        val startedPlaying = newState.playing && !previous.playing
        val stoppedPlaying = !newState.playing && previous.playing

        if (startedPlaying) {
            ensureForeground()
            if (!requestFocus()) {
                // Sin foco no suena: se lo decimos a Dart y volverá en pausa.
                MediaBridge.sendCommand("pause")
            }
            updateNotification()
        } else if (stoppedPlaying) {
            abandonFocus()
            demoteFromForeground()
        } else if (newState.buffering != previous.buffering) {
            updateNotification()
        }
    }

    // -------------------------------------------------------------------------
    // MediaSession
    // -------------------------------------------------------------------------

    private val sessionCallback = object : MediaSession.Callback() {
        override fun onPlay() = dispatch(COMMAND_PLAY)

        override fun onPause() = dispatch(COMMAND_PAUSE)

        override fun onStop() = shutdownPlayback()

        override fun onSkipToNext() = dispatch(COMMAND_NEXT)

        override fun onSkipToPrevious() = dispatch(COMMAND_PREVIOUS)

        override fun onSeekTo(pos: Long) = MediaBridge.sendSeek(pos)
    }

    private fun dispatch(command: String) {
        when (command) {
            COMMAND_PLAY, COMMAND_PAUSE, COMMAND_TOGGLE,
            COMMAND_NEXT, COMMAND_PREVIOUS -> MediaBridge.sendCommand(command)

            else -> Log.w(TAG, "comando desconocido: $command")
        }
    }

    private fun buildPlaybackState(): PlaybackState {
        val playbackState = when {
            state.buffering -> PlaybackState.STATE_BUFFERING
            state.playing -> PlaybackState.STATE_PLAYING
            else -> PlaybackState.STATE_PAUSED
        }
        return PlaybackState.Builder()
            .setActions(
                PlaybackState.ACTION_PLAY or
                    PlaybackState.ACTION_PAUSE or
                    PlaybackState.ACTION_PLAY_PAUSE or
                    PlaybackState.ACTION_SKIP_TO_NEXT or
                    PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackState.ACTION_SEEK_TO or
                    PlaybackState.ACTION_STOP,
            )
            .setState(
                playbackState,
                state.positionMs,
                if (state.playing) 1f else 0f,
                SystemClock.elapsedRealtime(),
            )
            .build()
    }

    private fun buildMediaMetadata(): MediaMetadata {
        val track = metadata
        val builder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, track?.title?.takeIf { it.isNotBlank() } ?: "CyberHex")
            .putString(MediaMetadata.METADATA_KEY_ARTIST, track?.artist ?: "")
            .putString(MediaMetadata.METADATA_KEY_ALBUM, track?.album ?: "")
            .putLong(MediaMetadata.METADATA_KEY_DURATION, track?.durationMs ?: 0L)

        decodeArt(track?.art)?.let { builder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, it) }
        return builder.build()
    }

    // -------------------------------------------------------------------------
    // Audio focus
    // -------------------------------------------------------------------------

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                // Pérdida definitiva (otra app tomó el foco): pausa sin reanudar.
                pausedForFocus = false
                MediaBridge.sendCommand("pause")
            }

            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                // Llamada o vídeo puntual: pausa y se reanuda al recuperar.
                pausedForFocus = state.playing
                if (pausedForFocus) MediaBridge.sendCommand("pause")
            }

            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // Aviso (navegación, notificación hablada): bajar, no parar.
                MediaBridge.sendCommand("duck", true)
            }

            AudioManager.AUDIOFOCUS_GAIN -> {
                MediaBridge.sendCommand("duck", false)
                if (pausedForFocus) {
                    pausedForFocus = false
                    MediaBridge.sendCommand("play")
                }
            }
        }
    }

    private fun requestFocus(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build(),
                )
                .setWillPauseWhenDucked(false)
                .setOnAudioFocusChangeListener(focusListener)
                .build()
                .also { focusRequest = it }
            return audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }

        @Suppress("DEPRECATION")
        return audioManager.requestAudioFocus(
            focusListener,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN,
        ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
        focusRequest = null
    }

    // -------------------------------------------------------------------------
    // Auriculares desconectados
    // -------------------------------------------------------------------------

    private fun registerNoisyReceiver() {
        if (noisyReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                    // Se sacaron los auriculares: pausar, nunca seguir por el altavoz.
                    MediaBridge.sendCommand("pause")
                }
            }
        }
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        noisyReceiver = receiver
    }

    // -------------------------------------------------------------------------
    // Notificación
    // -------------------------------------------------------------------------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager()
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Reproducción",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Controles de reproducción de CyberHex"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(): Notification {
        val track = metadata
        val playing = state.playing

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
        }

        val subtitle = listOfNotNull(
            track?.artist?.takeIf { it.isNotBlank() },
            track?.album?.takeIf { it.isNotBlank() },
        ).joinToString(" · ")

        builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(track?.title?.takeIf { it.isNotBlank() } ?: "CyberHex")
            .setContentText(subtitle)
            .setContentIntent(contentPendingIntent())
            // Deslizar en pausa cierra la reproducción (solo se puede cuando la
            // notificación no está en modo ongoing).
            .setDeleteIntent(stopPendingIntent())
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setOngoing(playing)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)

        decodeArt(track?.art)?.let { builder.setLargeIcon(it) }

        builder.addAction(
            Notification.Action.Builder(
                android.R.drawable.ic_media_previous,
                "Anterior",
                commandPendingIntent(COMMAND_PREVIOUS, REQUEST_PREVIOUS),
            ).build(),
        )
        builder.addAction(
            Notification.Action.Builder(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "Pausa" else "Reproducir",
                commandPendingIntent(COMMAND_TOGGLE, REQUEST_TOGGLE),
            ).build(),
        )
        builder.addAction(
            Notification.Action.Builder(
                android.R.drawable.ic_media_next,
                "Siguiente",
                commandPendingIntent(COMMAND_NEXT, REQUEST_NEXT),
            ).build(),
        )

        builder.setStyle(
            Notification.MediaStyle()
                .setMediaSession(session.sessionToken)
                .setShowActionsInCompactView(0, 1, 2),
        )

        return builder.build()
    }

    private fun updateNotification() {
        val notification = buildNotification()
        if (foregroundStarted) {
            startForegroundCompat(notification)
        } else {
            notificationManager().notify(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureForeground() {
        if (!foregroundStarted && state.playing) {
            startForegroundCompat(buildNotification())
            foregroundStarted = true
        } else if (!foregroundStarted) {
            // Servicio recién creado y todavía en pausa: notificación discreta.
            updateNotification()
        }
    }

    /**
     * Pausa: sale del primer plano pero **conserva** la notificación, ahora
     * descartable, para poder reanudar desde la cortina.
     */
    private fun demoteFromForeground() {
        if (!foregroundStarted) {
            updateNotification()
            return
        }
        stopForegroundCompat(remove = false)
        foregroundStarted = false
        // Se repinta con setOngoing(false) + deleteIntent.
        updateNotification()
    }

    private fun shutdownPlayback() {
        MediaBridge.sendCommand("pause")
        abandonFocus()
        if (foregroundStarted) {
            stopForegroundCompat(remove = true)
            foregroundStarted = false
        }
        notificationManager().cancel(NOTIFICATION_ID)
        stopSelf()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat(remove: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(if (remove) STOP_FOREGROUND_REMOVE else STOP_FOREGROUND_DETACH)
        } else {
            stopForeground(remove)
        }
    }

    // -------------------------------------------------------------------------
    // Intents
    // -------------------------------------------------------------------------

    private fun contentPendingIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        REQUEST_CONTENT,
        Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        pendingIntentFlags(),
    )

    private fun stopPendingIntent(): PendingIntent = PendingIntent.getService(
        this,
        REQUEST_STOP,
        Intent(this, MediaSessionService::class.java).setAction(ACTION_STOP),
        pendingIntentFlags(),
    )

    private fun commandPendingIntent(command: String, requestCode: Int): PendingIntent =
        PendingIntent.getService(
            this,
            requestCode,
            // El action forma parte del filtro del PendingIntent, así que cada
            // comando es un PendingIntent distinto (los extras no lo serían).
            Intent(this, MediaSessionService::class.java).setAction(ACTION_PREFIX + command),
            pendingIntentFlags(),
        )

    private fun pendingIntentFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    // -------------------------------------------------------------------------
    // Utilería
    // -------------------------------------------------------------------------

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun decodeArt(bytes: ByteArray?): Bitmap? {
        if (bytes == null || bytes.isEmpty()) return null
        return try {
            val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
            val longest = maxOf(bitmap.width, bitmap.height)
            if (longest <= MAX_ART_SIZE) {
                bitmap
            } else {
                val scale = MAX_ART_SIZE.toFloat() / longest
                Bitmap.createScaledBitmap(
                    bitmap,
                    (bitmap.width * scale).toInt().coerceAtLeast(1),
                    (bitmap.height * scale).toInt().coerceAtLeast(1),
                    true,
                )
            }
        } catch (error: Throwable) {
            // Una carátula corrupta no puede tumbar la notificación.
            Log.w(TAG, "carátula ilegible", error)
            null
        }
    }
}

private const val MAX_ART_SIZE = 1024

private const val ACTION_START = "com.gaboexperimetos.cyberhex.action.START"
private const val ACTION_STOP = "com.gaboexperimetos.cyberhex.action.STOP"
private const val ACTION_PREFIX = "com.gaboexperimetos.cyberhex.action.COMMAND."

private const val COMMAND_PLAY = "play"
private const val COMMAND_PAUSE = "pause"
private const val COMMAND_TOGGLE = "toggle"
private const val COMMAND_NEXT = "next"
private const val COMMAND_PREVIOUS = "previous"

private const val REQUEST_CONTENT = 1
private const val REQUEST_STOP = 2
private const val REQUEST_PREVIOUS = 3
private const val REQUEST_TOGGLE = 4
private const val REQUEST_NEXT = 5
