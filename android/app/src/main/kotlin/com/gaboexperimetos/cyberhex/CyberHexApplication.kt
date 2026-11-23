package com.gaboexperimetos.cyberhex

import android.app.Application
import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Application de CyberHex: crea el `FlutterEngine` **antes** que cualquier
 * actividad y lo deja en [FlutterEngineCache] bajo [ENGINE_ID].
 *
 * Por qué:
 *  * El motor de audio vive en Dart. Si el motor pertenece a `MainActivity`,
 *    al quitar la app de "Recientes" la actividad se destruye, el motor también
 *    y la música se corta aunque el servicio en primer plano siga vivo.
 *  * Cacheándolo aquí, el isolate de Dart sobrevive a la actividad: cerrar la
 *    ventana solo desengancha la vista, el `MediaSessionService` sigue
 *    publicando la notificación y el audio no se interrumpe.
 *
 * `MainActivity.provideFlutterEngine` devuelve este mismo motor y
 * `shouldDestroyEngineWithHost()` responde `false`, que es el contrato que
 * Flutter exige para no destruir un motor que no creó la actividad.
 *
 * Nota: se extiende `android.app.Application` y no
 * `io.flutter.app.FlutterApplication` porque esta última está deprecada desde
 * Flutter 3.29 y ya no aporta nada (era una subclase vacía de `Application`,
 * con su propio `onCreate` obsoleto); así el build no depende de una API en
 * retirada.
 */
class CyberHexApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        // Arranca Dart (y con él el motor de audio) en cuanto nace el proceso:
        // así la reproducción no depende de que haya una ventana visible.
        ensureEngine(this)
    }

    companion object {
        /** Clave del motor en [FlutterEngineCache]. */
        const val ENGINE_ID = "cyberhex_engine"

        /** Motor cacheado, o `null` si todavía no se creó. */
        fun cachedEngine(): FlutterEngine? = FlutterEngineCache.getInstance().get(ENGINE_ID)

        /**
         * Devuelve el motor cacheado y, si no existe, lo crea, ejecuta su
         * entrypoint por defecto y lo engancha al [MediaBridge].
         *
         * Es idempotente: se puede llamar desde `Application.onCreate` y desde
         * `MainActivity.provideFlutterEngine` sin crear dos motores.
         */
        fun ensureEngine(context: Context): FlutterEngine {
            cachedEngine()?.let { return it }

            val appContext = context.applicationContext ?: context
            val engine = FlutterEngine(appContext)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)

            // El canal se engancha aquí (no en la actividad): los botones del
            // casco y de la notificación tienen que funcionar sin ventana.
            MediaBridge.connect(engine, appContext)
            // Y el de almacenamiento también: Dart pregunta por el directorio
            // de datos en su `main()`, antes de que exista ninguna actividad.
            StorageBridge.connect(engine, appContext)
            return engine
        }
    }
}

/**
 * Canal `cyberhex/storage`: entrega a Dart el directorio privado de la app.
 *
 * Por qué existe: en Android puro en Dart no hay forma de llegar a
 * `context.filesDir` sin `path_provider` (una dependencia más) o sin este
 * canal. `cacheDir` es lo que el sistema puede vaciar cuando le falta espacio,
 * y por eso la sesión y los favoritos se perdían (R14 del informe).
 *
 * Contrato (§8.6): un único método, `getAppDataDir` → `String` con la ruta
 * absoluta de `filesDir`. Si el canal no existe (escritorio, pruebas), Dart
 * cae al temporal y sigue funcionando.
 */
internal object StorageBridge {
    private const val CHANNEL = "cyberhex/storage"
    private const val TAG = "CyberHex.Storage"

    private var channel: MethodChannel? = null

    /** Idempotente: se puede llamar desde la Application y desde la actividad. */
    fun connect(engine: FlutterEngine, context: Context) {
        if (channel != null) return
        val appContext = context.applicationContext ?: context
        val methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppDataDir" -> {
                    val dir = appContext.filesDir
                    if (dir == null) {
                        result.error("sin_directorio", "filesDir no disponible", null)
                    } else {
                        // Se crea por si el sistema limpió la carpeta: escribir
                        // en una ruta que no existe es el otro modo de perder
                        // datos.
                        if (!dir.exists()) dir.mkdirs()
                        Log.i(TAG, "filesDir: ${dir.absolutePath}")
                        result.success(dir.absolutePath)
                    }
                }

                else -> result.notImplemented()
            }
        }
        channel = methodChannel
    }
}
