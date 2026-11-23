package com.gaboexperimetos.cyberhex

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Azulejo de los ajustes rápidos: reproducir o pausar sin abrir la app.
 *
 * [TileService] existe desde **N (24)**; la clase se anota con
 * `@RequiresApi(N)` y el manifiesto la declara con
 * `android:permission="android.permission.BIND_QUICK_SETTINGS_TILE"`, así que
 * en versiones anteriores el sistema ni la carga ni la lista.
 *
 * No guarda estado: el icono sale de [PlaybackCache] (lo que el servicio apuntó)
 * y el toque se traduce en un comando al `MediaSessionService`.
 */
@RequiresApi(Build.VERSION_CODES.N)
class CyberHexTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        val cached = PlaybackCache.snapshot(this)
        val command = if (cached.playing) "toggle" else "play"
        MediaSessionService.sendCommand(this, command)
        // Optimista: el servicio confirmará el estado real en el próximo
        // latido (updateState), que repinta el azulejo.
        updateTile(playing = !cached.playing)
    }

    private fun updateTile(playing: Boolean = PlaybackCache.snapshot(this).playing) {
        val tile = qsTile ?: return
        tile.state = when {
            !PlaybackCache.snapshot(this).hasTrack -> Tile.STATE_INACTIVE
            playing -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        tile.icon = android.graphics.drawable.Icon.createWithResource(
            this,
            if (playing) R.drawable.ic_tile_pause else R.drawable.ic_tile_play,
        )
        tile.label = "CyberHex"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (playing) "Sonando" else "En pausa"
        }
        tile.updateTile()
    }

    companion object {
        /**
         * Pide al sistema que vuelva a llamar a [onStartListening] (si el
         * azulejo está visible). Sin efecto por debajo de N.
         */
        fun refresh(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            runCatching {
                TileService.requestListeningState(
                    context,
                    ComponentName(context, CyberHexTileService::class.java),
                )
            }
        }
    }
}
