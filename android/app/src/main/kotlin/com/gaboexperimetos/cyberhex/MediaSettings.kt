package com.gaboexperimetos.cyberhex

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import java.io.File

/**
 * Acciones que el usuario puede poner en la notificación.
 *
 * [command] es el que entiende `MediaSessionService.dispatch`; [icon] es el del
 * sistema (`android.R.drawable`), porque la app no trae iconos de transporte.
 */
enum class MediaAction(val id: String, val label: String, val icon: Int, val command: String) {
    previous("previous", "Anterior", android.R.drawable.ic_media_previous, "previous"),
    toggle("toggle", "Reproducir / pausa", android.R.drawable.ic_media_play, "toggle"),
    next("next", "Siguiente", android.R.drawable.ic_media_next, "next"),
    stop("stop", "Cerrar", android.R.drawable.ic_menu_close_clear_cancel, "stop"),
    ;

    companion object {
        /** Orden canónico: es el que se pinta y el que se guarda. */
        val ORDER: List<MediaAction> = listOf(previous, toggle, next, stop)

        fun fromId(id: String?): MediaAction? = ORDER.firstOrNull { it.id == id }
    }
}

/**
 * Ajustes de la capa Android que el usuario elige en la app (`SettingsPage`).
 *
 * Viven en `SharedPreferences` y no en el lado Dart porque los leen piezas que
 * pueden despertar sin UI: el widget, el azulejo rápido y el propio servicio.
 * Dart los envía con el método `configure` del canal `cyberhex/media`.
 */
object MediaSettings {

    private const val TAG = "CyberHex.Media"
    private const val PREFS = "cyberhex_media"

    private const val KEY_AUTO_PLAY = "auto_play_on_connect"
    private const val KEY_ACTIONS = "notification_actions"

    /** Sin elección del usuario: las tres de siempre. */
    private val DEFAULTS: List<MediaAction> =
        listOf(MediaAction.previous, MediaAction.toggle, MediaAction.next)

    fun preferences(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // -------------------------------------------------------------------------
    // Auto-play al conectar auriculares o Bluetooth
    // -------------------------------------------------------------------------

    fun autoPlayOnConnect(context: Context): Boolean =
        preferences(context).getBoolean(KEY_AUTO_PLAY, false)

    fun setAutoPlayOnConnect(context: Context, enabled: Boolean) {
        preferences(context).edit().putBoolean(KEY_AUTO_PLAY, enabled).apply()
    }

    // -------------------------------------------------------------------------
    // Acciones de la notificación
    // -------------------------------------------------------------------------

    /**
     * Acciones elegidas, en el orden canónico.
     *
     * `toggle` está **siempre**: una notificación de reproducción sin
     * play/pausa no sirve. Se guardan como cadena separada por comas porque
     * `StringSet` no conserva el orden.
     */
    fun notificationActions(context: Context): List<MediaAction> {
        val raw = preferences(context).getString(KEY_ACTIONS, null) ?: return DEFAULTS
        val parsed = sanitize(raw.split(',').map { it.trim() })
        return parsed.ifEmpty { DEFAULTS }
    }

    fun setNotificationActions(context: Context, actions: List<MediaAction>) {
        val value = sanitize(actions.map { it.id }).joinToString(",") { it.id }
        preferences(context).edit().putString(KEY_ACTIONS, value).apply()
    }

    /** Descarta ids desconocidos y duplicados y garantiza `toggle`. */
    private fun sanitize(ids: List<String>): List<MediaAction> {
        val chosen = ids.mapNotNull { MediaAction.fromId(it) }.toSet() + MediaAction.toggle
        return MediaAction.ORDER.filter { it in chosen }
    }

    // -------------------------------------------------------------------------
    // Entrada desde Dart: `configure`
    // -------------------------------------------------------------------------

    /**
     * Aplica el mapa que manda Dart y devuelve `true` si cambió algo (para que
     * el servicio repinte la notificación). Los campos ausentes se dejan como
     * estaban.
     */
    fun apply(context: Context, arguments: Any?): Boolean {
        val map = arguments as? Map<*, *> ?: return false
        var changed = false

        (map["autoPlayOnConnect"] as? Boolean)?.let { enabled ->
            if (enabled != autoPlayOnConnect(context)) {
                setAutoPlayOnConnect(context, enabled)
                changed = true
            }
        }

        @Suppress("UNCHECKED_CAST")
        val rawActions = map["notificationActions"] as? List<Any?>
        if (rawActions != null) {
            val ids = rawActions.mapNotNull { it as? String }
            val actions = sanitize(ids)
            if (actions != notificationActions(context)) {
                setNotificationActions(context, actions)
                changed = true
            }
        } else if (map.containsKey("notificationActions")) {
            Log.w(TAG, "notificationActions con tipo inesperado")
        }

        return changed
    }

    /** Ids en el formato que espera Dart. */
    fun actionIds(context: Context): List<String> = notificationActions(context).map { it.id }
}

/** Lo último que el servicio supo de la reproducción, para el widget. */
class CachedPlayback(
    val title: String,
    val artist: String,
    val album: String,
    val playing: Boolean,
    val positionMs: Long,
    val durationMs: Long,
) {
    val hasTrack: Boolean
        get() = title.isNotBlank() && title != "CyberHex"
}

/**
 * Caché de reproducción en disco.
 *
 * El widget y el azulejo se despiertan sin que el servicio esté vivo, así que
 * no pueden preguntarle: leen lo último guardado. La carátula va a un archivo
 * (`filesDir`), no a `SharedPreferences` — un JPEG de portada no cabe con
 * gracia en el XML de preferencias.
 */
object PlaybackCache {

