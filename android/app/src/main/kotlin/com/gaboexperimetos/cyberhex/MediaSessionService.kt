package com.gaboexperimetos.cyberhex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.bluetooth.BluetoothDevice
import android.view.KeyEvent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession.Token
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
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

        /**
         * Prefijo de los intents que llevan un comando en el `action`. Público
         * porque el widget y el azulejo lo usan para no tener que exportar
         * métodos del servicio.
         */
        const val ACTION_COMMAND_PREFIX = "com.gaboexperimetos.cyberhex.action.COMMAND."

        /**
         * Token de la sesión en curso, o `null` si el servicio no está vivo.
         * Lo lee [CyberHexBrowserService] para enganchar el transporte del
         * coche; se publica en `onCreate` y se limpia en `onDestroy`.
         */
        @Volatile
        var token: Token? = null
            private set

        /** Aviso de sesión lista (para que el navegador de medios reconecte). */
        @Volatile
        var onSessionReady: ((Token) -> Unit)? = null

        /**
         * Manda un comando sin que el emisor tenga que saber si el servicio
         * está vivo: arranca el servicio (ligero, sin primer plano) y el mismo
         * `onStartCommand` lo despacha. Lo usan widget, azulejo y notificación.
         */
        fun sendCommand(context: Context, command: String) {
            val intent = Intent(context, MediaSessionService::class.java)
                .setAction(ACTION_COMMAND_PREFIX + command)
            try {
                context.startService(intent)
            } catch (error: Throwable) {
                // Android 8+ puede vetar startService en segundo plano. No se
                // usa startForegroundService aquí a propósito: si el comando
                // no llega a reproducir nada, no habría startForeground y el
                // sistema mataría el proceso. Se pierde el toque y se anota.
                Log.w(TAG, "startService rechazado: ${error.message}")
            }
        }

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

    private var headsetReceiver: BroadcastReceiver? = null

    // Doble y triple pulsación del botón del casco.
    private val clickHandler = Handler(Looper.getMainLooper())
    private var clickCount = 0
    private val clickRunnable = Runnable {
        val count = clickCount
        clickCount = 0
        when (count) {
            1 -> dispatch(COMMAND_TOGGLE)
            2 -> dispatch(COMMAND_NEXT)
            else -> dispatch(COMMAND_PREVIOUS)
        }
    }

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

        // La sesión existe: se publica para el navegador de medios del coche.
        token = session.sessionToken
        onSessionReady?.invoke(session.sessionToken)

        createNotificationChannel()
        registerNoisyReceiver()
        registerHeadsetReceiver()

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
                // Viene de fuera (widget, azulejo, notificación): puede que
                // Dart aún no esté escuchando, y entonces hay que abrir la app.
                dispatch(action.removePrefix(ACTION_PREFIX), external = true)
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
        headsetReceiver?.let {
            runCatching { unregisterReceiver(it) }
            headsetReceiver = null
        }
        clickHandler.removeCallbacks(clickRunnable)
        abandonFocus()
        token = null

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
        PlaybackCache.save(this, metadata, state)
        widgetsChanged()
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

        // Guardar y repintar en cada latido gastaría flash y batería por nada:
        // el widget avanza con la reproducción, no con el reloj. Basta con
        // apuntar al cambiar play/pausa o cada [CACHE_STEP_MS] de posición.
        val cacheNeeded = newState.playing != previous.playing ||
            (newState.positionMs / CACHE_STEP_MS) != (previous.positionMs / CACHE_STEP_MS)
        if (cacheNeeded) {
            PlaybackCache.save(this, metadata, state)
            widgetsChanged()
        }
    }

    /** Repinta widget y azulejo con la instantánea recién guardada. */
    private fun widgetsChanged() {
        runCatching { CyberHexWidgetProvider.refreshAll(this) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // Cargar la clase del azulejo en API < 24 revienta (TileService no
            // existe): se comprueba antes de nombrarla.
            runCatching { CyberHexTileService.refresh(this) }
        }
    }

    /** Dart pidió cambiar los ajustes de la capa Android (`configure`). */
    fun onSettingsChanged() {
        updateNotification()
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

        /**
         * Botones del casco y de los auriculares Bluetooth.
         *
         * Un clic salta «toggle», **dos clics seguidos → siguiente** y **tres →
         * anterior**, que es lo que hace la mayoría de reproductores. El
         * primer clic espera [MULTI_CLICK_DELAY_MS] para saber si viene otro;
         * ese retardo es el precio de distinguir 1 de 2.
         */
        override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
            @Suppress("DEPRECATION")
            val event = mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT) as? KeyEvent
                ?: return super.onMediaButtonEvent(mediaButtonIntent)
            val code = event.keyCode
            val relevant = code == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE ||
                code == KeyEvent.KEYCODE_HEADSETHOOK ||
                code == KeyEvent.KEYCODE_MEDIA_PLAY ||
                code == KeyEvent.KEYCODE_MEDIA_PAUSE
            if (!relevant) return super.onMediaButtonEvent(mediaButtonIntent)
            if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount > 0) return true

            clickCount = (clickCount + 1).coerceAtMost(3)
            clickHandler.removeCallbacks(clickRunnable)
            clickHandler.postDelayed(clickRunnable, MULTI_CLICK_DELAY_MS)
            return true
        }
    }

    /**
     * Traduce un comando a la llamada del canal. Si [external] (widget,
     * azulejo, notificación) y Dart todavía no tiene manejador —la app no se
     * abrió nunca o el proceso acaba de renacer— no hay a quién mandárselo: se
     * abre la app, que restaura la sesión y ya recibe los botones.
     */
    private fun dispatch(command: String, external: Boolean = false) {
        when (command) {
            COMMAND_PLAY, COMMAND_PAUSE, COMMAND_TOGGLE,
            COMMAND_NEXT, COMMAND_PREVIOUS -> {
                if (external && !MediaBridge.dartReady) {
                    Log.i(TAG, "sin Dart para '$command': se abre la app")
                    openApp()
                    return
                }
                MediaBridge.sendCommand(command)
            }

            COMMAND_STOP -> shutdownPlayback()

            else -> Log.w(TAG, "comando desconocido: $command")
        }
    }

    /** Abre la actividad principal desde el servicio. */
    private fun openApp() {
        runCatching {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
            )
        }.onFailure { Log.w(TAG, "no se pudo abrir la app", it) }
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
    // Auriculares y Bluetooth
    // -------------------------------------------------------------------------

    /**
     * Auto-play configurable al conectar.
     *
     * `ACTION_HEADSET_PLUG` (cable) y `BluetoothDevice.ACTION_ACL_CONNECTED`
     * llegan aquí. El de Bluetooth solo se escucha si hay permiso
     * `BLUETOOTH_CONNECT` (Android 12+; lo pide `MainActivity` al arrancar): sin
     * él el sistema no lo entrega y registrarlo sería un filtro muerto. Solo se
     * manda `play` si el usuario lo activó **y** había una
     * pista en pausa (nunca se arranca de la nada ni se interrumpe lo que ya
     * suena). `EXTRA_STATE` de la clavija se ignora: en Android moderno llega
     * `STATE_UNPLUGGED/PLUGGED` sin fiabilidad según el fabricante, y para
     * desconectar ya está `ACTION_AUDIO_BECOMING_NOISY`.
     */
    private fun registerHeadsetReceiver() {
        if (headsetReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (!MediaSettings.autoPlayOnConnect(this@MediaSessionService)) return
                if (state.playing) return
                val cached = PlaybackCache.snapshot(this@MediaSessionService)
                if (!cached.hasTrack) return
                Log.d(TAG, "auto-play por ${intent?.action}")
                MediaBridge.sendCommand(COMMAND_PLAY)
            }
        }
        val filter = IntentFilter().apply {
            addAction(AudioManager.ACTION_HEADSET_PLUG)
            if (canWatchBluetooth()) addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        headsetReceiver = receiver
    }

    /**
     * ¿Podemos recibir `ACTION_ACL_CONNECTED`?
     *
     * Desde Android 12 es un broadcast protegido: sin `BLUETOOTH_CONNECT`
     * concedido no llega nada (R32). Antes de Android 12 no hacía falta.
     */
    private fun canWatchBluetooth(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

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
            // Icono hexagonal propio (adaptive foreground monocromo): el del
            // sistema (android.R.drawable.ic_media_play) no identificaba la app.
            .setSmallIcon(R.drawable.ic_launcher_foreground)
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

        // Acciones elegidas por el usuario (SettingsPage → «Notificación»):
        // anterior / play-pausa / siguiente / cerrar, siempre con play-pausa.
        val actions = MediaSettings.notificationActions(this)
        val compact = ArrayList<Int>(3)
        for (action in actions) {
            val (icon, label, pending) = when (action) {
                MediaAction.previous -> Triple(
                    android.R.drawable.ic_media_previous,
                    "Anterior",
                    commandPendingIntent(COMMAND_PREVIOUS, REQUEST_PREVIOUS),
                )

                MediaAction.toggle -> Triple(
                    if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                    if (playing) "Pausa" else "Reproducir",
                    commandPendingIntent(COMMAND_TOGGLE, REQUEST_TOGGLE),
                )

                MediaAction.next -> Triple(
                    android.R.drawable.ic_media_next,
                    "Siguiente",
                    commandPendingIntent(COMMAND_NEXT, REQUEST_NEXT),
                )

                MediaAction.stop -> Triple(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Cerrar",
                    commandPendingIntent(COMMAND_STOP, REQUEST_STOP_ACTION),
                )
            }
            if (compact.size < 3) compact.add(builder.actionCount)
            builder.addAction(Notification.Action.Builder(icon, label, pending).build())
        }

        builder.setStyle(
            Notification.MediaStyle()
                .setMediaSession(session.sessionToken)
                .setShowActionsInCompactView(*compact.toIntArray()),
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
private const val ACTION_PREFIX = MediaSessionService.ACTION_COMMAND_PREFIX

private const val COMMAND_PLAY = "play"
private const val COMMAND_PAUSE = "pause"
private const val COMMAND_TOGGLE = "toggle"
private const val COMMAND_NEXT = "next"
private const val COMMAND_PREVIOUS = "previous"
private const val COMMAND_STOP = "stop"

private const val REQUEST_CONTENT = 1
private const val REQUEST_STOP = 2
private const val REQUEST_PREVIOUS = 3
private const val REQUEST_TOGGLE = 4
private const val REQUEST_NEXT = 5
private const val REQUEST_STOP_ACTION = 6

/** Ventana para contar clics del botón del casco (2 = siguiente, 3 = anterior). */
private const val MULTI_CLICK_DELAY_MS = 420L

/** Cada cuántos ms de posición se vuelca el estado al widget. */
private const val CACHE_STEP_MS = 5_000L
