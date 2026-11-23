#ifndef CYBERHEX_MPRIS_BRIDGE_H_
#define CYBERHEX_MPRIS_BRIDGE_H_

// Puente MPRIS2 (D-Bus) del runner de Linux.
//
// El audio sigue viviendo en Dart: este archivo solo publica
// `org.mpris.MediaPlayer2.cyberhex` en la sesión de D-Bus y traduce lo que piden
// los clientes (kded, GSConnect, playerctl, la tecla «multimedia» del teclado,
// el plasmoid...) a comandos de texto que el lado Flutter reenvía al
// PlayerController. Sin D-Bus de sesión (SSH, sesión sin escritorio) todas las
// funciones son no-op y no se registra nada.

#include <glib.h>

G_BEGIN_DECLS

typedef struct _MprisBridge MprisBridge;

/**
 * MprisCommandCallback:
 * @command: orden en texto, con argumento opcional tras `:`.
 * @user_data: lo que se pasó a mpris_bridge_new().
 *
 * Órdenes emitidas:
 *  * `play`, `pause`, `toggle`, `stop`, `next`, `previous`
 *  * `seek:<segundos>` (absoluto, viene de `SetPosition`)
 *  * `seekrel:<segundos>` (relativo, viene de `Seek`)
 *  * `volume:<0..1>`, `loop:<none|track|playlist>`, `shuffle:<0|1>`
 *  * `open:<ruta o uri>`, `raise`, `quit`
 */
typedef void (*MprisCommandCallback)(const gchar* command, gpointer user_data);

/** Crea el puente y pide el nombre en la sesión de D-Bus. */
MprisBridge* mpris_bridge_new(MprisCommandCallback on_command,
                              gpointer user_data);

/** Suelta nombre, objeto y conexión. Acepta NULL. */
void mpris_bridge_free(MprisBridge* bridge);

/** Metadatos actuales. [duration_us] en microsegundos. */
void mpris_bridge_set_metadata(MprisBridge* bridge,
                               const gchar* title,
                               const gchar* artist,
                               const gchar* album,
                               gint64 duration_us);

/** Estado del transporte y posición (microsegundos). */
void mpris_bridge_set_playback(MprisBridge* bridge,
                               gboolean playing,
                               gint64 position_us);

/** Repetición (`none`/`track`/`playlist`) y aleatorio. */
void mpris_bridge_set_loop_and_shuffle(MprisBridge* bridge,
                                       const gchar* loop_status,
                                       gboolean shuffle);

/** Volumen 0..1. */
void mpris_bridge_set_volume(MprisBridge* bridge, gdouble volume);

/** Emite la señal `Seeked` (cuando Dart salta por su cuenta). */
void mpris_bridge_emit_seeked(MprisBridge* bridge, gint64 position_us);

G_END_DECLS

#endif  // CYBERHEX_MPRIS_BRIDGE_H_
