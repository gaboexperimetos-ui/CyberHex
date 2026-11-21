package com.gaboexperimetos.cyberhex

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

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
 *    la notificación no se muestra).
 */
class MainActivity : FlutterActivity() {

    private var askedNotifications = false

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

    private companion object {
        const val REQUEST_NOTIFICATIONS = 0x4E
    }
}
