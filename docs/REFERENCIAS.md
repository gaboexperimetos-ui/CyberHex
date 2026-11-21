# Referencias: qué hacen otros reproductores

Investigación del 2026-11-21 para el paso «absorber lo útil de proyectos
similares» antes de rediseñar la interfaz.

Fuentes consultadas:

- **fooyin** (Qt 6 / C++, GPL-3, ~2.500 estrellas) — «el foobar2000 de Linux»:
  widgets acoplables, layouts con nombre, FooScript, hojas CUE (también
  embebidas), gapless, ReplayGain calculado, medidores de pico/VU, selección de
  dispositivo y salida por ALSA/PipeWire, listas M3U/M3U8, atajos globales,
  búsqueda avanzada, conversión de audio, CD con AccurateRip.
- **Strawberry** (Qt 6 / GStreamer, fork de Clementine) — biblioteca grande,
  edición de etiquetas en lote, carátulas, letras, radio, fades, MPRIS.
- **Tauon Music Box** — arrastrar y soltar para listas, gapless, FLAC, foco en
  colecciones locales y edición rápida de metadatos.
- **Amberol / Lollypop / Plattenalbum** — interfaz mínima tipo «álbum primero»,
  controles grandes, sin gestión de biblioteca pesada.
- **Musicolet / Poweramp** (Android) — navegación por carpetas, temporizador,
  ecualizador profundo, controles en notificación y pantalla bloqueada.

## Decisiones

| Idea | Fuente | Decisión | Por qué |
|---|---|---|---|
| Gapless + crossfade | fooyin, Tauon | **Ya existe** | `ch_engine_set_gapless` / `set_crossfade` |
| ReplayGain por pista/álbum + R128 | fooyin | **Ya existe** | `set_replaygain`, `set_replaygain_mode` |
| Hojas CUE | fooyin | **Ya existe** | `ch_cue_*`, ahora bindeado |
| Cola editable (mover, quitar, insertar) | fooyin, Strawberry | **Ya existe** | `ch_engine_queue_*`, ahora bindeado |
| Listas M3U/M3U8 | fooyin, Strawberry | **Ya existe** | `queue_import` / `queue_export` |
| Vúmetro y espectro | fooyin | **Ya existe** | `levels`, `meter`, `spectrum` |
| Selección de dispositivo de salida | fooyin | **Ya existe** | `output_device_*`, ahora bindeado |
| Temporizador de apagado | Musicolet, Strawberry | **Ya existe** | `set_sleep_timer`, ahora bindeado |
| Velocidad/tono sin cambiar el otro | fooyin | **Ya existe** | `set_speed` / `set_pitch` |
| «Anterior» reinicia si llevas >3 s | Spotify, Strawberry, Tauon | **Absorbido ahora** | `PlayerController.previous()` |
| Volumen efectivo del motor | todos | **Absorbido ahora** | `ch_engine_volume` bindeado |
| Cola visible (leer pistas) | fooyin, Strawberry | **Motor ampliado ahora** | `ch_engine_queue_item` |
| Mostrar título de la pista en vez del archivo | todos | Ya hecho | `syncTrackInfo` |
| Biblioteca con búsqueda y filtros | fooyin 0.8 | **Siguiente** | `ch_library_*` ya alcanzable; falta UI |
| Letras sincronizadas tipo karaoke | Strawberry | **Siguiente** | `lyrics_count` / `lyric_line` ya alcanzables |
| Restaurar sesión al arrancar | Strawberry, Tauon | **Siguiente** | `save_state` / `load_state` ya alcanzables |
| MPRIS en Linux (`org.mpris.MediaPlayer2`) | fooyin, Strawberry | **Pendiente** | requiere D-Bus por MethodChannel |
| Atajos globales | fooyin | **Pendiente** | depende de la plataforma |
| Edición de etiquetas en lote | Strawberry | **Descartado por ahora** | el núcleo solo lee etiquetas |
| CD / AccurateRip | fooyin | **Descartado** | fuera del alcance de un reproductor de archivos |
| Conversión de audio | fooyin | **Descartado** | no es un reproductor, es otra herramienta |
| Last.fm / scrobbling | fooyin | **Descartado** | el proyecto es local por diseño: sin red |
| Layouts de widgets acoplables | fooyin | **Adaptado** | una sola ventana con hojas, no un dock system |

## Lo absorbido en el código

1. **`previous()` con reinicio**: si la posición supera 3 s, vuelve al inicio
   de la pista; si no, salta a la anterior. Es lo que espera cualquiera que
   venga de Spotify, Strawberry o Tauon, y evita el «salto accidental» al
   pulsar anterior con la canción empezando.
2. **`ch_engine_volume`**: hasta ahora la app recordaba el volumen que había
   pedido, no el que el motor tiene de verdad. La UI debe leer el efectivo.
3. **`ch_engine_queue_item`**: el motor sabía contar y editar la cola, pero no
   decir qué pista hay en cada índice, así que ninguna interfaz podía dibujar
   la cola. Se añade al núcleo, al header, a `API.md` y a los bindings.

## Criterio de diseño para la interfaz

De los tres estilos vistos —dock de widgets (fooyin), biblioteca pesada
(Strawberry) y minimalismo de álbum (Amberol)— CyberHex se queda con el
tercero con toques del primero: **una ventana, el álbum como protagonista y
hojas** para cola, letras y ajustes. Nada de árboles de biblioteca permanentes
en móvil; en escritorio, la biblioteca será una hoja de búsqueda.
