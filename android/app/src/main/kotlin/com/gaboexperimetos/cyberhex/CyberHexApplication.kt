package com.gaboexperimetos.cyberhex

import android.app.Application
import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

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
            return engine
        }
    }
}