    private const val PREFS = "cyberhex_media"
    private const val KEY_TITLE = "last_title"
    private const val KEY_ARTIST = "last_artist"
    private const val KEY_ALBUM = "last_album"
    private const val KEY_PLAYING = "last_playing"
    private const val KEY_POSITION = "last_position_ms"
    private const val KEY_DURATION = "last_duration_ms"
    private const val ART_FILE = "widget_art.png"
    private const val TAG = "CyberHex.Media"

    fun save(context: Context, metadata: TrackMetadata?, state: PlayerState) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val editor = prefs.edit()
            .putString(KEY_TITLE, metadata?.title ?: "")
            .putString(KEY_ARTIST, metadata?.artist ?: "")
            .putString(KEY_ALBUM, metadata?.album ?: "")
            .putBoolean(KEY_PLAYING, state.playing)
            .putLong(KEY_POSITION, state.positionMs)
            .putLong(KEY_DURATION, metadata?.durationMs ?: state.durationMs)
        editor.apply()

        val art = metadata?.art
        if (art != null && art.isNotEmpty()) writeArt(context, art)
    }

    fun snapshot(context: Context): CachedPlayback {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return CachedPlayback(
            title = prefs.getString(KEY_TITLE, "") ?: "",
            artist = prefs.getString(KEY_ARTIST, "") ?: "",
            album = prefs.getString(KEY_ALBUM, "") ?: "",
            playing = prefs.getBoolean(KEY_PLAYING, false),
            positionMs = prefs.getLong(KEY_POSITION, 0L),
            durationMs = prefs.getLong(KEY_DURATION, 0L),
        )
    }

    /** Vuelve a pausa: el proceso murió mientras sonaba. */
    fun markPaused(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PLAYING, false)
            .apply()
    }

    fun art(context: Context, maxSize: Int = 256): Bitmap? {
        val file = File(context.filesDir, ART_FILE)
        if (!file.exists()) return null
        return try {
            val options = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
            val bitmap = BitmapFactory.decodeFile(file.absolutePath, options) ?: return null
            val longest = maxOf(bitmap.width, bitmap.height)
            if (longest <= maxSize) {
                bitmap
            } else {
                val scale = maxSize.toFloat() / longest
                Bitmap.createScaledBitmap(
                    bitmap,
                    (bitmap.width * scale).toInt().coerceAtLeast(1),
                    (bitmap.height * scale).toInt().coerceAtLeast(1),
                    true,
                )
            }
        } catch (error: Throwable) {
            Log.w(TAG, "carátula del widget ilegible", error)
            null
        }
    }

    private fun writeArt(context: Context, bytes: ByteArray) {
        // Se llama solo cuando cambian los metadatos (pista nueva, carátula
        // nueva), no en cada latido del estado.
        val file = File(context.filesDir, ART_FILE)
        try {
            file.writeBytes(bytes)
        } catch (error: Throwable) {
            Log.w(TAG, "no se pudo guardar la carátula del widget", error)
        }
    }
}
