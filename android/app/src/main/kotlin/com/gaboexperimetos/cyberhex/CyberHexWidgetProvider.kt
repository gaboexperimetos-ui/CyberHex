package com.gaboexperimetos.cyberhex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

/**
 * Widget de la pantalla de inicio, versión **4x1** (barra fina): carátula,
 * título, anterior / play-pausa / siguiente y una línea de progreso.
 *
 * No reproduce ni guarda estado propio: pinta [PlaybackCache] —lo que el
 * `MediaSessionService` apuntó la última vez— y sus botones son
 * `PendingIntent`s al servicio, que es el único que habla con Dart. Así el
 * widget funciona aunque la UI esté cerrada y no duplica la lógica de mando.
 *
 * `FLAG_IMMUTABLE` existe desde M (23) y es **obligatorio** desde S (31) para
 * los `PendingIntent` que apuntan a la propia app: se pide según SDK.
 */
open class CyberHexWidgetProvider : AppWidgetProvider() {

    /** Layout de esta variante; la subclase de 4x2 lo cambia. */
    protected open val layoutRes: Int
        get() = R.layout.widget_small

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val views = buildViews(context)
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** El usuario cambió el tamaño: se repinta con el mismo layout. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        appWidgetManager.updateAppWidget(appWidgetId, buildViews(context))
    }

    /** Primer widget colocado: el azulejo rápido pasa a existir. */
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // Con API < 24 la clase del azulejo no se puede ni cargar.
            CyberHexTileService.refresh(context)
        }
    }

    /** Pinta la instantánea actual guardada en disco. */
    fun buildViews(context: Context): RemoteViews {
        val cached = PlaybackCache.snapshot(context)
        val views = RemoteViews(context.packageName, layoutRes)

        views.setTextViewText(R.id.widget_title, cached.title.ifBlank { "CyberHex" })
        views.setTextViewText(
            R.id.widget_artist,
            cached.artist.ifBlank {
                when {
                    !cached.hasTrack -> "Elige una pista en la app"
                    cached.playing -> "Sonando"
                    else -> "En pausa"
                }
            },
        )
        views.setImageViewResource(
            R.id.widget_toggle,
            if (cached.playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
        )
        views.setContentDescription(
            R.id.widget_toggle,
            if (cached.playing) "Pausa" else "Reproducir",
        )

        val art = PlaybackCache.art(context, maxSize = 192)
        if (art != null) {
            views.setImageViewBitmap(R.id.widget_art, art)
        } else {
            views.setImageViewResource(R.id.widget_art, R.drawable.ic_launcher_foreground)
        }

        val duration = cached.durationMs.coerceAtLeast(0L)
        // `max` va en milisegundos y como Int: se recorta a 24 h para que no
        // desborde en pistas con duración absurda.
        val max = duration.coerceAtMost(24L * 60 * 60 * 1000).toInt()
        if (max > 0) {
            val progress = cached.positionMs.coerceIn(0L, max.toLong()).toInt()
            views.setProgressBar(R.id.widget_progress, max, progress, false)
        } else {
            views.setViewVisibility(R.id.widget_progress, View.INVISIBLE)
        }

        views.setOnClickPendingIntent(
            R.id.widget_previous,
            commandPendingIntent(context, "previous", REQUEST_PREVIOUS),
        )
        views.setOnClickPendingIntent(
            R.id.widget_toggle,
            commandPendingIntent(context, "toggle", REQUEST_TOGGLE),
        )
        views.setOnClickPendingIntent(
            R.id.widget_next,
            commandPendingIntent(context, "next", REQUEST_NEXT),
        )
        views.setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent(context))

        return views
    }

    companion object {
        private const val REQUEST_OPEN = 11
        private const val REQUEST_PREVIOUS = 12
        private const val REQUEST_TOGGLE = 13
        private const val REQUEST_NEXT = 14

        /** Repinta todas las instancias de los dos tamaños. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val small = CyberHexWidgetProvider().buildViews(context)
            for (id in manager.getAppWidgetIds(ComponentName(context, CyberHexWidgetProvider::class.java))) {
                manager.updateAppWidget(id, small)
            }
            val large = CyberHexWidgetLargeProvider().buildViews(context)
            for (id in manager.getAppWidgetIds(ComponentName(context, CyberHexWidgetLargeProvider::class.java))) {
                manager.updateAppWidget(id, large)
            }
        }

        internal fun commandPendingIntent(
            context: Context,
            command: String,
            requestCode: Int,
        ): PendingIntent {
            val intent = Intent(context, MediaSessionService::class.java)
                .setAction(MediaSessionService.ACTION_COMMAND_PREFIX + command)
            return PendingIntent.getService(context, requestCode, intent, pendingFlags())
        }

        internal fun openAppPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(context, REQUEST_OPEN, intent, pendingFlags())
        }

        /**
         * `FLAG_IMMUTABLE` desde M; antes no existe y no se pide. Nunca
         * `FLAG_MUTABLE`: el intent es nuestro y no necesita que lo rellenen.
         */
        internal fun pendingFlags(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
    }
}

/**
 * Widget 4x2: carátula grande, título, artista y barra de progreso.
 *
 * Es una subclase porque Android identifica cada widget por su clase y hacen
 * falta **dos** `<receiver>` en el manifiesto (uno por tamaño).
 */
class CyberHexWidgetLargeProvider : CyberHexWidgetProvider() {

    override val layoutRes: Int
        get() = R.layout.widget_large
}
