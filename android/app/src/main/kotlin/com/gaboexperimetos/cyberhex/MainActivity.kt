package com.gaboexperimetos.cyberhex

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Actividad única de CyberHex.
 *
 * No crea su propio `FlutterEngine`: usa el que cachea
 * [CyberHexApplication] (ver [provideFlutterEngine]) y pide que no se destruya
 * al desmontar la vista ([shouldDestroyEngineWithHost]), para que la música
 * siga sonando al cerrar desde "Recientes".
 *
 * Además:
 *  * engancha el canal `cyberhex/media` en `configureFlutterEngine` (idempotente,
 *    porque el motor ya viene enganchado desde la Application);
 *  * pide `POST_NOTIFICATIONS` en Android 13+, necesario para que se vea la
 *    notificación de reproducción (sin permiso el servicio sigue sonando, pero
 *    la notificación no se muestra);
 *  * recibe `ACTION_VIEW` (tocar un audio en el explorador, en WhatsApp, en
 *    "Compartir con..."), convierte el `content://` en un archivo real dentro
 *    de `cacheDir/shared_audio` y lo entrega a Dart por el canal
 *    `cyberhex/intent`.
 */
class MainActivity : FlutterActivity() {

    private var askedNotifications = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        flutterEngine?.let { IntentBridge.attach(it) }
        if (savedInstanceState == null) {
            // Solo en el arranque real: al recrearse (rotación, tema) el
            // intent se redespacha y volveríamos a abrir el mismo archivo.
            deliverViewIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverViewIntent(intent)
    }

    /** El motor lo posee la Application: la actividad solo lo reutiliza. */
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        CyberHexApplication.ensureEngine(context)

    /**
     * `false` = al destruirse la actividad **no** se destruye el motor (ni el
     * isolate de Dart, ni el hilo de audio). Es lo que mantiene la reproducción
     * viva cuando el usuario desliza CyberHex fuera de "Aplicaciones recientes".
     */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaBridge.connect(flutterEngine, applicationContext)
        IntentBridge.attach(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Solo se llama cuando el motor se destruye de verdad (aquí nunca, por
        // shouldDestroyEngineWithHost = false); si algún día pasara, el canal
        // deja de ser válido y hay que soltarlo.
        MediaBridge.disconnect()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onPostResume() {
        super.onPostResume()
        // Se pide aquí (no en onCreate) para que la actividad ya esté en primer
        // plano y el diálogo no se descarte.
        if (askedNotifications) return
        askedNotifications = true
        requestNotificationPermission()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    // ---------------------------------------------------------------------
    // Abrir archivos de audio desde el sistema
    // ---------------------------------------------------------------------

    private fun deliverViewIntent(intent: Intent?) {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val path = resolveAudioPath(uri)
        if (path == null) {
            Log.w(TAG, "no pude resolver el archivo: $uri")
            return
        }
        Log.i(TAG, "abriendo desde el sistema: $path")
        IntentBridge.deliver(path)
    }

    /** `content://` (otros procesos) no es una ruta POSIX: hay que copiarlo. */
    private fun resolveAudioPath(uri: Uri): String? = when (uri.scheme?.lowercase()) {
        "content" -> copyToCacheDir(uri)
        "file" -> uri.path
        else -> uri.path?.takeIf { it.isNotBlank() }
    }

    private fun copyToCacheDir(uri: Uri): String? {
        val directory = File(cacheDir, SHARED_AUDIO_DIR).apply { mkdirs() }
        // Nombre estable por URI: si el usuario reabre lo mismo, no se duplica.
        val name = "shared_" + Integer.toHexString(uri.toString().hashCode()) +
            "." + guessExtension(uri)
        val target = File(directory, name)
        if (target.length() > 0) return target.absolutePath
        return try {
            // El núcleo abre rutas POSIX; necesita el archivo entero en disco.
            contentResolver.openInputStream(uri)?.use { source ->
                FileOutputStream(target).use { sink -> source.copyTo(sink) }
            } ?: return null
            if (target.length() > 0) target.absolutePath else null
        } catch (error: Exception) {
            Log.w(TAG, "no pude copiar $uri al caché", error)
            target.delete()
            null
        }
    }

    /**
     * Extensión para el archivo temporal.
     *
     * Miniaudio y FFmpeg identifican el formato por el contenido, así que el
     * sufijo solo es una pista; aun así se busca la real (MIME, luego nombre).
     */
    private fun guessExtension(uri: Uri): String {
        mimeToExtension(contentResolver.getType(uri))?.let { return it }
        val extension = displayName(uri)
            ?.substringAfterLast('.', "")
            ?.lowercase()
            .orEmpty()
        if (extension.length in 2..5 && extension.all { it.isLetterOrDigit() }) {
            return extension
        }
        return "mp3"
    }

    private fun mimeToExtension(mime: String?): String? = when (mime?.lowercase()) {
        "audio/mpeg", "audio/mp3", "audio/x-mp3" -> "mp3"
        "audio/flac", "audio/x-flac" -> "flac"
        "audio/aac", "audio/mp4", "audio/m4a", "audio/x-m4a" -> "m4a"
        "audio/ogg", "audio/vorbis", "audio/x-vorbis+ogg", "application/ogg" -> "ogg"
        "audio/opus" -> "opus"
        "audio/wav", "audio/x-wav", "audio/wave" -> "wav"
        "audio/ape", "audio/x-ape" -> "ape"
        "audio/wavpack" -> "wv"
        else -> null
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme != "content") return uri.lastPathSegment
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        } catch (error: Exception) {
            null
        }
    }

    private companion object {
        const val TAG = "CyberHex.Intent"
        const val REQUEST_NOTIFICATIONS = 0x4E
        const val SHARED_AUDIO_DIR = "shared_audio"
    }
}

/**
 * Canal `cyberhex/intent`: entrega a Dart la ruta de un audio abierto desde
 * fuera de la app (explorador de archivos, WhatsApp, "Compartir con...").
 *
 * Hay una carrera real: el `Intent` puede llegar antes de que Dart esté
 * escuchando (el motor arranca en la Application). Por eso el primer archivo se
 * guarda como *pendiente* y lo recoge `getInitialFile`; a partir de ahí, si Dart
 * ya preguntó, se empuja con `onOpenFile`.
 */
private object IntentBridge {
    private const val CHANNEL = "cyberhex/intent"

    private var channel: MethodChannel? = null
    private var pendingPath: String? = null
    private var dartAskedInitial = false

    /** Idempotente: se llama desde `onCreate` y desde `configureFlutterEngine`. */
    fun attach(engine: FlutterEngine) {
        if (channel != null) return
        val methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    dartAskedInitial = true
                    val path = pendingPath
                    pendingPath = null
                    result.success(path)
                }

                else -> result.notImplemented()
            }
        }
        channel = methodChannel
    }

    fun deliver(path: String) {
        val methodChannel = channel
        if (methodChannel == null || !dartAskedInitial) {
            pendingPath = path
            return
        }
        methodChannel.invokeMethod("onOpenFile", path)
    }
}
