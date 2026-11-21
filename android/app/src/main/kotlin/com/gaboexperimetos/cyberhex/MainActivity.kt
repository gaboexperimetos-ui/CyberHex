package com.gaboexperimetos.cyberhex

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Actividad única de CyberHex.
 *
 * Además de hospedar el `FlutterEngine` (donde vive el motor de audio):
 *  * engancha el canal `cyberhex/media` en `configureFlutterEngine` y lo suelta
 *    en `cleanUpFlutterEngine`;
 *  * pide `POST_NOTIFICATIONS` en Android 13+, necesario para que se vea la
 *    notificación de reproducción (sin permiso el servicio sigue sonando, pero
 *    la notificación no se muestra).
 */
class MainActivity : FlutterActivity() {

    private var askedNotifications = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaBridge.connect(flutterEngine, applicationContext)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // El motor se destruye a continuación: el canal deja de ser válido.
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
