package com.gaboexperimetos.cyberhex

import android.media.MediaDescription
import android.media.browse.MediaBrowser
import android.media.session.MediaSession
import android.os.Bundle
import android.service.media.MediaBrowserService
import android.util.Log

/**
 * `MediaBrowserService` **del sistema** (API 21+, sin AndroidX) para que
 * Android Auto y los coches con `MediaBrowser` vean a CyberHex como fuente de
 * audio.
 *
 * El servicio no tiene catálogo propio: la biblioteca y las colas las maneja
 * Dart, y aquí no se puede pedir nada a Dart de forma síncrona sin montar otro
 * canal. Así que publica:
 *
 *  * raíz `cyberhex_root` con un único hijo `cyberhex_now` («Lo que suena»);
 *  * ese hijo, la pista actual según [PlaybackCache], con título, artista y
 *    duración.
 *
 * El transporte lo pone el sistema a través del **token de la MediaSession**
 * ([MediaSessionService.token]): los botones del coche acaban en los mismos
 * `onPlay`/`onPause`/`onSkipToNext` que los del casco, sin código nuevo.
 *
 * Limitación conocida: el token solo existe cuando el `MediaSessionService`
 * ya arrancó al menos una vez (se publica en `onCreate`). Si el coche pide la
 * raíz antes, [onGetRoot] devuelve `null` y el sistema reintenta.
 */
class CyberHexBrowserService : MediaBrowserService() {

    companion object {
        private const val TAG = "CyberHex.Browser"

        const val ROOT_ID = "cyberhex_root"
        private const val NOW_ID = "cyberhex_now"
    }

    override fun onCreate() {
        super.onCreate()
        val token: MediaSession.Token? = MediaSessionService.token
        if (token == null) {
            Log.i(TAG, "sin sesión todavía: la raíz no se publica")
        } else {
            sessionToken = token
        }
        // El sistema puede reconectar; se le da la sesión del servicio de medios.
        MediaSessionService.onSessionReady = { fresh ->
            sessionToken = fresh
        }
    }

    override fun onDestroy() {
        MediaSessionService.onSessionReady = null
        super.onDestroy()
    }

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?,
    ): BrowserRoot? {
        if (sessionToken == null) return null
        return BrowserRoot(ROOT_ID, null)
    }

    override fun onLoadChildren(
        parentMediaId: String,
        result: Result<List<MediaBrowser.MediaItem>>,
    ) {
        val items = when (parentMediaId) {
            ROOT_ID -> listOf(
                MediaBrowser.MediaItem(
                    MediaDescription.Builder()
                        .setMediaId(NOW_ID)
                        .setTitle("Lo que suena")
                        .setSubtitle("CyberHex")
                        .setIconUri(null)
                        .build(),
                    MediaBrowser.MediaItem.FLAG_BROWSABLE,
                ),
            )

            NOW_ID -> {
                val cached = PlaybackCache.snapshot(this)
                if (!cached.hasTrack) {
                    emptyList()
                } else {
                    val description = MediaDescription.Builder()
                        .setMediaId(NOW_ID)
                        .setTitle(cached.title)
                        .setSubtitle(cached.artist)
                        .setDescription(cached.album.takeIf { it.isNotBlank() })
                        .build()
                    listOf(
                        MediaBrowser.MediaItem(
                            description,
                            MediaBrowser.MediaItem.FLAG_PLAYABLE,
                        ),
                    )
                }
            }

            else -> emptyList()
        }
        result.sendResult(items)
    }
}
