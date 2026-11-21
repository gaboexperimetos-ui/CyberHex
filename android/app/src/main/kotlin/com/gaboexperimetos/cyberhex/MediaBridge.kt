package com.gaboexperimetos.cyberhex

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Estado de reproducción tal como lo manda Dart con `updateState`.
 *
 * La posición llega ya limitada a 1 Hz por el lado Dart; aquí no se filtra.
 */
class PlayerState(
    val playing: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    val buffering: Boolean,
)

/** Metadatos de la pista actual (`updateMetadata`). `art` puede ser `null`. */
class TrackMetadata(
    val title: String,
    val artist: String,
    val album: String,
    val durationMs: Long,
    val art: ByteArray?,
)

/**
 * Único punto de contacto entre el `MethodChannel` y el servicio.
 *
 * El motor de audio vive en Dart (en el `FlutterEngine` de `MainActivity`), así
 * que Kotlin **nunca** reproduce nada: solo mantiene el proceso en primer plano,
 * pinta la notificación/MediaSession y reenvía botones.
 *
 * Direcciones:
 *  * Dart → Kotlin: `updateMetadata`, `updateState` (+ reservados `setQueue`,
 *    `start`, `stop` de la v1.1; hoy se ignoran con `notImplemented`).
 *  * Kotlin → Dart: `play`, `pause`, `toggle`, `next`, `previous`, `seek`
 *    (segundos, double), `setVolume` (0..1, double), `duck` (bool).
 *
 * Si el canal todavía no existe (motor arrancando, o actividad destruida y
 * servicio vivo) los comandos se encolan y se drenan en [connect] /
 * [sendCommand]; el tope evita crecer sin límite.
 */
object MediaBridge {

    /** Identificador del canal, idéntico a `MediaSessionChannel.channelName` en Dart. */
    const val CHANNEL = "cyberhex/media"

    private const val TAG = "CyberHex.Media"
    private const val MAX_PENDING = 16

    private class Command(val method: String, val argument: Any?)

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var serviceRef: WeakReference<MediaSessionService>? = null

    private val pending = ArrayDeque<Command>()

    /** Último snapshot: se reenvía al servicio cuando se engancha (o se recrea). */
    private var metadata: TrackMetadata? = null
    private var state: PlayerState? = null

    /** ¿Hay un servicio vivo escuchando? */
    val isServiceAlive: Boolean
        get() = serviceRef?.get() != null

    // -------------------------------------------------------------------------
    // Ciclo de vida del canal
    // -------------------------------------------------------------------------

    /**
     * Se llama desde `MainActivity.configureFlutterEngine`: el motor ya existe,
     * así que ya se puede hablar con Dart.
     */
    fun connect(engine: FlutterEngine, context: Context) {
        // Puede llamarse dos veces con el mismo motor: desde la Application
        // (para que el canal exista sin ventana) y desde MainActivity. El
        // handler es el mismo, así que la segunda vez no se hace nada.
        if (channel != null) return
        appContext = context

        val methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateMetadata" -> {
                    val parsed = parseMetadata(call.arguments)
                    if (parsed != null) {
                        metadata = parsed
                        serviceRef?.get()?.onMetadata(parsed)
                    }
                    result.success(true)
                }

                "updateState" -> {
                    val parsed = parseState(call.arguments)
                    if (parsed != null) {
                        state = parsed
                        // Primera vez que suena: hay que subir el servicio a
                        // primer plano (solo se puede desde la app en foreground).
                        if (parsed.playing) ensureServiceStarted()
                        serviceRef?.get()?.onState(parsed)
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
        channel = methodChannel
        flush()
    }

    /** Se llama desde `cleanUpFlutterEngine`: el motor se va a destruir. */
    fun disconnect() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    // -------------------------------------------------------------------------
    // Servicio
    // -------------------------------------------------------------------------

    fun attach(service: MediaSessionService) {
        serviceRef = WeakReference(service)
        // Al recrearse el servicio, se repinta con lo último conocido.
        metadata?.let { service.onMetadata(it) }
        state?.let { service.onState(it) }
    }

    fun detachService(service: MediaSessionService) {
        if (serviceRef?.get() === service) serviceRef = null
    }

    private fun ensureServiceStarted() {
        if (isServiceAlive) return
        appContext?.let { MediaSessionService.start(it) }
    }

    // -------------------------------------------------------------------------
    // Kotlin → Dart
    // -------------------------------------------------------------------------

    fun sendCommand(method: String, argument: Any? = null) {
        val current = channel
        if (current == null) {
            if (pending.size >= MAX_PENDING) pending.removeFirst()
            pending.addLast(Command(method, argument))
            Log.d(TAG, "canal no listo, encolado: $method")
            return
        }
        current.invokeMethod(
            method,
            argument,
            object : MethodChannel.Result {
                override fun success(result: Any?) = Unit

                override fun error(code: String, message: String?, details: Any?) {
                    Log.w(TAG, "$method: $code $message")
                }

                override fun notImplemented() {
                    Log.w(TAG, "$method: no implementado en Dart")
                }
            },
        )
    }

    /** Envía en segundos, como espera el lado Dart. */
    fun sendSeek(positionMs: Long) {
        sendCommand("seek", positionMs.coerceAtLeast(0L) / 1000.0)
    }

    private fun flush() {
        while (channel != null && pending.isNotEmpty()) {
            val command = pending.removeFirst()
            sendCommand(command.method, command.argument)
        }
    }

    // -------------------------------------------------------------------------
    // Parseo de argumentos
    // -------------------------------------------------------------------------

    private fun parseMetadata(arguments: Any?): TrackMetadata? {
        val map = arguments as? Map<*, *> ?: return null
        return TrackMetadata(
            title = map["title"] as? String ?: "CyberHex",
            artist = map["artist"] as? String ?: "",
            album = map["album"] as? String ?: "",
            durationMs = (map["durationMs"] as? Number)?.toLong() ?: 0L,
            art = map["art"] as? ByteArray,
        )
    }

    private fun parseState(arguments: Any?): PlayerState? {
        val map = arguments as? Map<*, *> ?: return null
        return PlayerState(
            playing = map["playing"] as? Boolean ?: false,
            positionMs = (map["positionMs"] as? Number)?.toLong() ?: 0L,
            durationMs = (map["durationMs"] as? Number)?.toLong() ?: 0L,
            buffering = map["buffering"] as? Boolean ?: false,
        )
    }
}
