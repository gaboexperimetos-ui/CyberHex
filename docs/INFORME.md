# CyberHex — Informe para el arquitecto

> **Para qué sirve este archivo.** Un agente (Arena/Claude) ejecuta el código; un
> arquitecto (Gemini/AI Studio) planifica. Este informe es la única fuente de
> verdad del estado real: qué existe, qué está probado, qué no se puede probar
> aquí y qué falta. Se actualiza al final de cada turno; el detalle cronológico
> vive en [`BITACORA.md`](BITACORA.md).
>
> Última actualización: 2026-11-21 · rama `arena/108ff38d-cyberhex` · base `8f392f7` + este pedido

---

## 0. Protocolo de trabajo

1. El arquitecto lee **este archivo entero** antes de ordenar nada.
2. Emite **pedidos** en este formato (uno o varios por turno):

   ```
   OBJETIVO: <resultado observable>
   ALCANCE: <archivos/módulos que puede tocar>
   PROHIBIDO: <lo que no debe tocar>
   CRITERIO DE ACEPTACIÓN: <cómo se comprueba>
   RIESGO ACEPTABLE: <sí/no a cambios de comportamiento>
   ```
3. El agente ejecuta, **verifica con lo que hay en el sandbox** (ver §7), commitea
   en trozos reversibles y responde con el delta + actualiza `BITACORA.md`.
4. Si un pedido depende de algo que **no se puede verificar aquí** (§7.2), el
   agente lo dice antes de empezar, no después.
5. Un pedido = un objetivo. Si son dos cosas independientes, dos pedidos.

---

## 1. Resumen ejecutivo

- Reproductor **Flutter + motor nativo propio** (Zig 0.17.1 + C23). Un solo
  núcleo, dos apps: **escritorio Linux/Arch** y **Android**.
- Núcleo: **133 818 líneas** (sin `third_party`), **199 símbolos `ch_*`**, ABI **3**.
  Decodifica con FFmpeg si está; si no, con miniaudio (WAV/FLAC/MP3/Vorbis).
- App: **20 295 líneas Dart** + **5 565 de tests** (226 casos). Estado
  centralizado en `PlayerController` (testeable **sin** la `.so`). Fases 1B y 2
  cerradas (cola, biblioteca, sesión persistente y DSP audiófilo) y **fase 3 en
  marcha**: paisajes sonoros, detector de BPM, exportador WAV y `.cue` en el
  núcleo, **toda** la API del motor expuesta a Dart con el DSP persistido en la
  sesión, el **laboratorio de audio** («toda la fase 2 en pantalla»), la fase 4
  de letras, etiquetas y tarjetas, la fase 5 de listas, multi-cola, automix,
  estadísticas y descargas, la fase 6A de temas, gestos y mini-reproductor, la
  6B de escritorio (MPRIS, drag & drop, atajos) y la **7B: radios por Internet,
  WebDAV/nube, exportador de rango con DSP, scrobbling y copia de seguridad
  unificada**.
- Android: **823 líneas Kotlin** (actividad, puente de canal y servicio de
  reproducción en primer plano con `MediaSession`). El motor sigue en Dart:
  Kotlin no decodifica nada, solo mantiene el proceso vivo y reenvía controles.
- Verificado aquí: 13 tests Zig, `.so` ReleaseFast nativa y cruzada aarch64,
  prueba de humo con audio real y el build de escritorio con CMake real.
- **No verificado aquí** (falta SDK): `flutter analyze`, `flutter test`,
  `flutter build linux/apk`. Toda la capa Dart/Kotlin es "escrita, no compilada".

---

## 2. Inventario

```
core/                       motor nativo (Zig 0.17.1 + C23)        133 818 líneas
  src/root.zig              199 símbolos ch_*, hilo de audio, render, cola, EQ, eventos
  src/dsp_ambient.zig       paisajes sonoros (lluvia, marrón, vinilo) sin malloc
  src/bpm.zig               detector de pulso 60..200 BPM por autocorrelación
  src/{cue,fileio,analysis}.c  hojas CUE, guardado de carátula, R128 y picos
  src/{eq,stft,fft,stretch}.zig   DSP puro (con tests)
  src/audio.c               miniaudio: dispositivo, callback
  src/decode_ffmpeg.c       decodificador FFmpeg (formato completo)
  src/decode_miniaudio.c    decodificador dr_wav/dr_flac/dr_mp3/stb_vorbis
  src/{playlist,library,lyrics,markers}.c   cola en disco, escaneo, LRC, marcadores
  include/cyberhex_core.h   contrato C (lo que consume Dart)
  tests/smoke.c             prueba de humo portable (PC y teléfono)
  API.md                    referencia de la API
  build.zig                 -Ddecoder=auto|ffmpeg|miniaudio, pasos test/smoke
lib/                        app Flutter                                 20 295 líneas
  core/player_api.dart      contrato PlayerApi (112 miembros) + PlayerSnapshot + AudioSettings
  core/player_controller.dart  estado + bombeo de eventos cada 80 ms
  core/native_player.dart   bindings FFI (única frontera con el núcleo)
  core/eq_presets.dart      curvas de EQ por anclajes (interpolación log) + «Mi oído»
  core/lyrics_parser.dart   .lrc (marcas múltiples, bilingüe, offset) + USLT/LYRICS
  core/tag_editor.dart      ID3v2 y Vorbis comment: leer y escribir etiquetas y carátula
  core/playlist_store.dart  playlists .m3u/.m3u8/.pls, inteligentes, 5 colas y posición
  core/stats_store.dart     historial, totales, top de pistas/artistas y hora favorita
  core/automix_engine.dart  plan de mezcla por BPM (±8 %) y máquina de estados
  core/audio_downloader.dart  Internet Archive y URLs directas con dart:io
  core/theme_controller.dart 4 temas, color de carátula, gestos y barra configurable
  core/radio_store.dart     emisoras propias, .m3u/.m3u8/.pls y ventana de 12 s por HTTP
  core/scrobbler.dart       ListenBrainz y Last.fm (MD5 propio), cola con reintentos
  core/backup_service.dart  copia .json unificada de todos los almacenes
  theme.dart                4 paletas (neón, AMOLED, claro, Material You) y estilos
  platform/media_session_channel.dart  puente Dart del canal cyberhex/media
  ui/audio_lab_sheet.dart   laboratorio: todo el DSP, BPM, WAV, .cue, loop y sueño
  ui/lyrics_page.dart       visor a pantalla completa con fondo difuminado
  ui/lyrics_creator_page.dart  estudio: marcar versos al ritmo y guardar .lrc
  ui/tag_editor_sheet.dart  etiquetas y carátula, individual o por álbum
  ui/share_card_sheet.dart  tarjeta compartible exportable desde RepaintBoundary
  ui/playlists_page.dart    listas, inteligentes, importar/exportar y detalle
  ui/stats_page.dart        totales, gráfico por hora, top e historial
  ui/downloader_page.dart   buscar en Archive o pegar URL, con barra de progreso
  ui/mini_player.dart       barra flotante en biblioteca y listas
  ui/settings_page.dart     tema, carátula, salida, scrobbling y copia de seguridad
  ui/radio_page.dart        emisoras propias, sugeridas, importar/exportar m3u
  ui/network_page.dart      WebDAV (Basic/Bearer), enlaces de nube y caché local
  ui/audio_export_sheet.dart  rango inicio/fin → WAV master o tono de llamada
  ui/visualizer_widget.dart vúmetro + espectro (barras o hexágonos) a 30 Hz
  ui/hearing_test_sheet.dart  prueba de audición por bandas → compensación
  ui/{player_page,eq_sheet,queue_sheet,library_page,core_error_screen}.dart
  main.dart                 crea motor + controlador (o recibe uno inyectado)
test/                       226 tests Dart                             5 565 líneas
android/                    Gradle + tarea que compila el núcleo + jniLibs
  app/src/main/kotlin/…/MainActivity.kt         52 líneas, canal + permisos
  app/src/main/kotlin/…/MediaBridge.kt         205 líneas, canal y cola de comandos
  app/src/main/kotlin/…/MediaSessionService.kt 566 líneas, FGS + MediaSession
linux/                      CMake: compila y empaqueta el núcleo en bundle/lib
packaging/linux/            PKGBUILD de Arch + .desktop + icono SVG
docs/                       este informe y la bitácora
ANALISIS.md                 auditoría técnica original + tabla de hallazgos A/B/C
```

---

## 3. Arquitectura

```
Flutter UI (lib/)  ──PlayerController──  native_player.dart
                                               │ dart:ffi
                                    libcyberhex_core.so (.dll/.dylib)
                                               │
        ┌──────────────────────────────────────┴─────────────────────────┐
        │ root.zig: estado atómico, cola, EQ, ReplayGain, fade, A-B      │
        │  hilo de audio (miniaudio) ⇄ hilo decodificador ⇄ hilo UI       │
        └──────────────────┬──────────────────────────┬──────────────────┘
                    audio.c (salida)          decode_ffmpeg.c | decode_miniaudio.c
```

- **Hilo de audio**: `render()` cada bloque. Sin locks salvo `tryLock` del
  espectro y un `seg_lock` puntual. Niveles y visor se calculan aquí.
- **Hilo decodificador**: llena el ring buffer, atiende `seek_req`/`skip_req`,
  estiramiento y crossfade.
- **Comunicación con la UI**: sondeo (`ch_engine_poll_event`, posición,
  `ch_engine_levels`, `ch_engine_spectrum`). Nunca callbacks desde el audio.
- **Datos**: `PlayerSnapshot` inmutable; la posición va por un `ValueNotifier`
  aparte para no reconstruir la pantalla a 12,5 Hz.

---

## 4. El núcleo (API)

97 funciones `export fn`. Grupos (detalle en `core/API.md`):

| Grupo | Ejemplos | Notas |
|---|---|---|
| Ciclo de vida | `ch_engine_create/destroy`, `ch_core_version`, `ch_engine_abi_version` | ABI 3 |
| Carga y cola | `ch_engine_load`, `load_async`?, `load_add`, `play_index`, `queue_*`, `move`, `shuffle` | cola no se vacía al cargar |
| Transporte | `play`, `pause`, `seek`, `set_volume`, `is_playing`, `position`, `duration` | posición con `played` |
| Fade pausa | `set_pause_fade`, `pause_fade` | def. 0,05 s; la posición cuenta el fundido |
| Loop A-B | `set_loop`, `loop_start`, `loop_end` | se cancela al cambiar de pista |
| EQ | `eq_band_count/freq`, `set_eq_gains`, `set_band_gain`, `set_eq_preamp` | 36 bandas, ±18 dB, preamp 0..−24 |
| Medición | `levels` (RMS/pico), `spectrum`, `buffered_seconds`, `buffer_underflows` | post-EQ/post-limitador |
| Dinámica | `set_limiter`, `set_replaygain`, `set_replaygain_mode`, `rg_gain_db/peak` | álbum/pista + R128 |
| Canales | `set_balance`, `set_channel_mode` (estéreo/mono/swap) | antes del limitador |
| Metadatos | `title/artist/album/tag`, `cover_*`, `lyrics_*` | carátulas múltiples (4) |
| Avance auto | `set_repeat`, `set_shuffle`, `set_crossfade`, `set_gapless`, `skipped_tracks` | salta pistas rotas |
| Estiramiento | `set_speed`, `set_pitch` | WSOLA en `stretch.zig` |
| Dispositivo | `output_device_*`, `set_output_device` | recrea el dispositivo |
| Sistema | `set_sleep_timer`, `detect_silence`, `poll_event` | sin callbacks |
| Biblioteca | `ch_library_*` | escaneo incremental, ciclos, hash |

**Inmutable por diseño y no negociable sin pedido explícito:** 48 000 Hz fijos,
`CHANNELS = 2`, salida f32, FFI en C plano (sin structs opacos versionados).

### 4.1 Fase 3, pedido 1: paisajes, BPM, CUE en memoria y exportador WAV

Lo nuevo del núcleo (símbolos **añadidos**, ninguno cambiado: la ABI sigue en 3 y
`lib/`, `android/` y `linux/` no se tocaron):

| Pieza | Símbolo(s) | Dónde |
|---|---|---|
| Paisaje sonoro (lluvia, ruido marrón, vinilo) | `ch_engine_set_soundscape`, `ch_engine_soundscape` | `src/dsp_ambient.zig` |
| Pulso del archivo | `ch_engine_detect_bpm` | `src/bpm.zig` |
| `.cue` desde texto | `ch_cue_parse` | `src/cue.c` |
| Exportar a WAV | `ch_engine_render_wav`, `ch_engine_render_wav_ex` | `src/root.zig` |

* **Paisajes**: generador determinista por semilla, un xorshift32 por canal, sin
  `malloc` y sin candados; preset y nivel son atómicos. Entra en la mezcla
  **antes del limitador** (contrato 20). A nivel 1 el RMS es ~0.06 y el pico
  ~0.25, así que la música manda.
* **BPM**: envolvente de energía (tramas de 10 ms) → flujo suavizado →
  autocorrelación 60..200 con prior logarítmico en 120 → refinado parabólico.
  Acierta 62..198 BPM con error ≤ 0.3 % en clicks sintéticos y devuelve 0 ante
  silencio o ruido; nunca sale del rango.
* **CUE**: el parser pasa a trabajar sobre un buffer (mismo código para fichero
  y para texto) y `ch_cue_parse` abre la puerta a `.cue` que llegan de un zip,
  de la red o de una intención de compartir. Probado con ASan/UBSan.
* **Exportador**: decodifica a 48 kHz estéreo, aplica la ganancia ReplayGain de
  las etiquetas, limita a −1 dBFS, cuantiza a S16 con dither TPDF (un PRNG por
  canal) y escribe la cabecera RIFF primero (frames calculados desde la duración;
  si falta, doble pasada), así que no necesita buscar en el fichero. La variante
  `_ex` aplica el DSP del motor en el mismo orden que `render()`.
  En el smoke: 3 s → 576 044 bytes (44 + 3·48 000·4) y un recorte de 1 s → 192 044.

---

## 5. Capa Dart

| Archivo | Responsabilidad |
|---|---|
| `player_api.dart` | `PlayerApi` (contrato), `PlayerSnapshot` (inmutable, `==`), `PlayerEvent` |
| `player_controller.dart` | `ChangeNotifier`; drena eventos, refresca snapshot, `ValueNotifier<double> position` |
| `native_player.dart` | Implementa `PlayerApi` sobre FFI; **todo símbolo opcional con `providesSymbol`** (una `.so` vieja sigue cargando) |
| `platform/media_session_channel.dart` | Puente con Android: `updateMetadata`/`updateState` (throttle 1 s) hacia Kotlin y comandos (`play`, `pause`, `toggle`, `next`, `previous`, `seek`, `setVolume`, `duck`) hacia el controlador |
| `session_store.dart` | `SessionSnapshot` + `SessionStore` (JSON con `.tmp`→rename) y `SessionKeeper`, que restaura al arrancar y guarda al pausar o cambiar de pista |
| `favorites_store.dart` | Conjunto de rutas favoritas en JSON, `ChangeNotifier`, escritura atómica |
| `ui/player_page.dart` | Consume `ListenableBuilder` + `ValueListenableBuilder`; teclado (espacio) |
| `ui/eq_sheet.dart` | 36 bandas contra el controlador |
| `ui/queue_sheet.dart` | Cola: arrastrar para ordenar, deslizar para quitar, vaciar y «cola protegida» |
| `ui/library_page.dart` | Biblioteca: 5 pestañas, búsqueda, orden, filtro de cortas y menú contextual |

`PlayerApi` incluye `next()`/`previous()`; `NativePlayer` los bindea con
`providesSymbol` y quedan en `null` (no-op) si la `.so` es anterior a la ABI que
los exporta.

Tests: 42 del controlador + 26 de sesión + 11 de biblioteca + 7 del canal de
medios + 3 de la pantalla + 8 de archivos externos + 1 de tema (98 en total),
todos con `FakePlayer`/canal simulado (sin FFI, sin teléfono).

### 5.1 Cola, biblioteca y sesión (fase 1B)

- **Cola espejada.** El contrato C no exporta `queue_path`: solo
  `ch_engine_queue_count` y `ch_engine_queue_index`. `NativePlayer` mantiene
  `_queuePaths` y **toda** mutación de la cola pasa por él (`queue_add`,
  `queue_insert`, `play_index`, `load_add`, `move`, `remove`, `clear`,
  `import`, `export`); si el motor tuviera más pistas de las conocidas se
  rellenan con rutas vacías (`QueueItem.isPlayable == false`) en vez de
  inventar nombres. `load()` y `play_index` reinician el espejo.
- **`load_add` no devuelve el índice** (delega en `play_index` y devuelve 0):
  el índice audible se lee después con `ch_engine_queue_index`.
- **Rutas, no etiquetas.** La biblioteca solo da rutas
  (`ch_library_path`), así que `titleFromPath` recorta el nombre y artista y
  álbum se deducen de la jerarquía (`<raíz>/Artista/Álbum/pista`). La duración
  solo se conoce para lo ya reproducido (R15).
- **Sin congelar la UI.** `load_add` y `ch_library_scan` corren en
  `Isolate.run`: el handle de biblioteca se crea, escanea, copia y destruye
  dentro del isolate, y solo cruzan cadenas.
- **Sesión.** JSON plano (`queue`, `queueIndex`, `position`, `volume`,
  `repeatMode`, `shuffle`) con escritura atómica. Al restaurar se hace
  `playAt` + `pause` + `seek` para dejar la pista cargada en la posición
  exacta **sin** soltar audio al abrir la app. Guardado con 600 ms de
  antirrebote al pausar o cambiar de pista; `dispose` vacía lo pendiente.

---

### 5.2 Fase 2: el DSP audiófilo llega a Dart

Los 18 miembros nuevos de `PlayerApi` (63 en total) siguen la regla de la casa:
**todos con `providesSymbol`** (§8.6), así que una `.so` anterior a la ABI que
los exporta deja el control en `null` y cada operación devuelve un valor seguro
(`false`, `0` o el valor por defecto) en vez de romper.

| Qué | Setter | Lectura |
|---|---|---|
| 9D espacial | `set9D(enabled, speedHz, depth)` | `nineDEnabled`, `nineDSpeed`, `nineDDepth` |
| Potenciador | `setStereoEnhance(width, bassPunch)` | `stereoWidth`, `bassPunch` |
| Karaoke | `setVocalCut(0..1)` | `vocalCut` |
| Crossfeed Bauer | `setCrossfeed(enabled, level)` | `crossfeedEnabled`, `crossfeedLevel` |
| Modo noche | `setNightMode(enabled, amount)` | `nightModeEnabled`, `nightModeAmount` |
| Salida S16 | `setS16Output(bool)` | `s16Output` |

* `PlayerSnapshot` lleva los once campos (más `s16Output`) dentro de
  `copyWith`, `==` y `hashCode` (`Object.hashAll`, porque `Object.hash` tiene
  tope de 20 argumentos).
* `PlayerController` añade setters con `_refresh()` y la misma idea que el
  resto: `set9D({enabled, speed, depth})` envía solo lo que cambia y
  `toggle9D/toggleVocalCut/toggleCrossfeed/toggleNightMode` para la UI.
* Los getters que el C devuelve por puntero (`ch_engine_crossfeed`,
  `ch_engine_night_mode`) usan un `_outBuf` reservado una sola vez en el
  constructor: el snapshot los lee a 12 Hz y no se asigna memoria por lectura.
* `FakePlayer` implementa los 18 y **recorta igual que el motor**, así que los
  tests de rangos prueban el contrato, no la cortesía del doble.

Tests: 8 nuevos en `player_controller_test.dart` (setters, recorte de rangos,
alternancias, `==`/`hashCode` con los campos DSP, `copyWith` parcial y que los
setters no hacen nada tras `dispose`).

### 5.3 Fase 3, pedido 2: toda la API del motor, en Dart

`PlayerApi` pasa de 63 a **112 miembros** y `NativePlayer`/`FakePlayer` los
implementan **todos** (comprobador propio: 112/112 en ambos). Lo que faltaba:

| Grupo | Miembros nuevos |
|---|---|
| Medición | `levels()` → `PlayerLevels` (RMS y pico por canal), `spectrum([bands])` |
| Mezcla | `balance`/`setBalance`, `channelMode`/`setChannelMode` |
| ReplayGain | `replayGainEnabled`/`setReplayGain`, `replayGainGainDb`, `replayGainPeak`, `replayGainAlbum`/`setReplayGainAlbum` |
| Transporte | `speed`, `pitch`, `crossfade`, `gapless`, `setLoop`/`clearLoop`/`loopStart`/`loopEnd`/`loopActive` |
| Marcadores | `loadMarkers`, `saveMarkers`, `markersOf`, `addMarker`, `removeMarker`, `clearMarkers` (+ `addMarkerHere` en el controlador) |
| Sistema | `setSleepTimer`/`sleepRemaining`, `detectSilence` (isolate), `outputDevices`/`outputDevice`/`setOutputDevice`, `lyricLineCount`/`currentLyricLine` |
| Fase 3 | `soundscape`/`soundscapeLevel`/`setSoundscape` (enum `SoundscapePreset`), `detectBpm`, `renderWav`, `readCue`/`parseCue` |

* **Modelos nuevos** en `player_api.dart`: `PlayerLevels`, `AudioMarker`,
  `AudioDevice`, `CueTrack`, `SilenceTrim`, `SoundscapePreset` y `AudioSettings`
  (este último vive aquí, no en `session_store.dart`, para que controlador y
  sesión compartan el modelo sin importarse en círculo).
* **Frontera FFI**: 122 símbolos `ch_*` desde Dart, **todos** con
  `providesSymbol` y `null` si la `.so` es vieja (no-op con valores por
  defecto). Las tres operaciones caras —BPM, silencio y exportación— corren en
  `Isolate.run`, así que no congelan la UI; el resto son llamadas directas.
* **Marcadores**: un handle `ch_markers*` perezoso en `NativePlayer`, liberado
  en `dispose()`. Las rutas se reservan y se liberan en el mismo método (`try`/
  `finally`), sin punteros que sobrevivan a la llamada.
* **`.cue`**: se lee en el isolate y se devuelven `CueTrack` planos; el handle
  del núcleo se libera siempre con `ch_cue_free`.
* **Persistencia**: `AudioSettings` entra en `SessionSnapshot` (formato **2**),
  `SessionKeeper` lo aplica al arrancar (`applyAudioSettings`) y lo guarda con
  el mismo antirrebote de 600 ms, ahora también al mover un mando
  (`addAudioListener`). Un JSON viejo (versión 1) o corrupto se degrada campo a
  campo: nunca impide arrancar.

Tests: 12 nuevos del controlador (medición, rangos, loop, paisajes, marcadores,
temporizador, dispositivos, BPM/exportación, CUE, ida y vuelta de ajustes, aviso
de cambios y «nada tras dispose») y 5 de sesión (JSON completo, sesión v1 sin
audio, audio corrupto, restauración + guardado y antirrebote).

---

### 5.4 Fase 3, pedido 3: la UI de audio (todo el DSP en pantalla)

Hasta aquí el DSP existía y se podía llamar, pero **no había dónde tocarlo**: la
única pantalla de audio era el ecualizador. Este pedido lleva a la interfaz todo
lo que el núcleo ya sabía hacer, sin añadir una sola dependencia.

| Sitio | Qué se puede hacer |
|---|---|
| **Laboratorio de audio** (`AudioLabSheet`, desde el reproductor) | 9D (on/velocidad/profundidad), ancho estéreo, punch, crossfeed Bauer, karaoke, modo noche con su compresión, balance, canales (estéreo/mono/intercambiado), ReplayGain (global y por álbum), velocidad 0.25–4×, tono ±12 semitonos, salida S16 con dither, crossfade, gapless, loop A-B, temporizador de sueño, paisaje sonoro con su nivel, detección de BPM, exportación WAV con el DSP, apertura de hojas `.cue` y marcador en la posición actual |
| **Visualizador** (`VisualizerWidget`) | Vúmetro RMS/pico por canal con marca de clip y espectro de 24–28 bandas en dos estilos (barras o columnas de hexágonos). En el reproductor en versión compacta y en el laboratorio con medidores |
| **Ecualizador** (`EqualizerSheet`) | Los 36 mandos de siempre + **10 presets** en chips horizontales y acceso a la prueba de audición |
| **Prueba de audición** (`HearingTestSheet`) | Aísla una banda sobre la música que suena, pregunta «¿lo oyes?» y propone una curva de compensación; **restaura el EQ** al salir salvo que se acepte |
| **Pie del reproductor** | Botón de laboratorio y atajo de paisaje sonoro (cicla ninguno → lluvia → marrón → vinilo) |

Decisiones que conviene saber:

* **Los presets son curvas, no tablas de 36 números.** `EqPreset` guarda anclajes
  (frecuencia, dB) y `gainsFor` interpola en **log-frecuencia**, recorta a ±18 dB y
  mantiene plano fuera de rango. Si mañana el motor cambia el reparto de bandas,
  los presets siguen sonando como se pensaron. Se aplican con `setBand` banda a
  banda (36 llamadas), que es lo único que expone el contrato.
* **La prueba de audición no genera tonos** (el núcleo no tiene oscilador): deja
  sola la banda en cuestión a +12 dB y el resto a −18 dB sobre lo que esté
  sonando. La compensación resultante es suave (+12 dB como máximo, solo en las
  bandas perdidas) y se deshace con «Plano».
* **El visualizador sondea a 30 Hz con su propio temporizador**, no con el
  snapshot de 80 ms ni con un `Ticker` de la pantalla: `levels()`/`spectrum()` no
  bloquean (contrato del núcleo) y solo repinta el `CustomPaint`. Con
  `MediaQuery.disableAnimations` se queda en un fotograma.
* **1 443 líneas en cinco secciones plegables**: la hoja se abre con «Espacial»
  desplegada y el resto plegado, para que quepa en un móvil de 5" sin marear.

Tests nuevos (14, `test/audio_lab_test.dart`): curvas (plano, interpolación
logarítmica, recorte, compensación, los 10 presets dentro de rango), visualizador
(medidores y estilos), laboratorio (secciones, 9D al motor, paisaje, BPM), prueba
de audición (cancelar restaura y aplica con 10 respuestas) y presets del
ecualizador.

---

### 5.5 Fase 4: letras sincronizadas, estudio `.lrc`, etiquetas y tarjetas

El núcleo sabe *qué suena* pero no *qué pone en el archivo*: las etiquetas y las
letras incrustadas son formato de contenedor, así que se leen desde Dart sin
dependencias (`dart:io` + `dart:typed_data`). Son ~1 200 líneas nuevas de core
Dart y ~1 800 de UI.

| Pieza | Qué hace |
|---|---|
| `LyricsParser` | `.lrc` con marcas múltiples por línea, metadatos (`ti`, `ar`, `al`, `by`, `offset`), **bilingüe** por marca repetida o por `|`, y lectura de `USLT` (ID3v2, v2.3 y v2.4) y de `LYRICS`/`UNSYNCEDLYRICS` (Vorbis comment de FLAC). `indexAt()` por búsqueda binaria sobre el tiempo de presentación (con `offset`) |
| `LyricsPage` | Pantalla completa con la carátula difuminada (`ImageFiltered` a 42 px de sigma), resaltado y autoscroll por `Scrollable.ensureVisible`, salto exacto al tocar un verso, traducción conmutables y recarga |
| `LyricsCreatorPage` | Pegar texto → «Preparar versos» → play y «Marcar verso» al ritmo (sella con la posición del motor y avanza), ajuste fino ±0,1 s y deshacer; guarda `tema.lrc` junto al audio con metadatos del motor |
| `TagEditorSheet` | Título, artista, álbum, año, género, pista y carátula; escribe ID3v2.3 (MP3) o reconstruye los bloques FLAC (Vorbis comment + PICTURE); «aplicar al álbum» usa `albumSiblings` y conserva título y número de cada archivo |
| `ShareCardSheet` | Tarjeta 340×440 dentro de `RepaintBoundary`: carátula, verso elegido (el que suena al abrir), silueta de onda y marca. Exporta con `toImage(pixelRatio: 3)` → PNG a la ruta que elija el usuario |

Decisiones y límites que conviene tener escritos:

* **La forma de onda de la tarjeta es decorativa y determinista**
  (`shareWaveform(seed)`): el núcleo no expone los picos de la pista (sigue en
  P0.5), así que se dibuja una silueta estable a partir de título y artista en
  lugar de inventar un nivel medido. Está dicho en el código y en la hoja.
* **Escribir etiquetas reescribe el contenedor, no el audio**: en MP3 se
  sustituye la etiqueta y se copia el resto; en FLAC se reconstruye la cadena de
  bloques (STREAMINFO primero) y se copian los frames. Se hace con `.tmp` +
  `rename`. Implica cargar el archivo en memoria.
* **Solo `.mp3` y `.flac`**: `TagEditor.canWrite` lo comprueba antes de tocar
  nada y la hoja lo explica en vez de fallar a medias.
* **El motor no refresca metadatos** (no hay símbolo para ello): tras guardar, la
  hoja avisa de que hay que volver a abrir la pista.

Tests nuevos (28, `test/lyrics_and_tags_test.dart`): `LyricsParser` completo
(metadatos, offset, marcas múltiples, dos formas de bilingüe, texto plano, ida y
vuelta con `LrcWriter`, basura sin romper), letras incrustadas (USLT UTF-8,
Vorbis de FLAC, prioridad del `.lrc` de al lado), `TagEditor` (ID3v2 ida y
vuelta con y sin carátula, audio conservado, FLAC reconstruido, escritura en
disco, edición de álbum, formato no soportado) y cinco de widget (visor, foro
vacío, estudio con guardado real, hoja de etiquetas con escritura real y
tarjeta).

---

### 5.6 Fase 5: listas `.m3u`, cinco colas, automix, estadísticas y descargas

Todo lo que rodea a «escuchar música» sin tocar el núcleo: archivos de texto
(`.m3u`), JSON propio y `dart:io`. Cuatro piezas nuevas de core Dart y tres
pantallas.

| Pieza | Qué hace |
|---|---|
| `PlaylistStore` | Crear, renombrar, duplicar y borrar listas; añadir/quitar/reordenar sin duplicados; **importar y exportar** `.m3u`, `.m3u8` y `.pls` (rutas relativas resueltas contra el archivo); **listas inteligentes** Top 25, Nunca escuchadas y Añadidas este mes (esta última con `remember()` de lo que ve la biblioteca) |
| `MultiQueueStore` | **Cinco colas** simultáneas con su índice; la activa suena y las demás se guardan. Cambiar de cola guarda la actual y carga la otra en el motor (`clearQueue` + `enqueue` + `playAt`) |
| `LongTrackMemory` | Retoma audiolibros y directos: guarda la posición solo si la pista pasa de **15 min** y ya se oyeron 30 s; olvida la pista si se dejó a menos de 20 s del final. Escritura con antirrebote de 2 s |
| `StatsStore` | Reproducciones, minutos, top de pistas y artistas, reparto por hora (franja favorita) e historial de 1 000 entradas. JSON con antirrebote de 800 ms |
| `AutomixEngine` | Cuando quedan ≤ 8 s, calcula BPM de la actual y la siguiente (caché, `detectBpm` en isolate), estira el tempo **como mucho ±8 %** (acepta doble/mitad de pulso) y pone el crossfade; al entrar la siguiente, devuelve el tempo a `1.0`. `AutomixPlanner` es puro y se prueba sin motor |
| `AudioDownloader` | Busca en **Internet Archive** (`advancedsearch.php`), lista los archivos de audio del ítem y descarga con `HttpClient` y progreso por bytes; también acepta una **URL directa**. Nombre saneado y `.part` + `rename` |
| `PlaylistsPage` / `StatsPage` / `DownloaderPage` | Listas (con detalle, borrar, subir, exportar), estadísticas (tarjetas, 24 barras por hora, top e historial) y descargas (buscar → archivos → descargar → añadir a la cola) |

Decisiones y límites:

* **Lo descargado entra en la cola, no en la biblioteca**: el núcleo indexa
  carpetas con `ch_library_*`; no hay símbolo para inyectar una ruta suelta. La
  pantalla lo dice y deja añadir a la cola.
* **El automix no mezcla audio propio**: usa el crossfade del motor y `speed`
  como mucho ±8 %. Por encima de ese desvío suena a accidente y el plan lo evita.
* **Las estadísticas cuentan arranques**, no tiempo real con pausas: el
  controlador no expone un contador de reproducción y añadirlo sería un pedido
  de núcleo.
* **`seen` para «Añadidas este mes»**: la biblioteca apunta lo que escanea
  (`PlaylistStore.remember`), así que la lista sale de datos reales y no de la
  fecha del archivo.

Tests nuevos (22, `test/playlists_and_downloader_test.dart`): listas (CRUD,
sin duplicados, `.m3u`/`.pls`, importar/exportar, inteligentes, JSON), cinco
colas (captura, cambio, renombrado, disco), memoria de pistas largas, estadísticas
(acumulación y persistencia), automix (plan puro y motor con probe inyectado),
descargador (parser del buscador, filtrado de archivos, saneado de nombres y
**descarga real contra un `HttpServer` local** con progreso) y cuatro de widget.

---

### 5.7 Fase 6A: temas, carátula, gestos, mini-reproductor y modo bolsillo

La app deja de tener un solo aspecto. `theme.dart` gana **cuatro paletas**
(Neón, AMOLED Negro Puro, Claro y Material You) y `ThemeController` las aplica
sobre el `MaterialApp` entero; el reproductor pasa a ser táctil de verdad.

| Pieza | Qué hace |
|---|---|
| `CyberHexPalette` | 12 colores por tema + brillo. `buildCyberHexThemed(palette)` monta el `ThemeData` y expone la paleta como extensión (`paletteOf(context)`), con la neón como red de seguridad. `buildCyberHexTheme()` sigue existiendo y devuelve neón |
| `ThemeController` | Tema, **color dinámico de la carátula** (`instantiateImageCodec` a 32 px + media ponderada por saturación, con acento de reserva determinista si el byte no es imagen), estilo de carátula, modo bolsillo y qué botones van en la barra rápida. Persiste en `theme.json` |
| `PlayerPage` | Cuatro estilos de carátula (cuadrada, redondeada, disco giratorio y **a sangre** con la carátula de fondo), deslizamiento horizontal (siguiente/anterior) y vertical (volumen) sobre la carátula, **doble toque** por zonas (−10 s / play-pausa / +10 s), **búsqueda fina** arrastrando en vertical sobre la barra (1 px = 50 ms, se muestra en `mm:ss.mmm`), barra de acciones configurable, **modo bolsillo** (bloqueo total, se sale con pulsación larga) y **dos paneles** en pantallas anchas (≥ 760 px y horizontal) |
| `MiniPlayer` | Barra flotante con carátula, título, transporte y progreso; en biblioteca y listas, tocar abre el reproductor |
| `SettingsPage` | Tema, color dinámico, estilo de carátula, modo bolsillo y los cuatro botones de la barra rápida |

Límites y decisiones:

* **No hay `dynamic_color` ni `palette_generator`**: el acento se saca con
  `dart:ui` (decodificar a 32 px y promediar por saturación). Es menos «bonito»
  que un cuantizador, pero no añade un paquete y es determinista.
* **La migración a la paleta es incremental**: reproductor, mini-reproductor y
  ajustes ya leen `paletteOf(context)`; biblioteca, listas, estadísticas y
  descargas siguen con las constantes neón. Con el tema claro se ven como antes
  (R28).
* **El «a sangre» pone la carátula de fondo** con un velo del tema para que el
  texto siga legible; no recorta ni difumina la imagen.

Tests nuevos (19, `test/theme_and_gestures_test.dart`): paletas y extensión,
controlador (tema, ciclo, estilo, bolsillo, acciones, persistencia), acento de
píxeles (grises y transparentes fuera, rojo y azul dominantes), acento de
reserva, y en el reproductor: doble toque en las tres zonas, búsqueda fina por
arrastre vertical, modo bolsillo con bloqueo y salida por pulsación larga, los
cuatro estilos y el diseño de dos paneles; más mini-reproductor y ajustes.

---

### 5.8 Fase 7B: radios, red, exportador con DSP, scrobbling y copia de seguridad

Cierra la fase 7 en la app: **entrar audio que no está en el disco** (radio y
nube), **sacar audio con el DSP puesto** y **no perder nada** de lo que el
usuario ha construido (escuchas y copia de seguridad). Sin un solo paquete nuevo.

| Pieza | Qué hace |
|---|---|
| `RadioStore` | Emisoras propias (`radios.json`, escritura atómica) + importar `.m3u`/`.m3u8`/`.pls` (absolutas y relativas, `#EXTINF` como nombre) + exportar `.m3u`. Resuelve listas encadenadas (`.m3u` → flujo, 2 saltos) y **baja una ventana** del flujo a `${systemTemp}/cyberhex_radio` (12 s o 24 MB) para que el núcleo, que abre **archivos**, la reproduzca |
| `RadioPage` | «Mis emisoras» y cuatro sugeridas de fábrica (SomaFM Groove Salad y Lush, Radio Paradise, FIP), alta con nombre/URL/género, renombrar, borrar, importar/exportar y nota honesta: es radio **con búfer**, no directo continuo |
| `NetworkStore` + `WebDavClient` | Servidores WebDAV (Basic o Bearer) y enlaces de nube directos. `PROPFIND Depth: 1` parseado con expresiones regulares (los namespaces reales rompen un parser ingenuo), navegación por carpetas, subida de nivel, descarga atómica a `cloud_cache` y reproducción de lo bajado |
| `NetworkPage` | Añadir servidor o enlace, explorar, ver tamaño por entrada, descargar + reproducir, y aviso de que las credenciales se guardan **en claro** |
| `AudioExportSheet` | Rango inicio/fin sobre la pista actual → `renderWav` con **EQ + 9D + ancho estéreo** (o plano), en dos salidas: **pista masterizada** y **tono de llamada** (recorta a 30 s). Nombre sugerido, `getSaveLocation` y estado del render |
| `Scrobbler` | Cuenta la escucha si suena **más de la mitad o más de 4 min** (mínimo 30 s por pista) y la envía a **ListenBrainz** (`/1/submit-listens`, `Authorization: Token`) y **Last.fm** (`track.scrobble` firmado con MD5 propio). Cola persistente con 5 reintentos; se vacía al arrancar |
| `BackupService` | Un `.json` con las secciones que existan (favoritos, listas, colas, pistas largas, estadísticas, emisoras, tema, scrobbling, presets de EQ, sesión). Exportar/restaurar desde **Ajustes**, copiando el JSON tal cual para que la restauración quede idéntica |

Decisiones y límites:

* **El núcleo solo abre archivos**, así que ni la radio ni la nube son flujos
  continuos: se capturan 12 s (o 24 MB) y se reproducen (R35). Para la radio es
  suficiente para escuchar; para un disco en la nube se baja el archivo entero.
* **Sin paquetes nuevos**: `dart:io` para HTTP, `file_selector` (ya estaba) para
  elegir archivos y un **MD5 portado a mano** (RFC 1321) para Last.fm, con los
  vectores de siempre probados en `flutter test`.
* **Credenciales en claro** en `network.json`/`scrobbler.json`, que viven en el
  directorio privado de la app: es lo mismo que ya hacía la sesión y se avisa en
  la UI. Cifrarlas pediría `flutter_secure_storage`, es decir, un paquete (R36).
* **El scrobbling vive en la app, no en Ajustes**: `main.dart` crea el
  `Scrobbler` al arrancar y lo publica en `ScrobblerHost`; Ajustes solo lo
  configura. Hay que añadir esa línea fuera del alcance del pedido porque, si no,
  la escucha solo se contaría con Ajustes abierto.
* **«Ahora suena» no se publica**: solo se envía la escucha cerrada, que es lo
  que de verdad pide el 50 %/4 min.

Tests nuevos (28, `test/backup_and_radio_test.dart`): emisoras (alta, idempotencia
por URL, renombrado, baja, `.m3u`/`.pls` reales, exportación, persistencia y JSON
roto), bajada contra un `HttpServer` local con ventana y extensión por
content-type, resolución de listas y 404; MD5 y firma de Last.fm, umbral del
50 %/4 min, pistas cortas, scrobbling apagado, envío real a los dos servicios
contra un servidor local, sin red (queda pendiente) y persistencia; copia
(secciones presentes, restauración, secciones desconocidas/rotas, rechazo de un
JSON ajeno y nombre sugerido); WebDAV (`207` con espacios codificados, listado
real y `network.json`); y cinco de widget (Ajustes con las dos secciones nuevas,
interruptor de scrobbling, exportador con y sin pista).

---

## 6. Plataformas

### Escritorio (PC, Arch)

```bash
flutter pub get && flutter run -d linux      # CMake compila el núcleo y lo empaqueta
cd packaging/linux && makepkg -si            # paquete nativo con .desktop e icono
```

- `linux/CMakeLists.txt` ejecuta `zig build -Drelease=true -Ddecoder=auto
  --prefix <build>/cyberhex_core` y copia el `.so` a `bundle/lib/` (rpath
  `$ORIGIN/lib`). Vigila `src/`, `include/`, `vendor/`, `build.zig(.zon)`.
- `-DCYBERHEX_DECODER=miniaudio|ffmpeg|auto` desde CMake.

#### Fase 7A (pedido 8): escritorio de verdad, sin paquetes nuevos

| Pieza | Qué hace |
|---|---|
| `linux/runner/my_application.cc` (594) | `G_APPLICATION_HANDLES_COMMAND_LINE` con instancia única: `cyberhex archivo.flac` (o «Abrir con CyberHex») llega al canal `cyberhex/intent` (`onOpenFile`), y en arranque en frío sale por `getInitialFile`. La segunda ejecución se reenvía por D-Bus a la primera. `GtkWindow` acepta `text/uri-list`/`text/plain` y manda las rutas a `cyberhex/desktop` (`onDropPaths`). |
| `linux/runner/mpris_bridge.{h,cc}` (65 + 598) | `org.mpris.MediaPlayer2.cyberhex` por GDBus: `PlayPause`, `Play`, `Pause`, `Stop`, `Next`, `Previous`, `Seek`, `SetPosition`, `OpenUri`, `Raise`, `Quit`, propiedades (`PlaybackStatus`, `Metadata` con `mpris:length`, `LoopStatus`, `Shuffle`, `Volume`, `Position`, `Can*`) y señal `Seeked`. Sin sesión de D-Bus no se registra nada y la app sigue igual. |
| `lib/platform/desktop_channel.dart` (276) | Lado Dart: empuja metadatos/estado (µs, límite de 1 Hz en la posición), recibe el transporte (`play`…`setShuffle`), expone `setAlwaysOnTop`, `notifyTrack` (`GNotification`) y `Stream<List<String>> drops`. Fuera de Linux todo es `MissingPluginException` ignorada. |
| `PlayerPage` | Atajos: **espacio** play/pausa, **←/→** ±5 s, **Shift+←/→** anterior/siguiente, **↑/↓** volumen ±5 %, **M** silencio, **L** repetición, **S** aleatorio (con `Focus(autofocus)` para que funcionen sin tocar nada). Drag & drop: la primera pista suena, las demás se encolan y las carpetas se escanean con el motor. |
| `SettingsPage` | Sección **«Salida de audio y escritorio»**: dispositivo de salida (`outputDevices`/`setOutputDevice`), salida **S16 con dither TPDF**, ventana siempre encima y notificación de la pista actual. |

Decisiones y límites:

- **Las teclas multimedia globales no se capturan con `XGrabKey`**: eso rompe
  Wayland y pelea con el entorno. Se publican por **MPRIS**, que es el canal que
  usan GNOME, KDE, `playerctl` y los cascos Bluetooth; el entorno es quien
  traduce la tecla. Es lo estándar y lo que el usuario espera (**R34**).
- **El drag & drop lo captura GTK**, no Flutter: el runner entrega rutas, no
  texto. Si un día Flutter lo captura antes, la ruta no llegaría a Dart (**R33**).
- Los archivos sueltos siguen abriéndose con el canal `cyberhex/intent` que ya
  existía: no se duplicó el camino ni se tocó Kotlin.

### Android

```bash
cd core && ./build_ffmpeg_android.sh arm64-v8a   # una vez (10-20 min, necesita NDK)
flutter build apk --release                       # Gradle compila el núcleo
```

- `abiFilters = arm64-v8a`; tarea `buildCyberHexCore` incremental y saltable con
  `--android-project-arg=skipCoreBuild=true`.
- Manifest: `READ_MEDIA_AUDIO`, `READ_EXTERNAL_STORAGE` (≤12), `WAKE_LOCK`,
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` y
  `POST_NOTIFICATIONS`; `<service android:name=".MediaSessionService"
  android:foregroundServiceType="mediaPlayback" android:stopWithTask="false">`.
- **Riesgo actual**: sin FFmpeg estático, el APK no reproduce `.m4a/.aac`
  (miniaudio solo trae WAV/FLAC/MP3/Vorbis).

#### Reproducción en segundo plano (P0.1, escrito)

El motor de audio sigue en Dart; Kotlin **no** reproduce nada. Tres piezas:

```
PlayerController ──updateMetadata/updateState──▶ MediaBridge ──▶ MediaSessionService
      ▲                                                              │
      └──── play/pause/toggle/next/previous/seek/duck ◀── MediaSession.Callback,
                                                          acciones de la notificación,
                                                          audio focus, becoming-noisy
```

| Pieza | Detalle |
|---|---|
| `MediaBridge.kt` (205) | Dueño del `MethodChannel("cyberhex/media")`. Guarda el último snapshot y lo reenvía al servicio cuando se engancha (servicio recreado). Si el canal no existe, **encola hasta 16 comandos** y los drena en `connect()`. |
| `MediaSessionService.kt` (566) | Servicio en primer plano `mediaPlayback`. Publica `MediaSession` + `PlaybackState` (`ACTION_PLAY/PAUSE/PLAY_PAUSE/SKIP_TO_NEXT/SKIP_TO_PREVIOUS/SEEK_TO/STOP`) y `MediaMetadata` (título, artista, álbum, duración y carátula reducida a ≤1024 px). |
| `MainActivity.kt` (52) | `configureFlutterEngine` → `MediaBridge.connect`; `cleanUpFlutterEngine` → `disconnect`; `POST_NOTIFICATIONS` en runtime desde `onPostResume` (API 33+). |

Estados de la notificación:

- **Suena**: `startForeground()` (con `FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK` en
  API 29+), notificación `ongoing` — no se puede deslizar. Tres acciones (anterior,
  play/pausa, siguiente) en la vista compacta vía `Notification.MediaStyle`.
- **Pausa**: `stopForeground(STOP_FOREGROUND_DETACH)`; en API < 24
  `stopForeground(false)`. Se repinta con `setOngoing(false)` y `deleteIntent`, así
  que **deslizarla cierra** la reproducción (`pause` a Dart + `stopSelf()`).
- **Cierre**: `START_NOT_STICKY` y `stopWithTask="false"`: quitar la tarea de
  Recientes no mata el servicio.

Audio focus (`AudioFocusRequest` en API 26+, API clásica por debajo):

| Evento | Reacción |
|---|---|
| `LOSS` | `pause` (definitiva, no se reanuda) |
| `LOSS_TRANSIENT` | `pause` y **reanuda** al llegar `GAIN` |
| `LOSS_TRANSIENT_CAN_DUCK` | `duck(true)`; `duck(false)` en `GAIN` (25 % del volumen del usuario, restaurado exacto) |

Si el foco se **niega** al empezar, se manda `pause` a Dart: nunca suena sin
foco. Auriculares fuera: receptor dinámico de `ACTION_AUDIO_BECOMING_NOISY` →
`pause`. Todos los `PendingIntent` usan `FLAG_IMMUTABLE` en API ≥ 23; cada acción
lleva su propio *action* y *requestCode* para no colisionar.

> **Resuelto en P0.4:** `CyberHexApplication` crea el `FlutterEngine` al nacer el
> proceso, lo deja en `FlutterEngineCache` bajo `"cyberhex_engine"` y engancha
> `MediaBridge` antes de que exista ninguna ventana. `MainActivity` lo reutiliza
> (`provideFlutterEngine`) y responde `shouldDestroyEngineWithHost() = false`:
> cerrar desde Recientes destruye la vista, **no** el isolate de Dart ni el hilo
> de audio. Se extiende `android.app.Application` y no `FlutterApplication`
> (deprecada desde Flutter 3.29; era una subclase vacía de `Application`).

#### Fase 6B (pedido 7): widget, azulejo, coche y botones del casco

Todo esto vive en `android/` y **no añade ni un paquete**: solo API del sistema.
Ninguna de estas piezas reproduce audio; mandan comandos al
`MediaSessionService`, que es el único que habla con Dart.

| Pieza | Qué hace |
|---|---|
| `MediaSettings.kt` (234) | Preferencias que Android lee **sin la app abierta**: auto-play al conectar y botones de la notificación. `SharedPreferences` (`cyberhex_media`), porque las leen servicio, widget y azulejo. `MediaAction` (anterior / play-pausa / siguiente / cerrar) con orden canónico y `toggle` obligatorio. Método `apply` para el `configure` que manda Dart. |
| `PlaybackCache` (mismo archivo) | Última pista conocida (título, artista, álbum, sonando, posición, duración) + carátula en `filesDir/widget_art.png`. El servicio la vuelca al cambiar play/pausa o cada 5 s de posición, no en cada latido. |
| `CyberHexWidgetProvider.kt` (186) | Widget **4x1**: carátula, título, anterior / play-pausa / siguiente y progreso. `RemoteViews` con widgets del sistema. `PendingIntent` a `MediaSessionService` con `FLAG_IMMUTABLE` desde M. `CyberHexWidgetLargeProvider` = 4x2 (carátula 72 dp y barra). |
| `CyberHexTileService.kt` (72) | Azulejo de ajustes rápidos, `@RequiresApi(N)`; icono e estado desde `PlaybackCache`, toque → `toggle`/`play`. |
| `CyberHexBrowserService.kt` (109) | `android.service.media.MediaBrowserService` **del sistema** (API 21+, sin AndroidX) para Android Auto: raíz `cyberhex_root` → `cyberhex_now` con la pista actual. El transporte lo pone el token de la `MediaSession`. |
| `res/xml/automotive_app_desc.xml` | `<automotiveApp><uses name="media"/></automotiveApp>` en el manifiesto (`com.google.android.gms.car.application`): sin esto el coche no lista la app. |

Cambios en `MediaSessionService` (779) y `MediaBridge` (232):

- **Doble y triple pulsación** del botón del casco
  (`onMediaButtonEvent`): 1 → play/pausa, 2 → siguiente, 3 → anterior, con
  ventana de 420 ms. Un clic tarda ese margen en actuar: es el precio de
  distinguir 1 de 2.
- **Auto-play al conectar** (`ACTION_HEADSET_PLUG` y
  `BluetoothDevice.ACTION_ACL_CONNECTED`, receptor dinámico
  `RECEIVER_NOT_EXPORTED`): solo si el usuario lo activó, hay pista en pausa y
  nada sonando ya. La clavija no se usa para pausar: de eso se encarga
  `ACTION_AUDIO_BECOMING_NOISY`.
- **Acciones de la notificación elegibles**: se pintan en el orden canónico y la
  vista compacta usa las tres primeras; «Cerrar» manda `stop` → `pause` a Dart y
  `stopSelf()`.
- **`configure`** en el canal `cyberhex/media`: Dart empuja auto-play y botones
  al arrancar y en cada cambio de `ThemeController`; Kotlin solo repinta si algo
  cambió.
- **`dartReady`**: el servicio sabe si Dart tiene manejador. Si un toque del
  widget o del azulejo llega sin nadie escuchando, **abre la app** en vez de
  perder el comando (el motor arranca, `MainActivity` monta el canal y la sesión
  se restaura).

Límites conocidos (R30–R32): sin SDK de Android no se compilan ni se ejecutan
estas piezas aquí; el `MediaBrowserService` solo publica la pista actual (no hay
catálogo, porque la biblioteca vive en Dart); el auto-play por Bluetooth necesita
`BLUETOOTH_CONNECT` concedido a mano (el de la clavija no).

---

## 7. Verificación

### 7.1 Lo que el agente **sí** puede ejecutar aquí

| Qué | Comando | Resultado último |
|---|---|---|
| Tests Zig (31) | `cd core && zig build test -Ddecoder=miniaudio` | 31/31 |
| `.so` nativa | `zig build-lib … -O ReleaseFast` | 4,0 MB, 97 símbolos |
| `.so` aarch64 | `zig build-lib … -target aarch64-linux-gnu -mcpu cortex_a73` | 3,9 MB |
| Humo con audio real | `cd core && zig build smoke` | 0 fallos (RMS 0.4997, pausa 0.4000→0.4000, loop 10/10) |
| Sintaxis C | `gcc -fsyntax-only -std=c2x -Wall -Wextra` | limpio |
| Sintaxis Dart | tree-sitter-dart sobre `lib/` y `test/` | 56/56 sin errores |
| Firmas de `PlayerApi` | comprobador propio: 112 miembros en `NativePlayer` y `FakePlayer` | 112/112 en ambos |
| Tests del núcleo | `cd core && zig build test -Ddecoder=miniaudio` | 31/31 |
| Prueba de humo | `cd core && zig build smoke -Dsmoke-dir=/tmp` | 0 fallos |
| Símbolos del `.so` | `nm -D` | 199 `ch_*`; los 122 que usa el `.dart` presentes |
| Coherencia del canal | grep cruzado Dart↔Kotlin de nombres de método | 2/2 y 7/7 sin huérfanos |
| XML de Android | `ElementTree` sobre `AndroidManifest.xml` | válido; 6 permisos, 1 servicio `mediaPlayback` |
| Llaves/paréntesis Kotlin | escáner propio que ignora strings y comentarios | 3/3 balanceados |
| Layout FFI | `sizeof/offsetof` en C vs `_ChEvent` | 24 B, 0/4/8/16 |
| Integración CMake | harness con CMake 4.4 + Zig 0.17.1 | compila; 2ª pasada no-op |
| MD5 propio (Last.fm) | transliteración a Python comparada con `hashlib` | `''`, `abc` y el pangrama coinciden |
| Canales y JSON de la 7B | lectura cruzada de nombres de archivo/miembro | los 10 `.json` y los miembros usados por las páginas existen |

### 7.2 Lo que **no** se puede verificar aquí (lo hace el usuario)

- `flutter analyze` / `flutter test` — **no hay SDK de Dart/Flutter** y no se
  puede instalar (la red solo permite github/npm/pypi; el SDK vive en
  `storage.googleapis.com`).
- `flutter build linux` / `flutter build apk` — sin GTK, sin NDK, sin FFmpeg de
  desarrollo, sin `pub.dev` (no se pueden añadir dependencias nuevas y validarlas).
- Cualquier prueba en el teléfono.

- `kotlinc` / Gradle: tampoco hay JDK ni caché de Maven en este entorno, así que
  **el Kotlin del servicio tampoco compila aquí**.

> **Regla para el arquitecto:** todo pedido que toque Dart, Kotlin, Gradle o
> `pubspec.yaml` sale de aquí como "escrito y revisado", nunca como "probado".

---

## 8. Decisiones y contratos que no se rompen sin pedido explícito

1. Un solo núcleo para PC y Android; FFI en C plano.
2. 48 kHz y estéreo fijos; sin multicala ni remuestreo propio.
3. La posición cuenta el audio del fundido de pausa (arregla la deriva de 50 ms).
4. El loop A-B se cancela al cambiar de pista y usa el camino del `seek`.
5. `set_replaygain_mode` solo afecta a pistas que se abran **después**.
6. Los símbolos FFI nuevos se bindean con `providesSymbol` (compatibilidad hacia atrás).
7. `PlayerController` no conoce FFI: `PlayerApi` inyectable, tests sin `.so`.
8. Commits pequeños y reversibles, mensajes en español, un pedido por commit.
9. `next()`/`previous()` son **void** y no tocan el estado: el cambio de pista lo
   anuncia `CH_EVENT_TRACK` y el controlador relee etiquetas.
10. Canal `cyberhex/media` (contrato congelado):
    - **Dart → Kotlin**: `updateMetadata{title,artist,album,durationMs,art}`,
      `updateState{playing,positionMs,durationMs,buffering}` (≤1 Hz).
    - **Kotlin → Dart**: `play`, `pause`, `toggle`, `next`, `previous`,
      `seek(double segundos)`, `setVolume(double 0..1)`, `duck(bool)`.
    - Todo devuelve `Future<bool>`/`Boolean`; `MissingPluginException` se ignora.
    - Sin `androidx.media` ni media3: `android.media.session.MediaSession` +
      `Notification.MediaStyle` (API 21+), cero dependencias nuevas.
11. Canal `cyberhex/intent` (abrir audio desde fuera):
    - **Dart → Kotlin**: `getInitialFile` → `String?` (el archivo con el que se
      abrió la app; se entrega una sola vez).
    - **Kotlin → Dart**: `onOpenFile` con la **ruta POSIX** ya materializada.
    - Un `content://` se copia a `cacheDir/shared_audio/shared_<hash>.<ext>`
      antes de cruzar el canal: el núcleo solo abre rutas de archivo.
    - Si el `Intent` llega antes que Dart, queda pendiente y lo recoge
      `getInitialFile` (no hay carrera perdida).
12. Repetición: 0 = apagado, 1 = todo, 2 = una; `cycleRepeat()` va 0→1→2→0 y se
    lee del motor (`ch_engine_repeat`), no de un espejo en Dart.
13. La cola es del motor y su **espejo de rutas** es de `NativePlayer`: nadie
    más puede mutar la cola sin pasar por él, o el espejo se desincroniza.
    `queue_add` devuelve el índice; `load_add` no (se lee con `queue_index`).
14. `queueProtected` cambia el significado de `openFile`: con el flag, se usa
    `load_add` (añade al final y reproduce); sin él, `load` (la cola queda con
    esa única pista). La UI no decide, solo cambia el flag.
15. Cadena DSP fija y en este orden: **karaoke → 9D → ancho/punch → crossfeed
    → modo noche → balance → limitador**. Todo en el callback de audio, con los
    parámetros en `std.atomic.Value` (flotantes como bits en `u32`), sin
    candados y sin reservar memoria. Cualquier procesador nuevo entra aquí, no
    en un hilo aparte.
16. Los símbolos DSP tienen rango cerrado en el motor (`speed` 0.05..2,
    `depth`/`punch`/`vocal`/`level`/`night` 0..1, ancho 0..2) y la API recorta
    igual en `NativePlayer` y en `FakePlayer`: la UI no puede sacar al motor de
    su rango.
17. `ch_engine_set_stereo_width` (histórico) y `ch_engine_set_stereo_enhance`
    comparten el mismo mando de ancho: no hay dos anchos que se peleen.
18. La salida es f32 por defecto. El camino **S16 con dither TPDF** es opt-in
    (`ch_engine_set_s16_output`) y reabre el dispositivo; al hacerlo se
    conserva la configuración y se reanuda si estaba sonando.
19. La sesión es un JSON pequeño y prescindible: si falta, está vacío o está
    corrupto, la app arranca igual. Nunca se guarda una pista sin ruta y el
    índice se recoloca al filtrarlas.
20. El **paisaje sonoro** se suma a la mezcla después de crossfeed/modo noche y
    **antes del balance y del limitador**; con preset 0 o nivel 0 no cuesta nada
    (`isIdle`). Es determinista por semilla y no reserva memoria en el callback.
    Su estado **no** viaja en `ch_engine_save_state`: lo guarda la app en
    `SessionStore`.
21. El **exportador WAV** es siempre 48 kHz estéreo S16 con dither TPDF y
    limitador de seguridad a −1 dBFS; nunca remuestrea (el decodificador ya
    entrega 48 kHz) y devuelve códigos negativos documentados en vez de escribir
    un fichero a medias.
22. `ch_engine_detect_bpm` devuelve 0 (no un valor aproximado) cuando no hay
    pulso, y en cualquier caso un número entre 60 y 200. No toca el motor ni el
    audio en curso: decodifica aparte, como mucho 30 s.
23. Los ajustes de audio (9D, estéreo, karaoke, crossfeed, noche, balance, modo
    de canales, ReplayGain, crossfade, gapless, velocidad, tono y paisaje) se
    persisten en la **sesión de Dart** (`AudioSettings` dentro de
    `SessionSnapshot`, formato 2), nunca en `ch_engine_save_state`. Al arrancar,
    `SessionKeeper` los vuelca con una sola pasada (`applyAudioSettings`).
24. `PlayerApi` es el contrato único: si algo existe en el núcleo y la UI lo
    necesita, se añade a `PlayerApi` **y** a `NativePlayer` **y** a `FakePlayer`
    en el mismo commit. Ningún símbolo FFI nuevo sin `providesSymbol`.

---

## 9. Deuda técnica y riesgos

| # | Riesgo | Detalle | Dónde |
|---|---|---|---|
| R1 | Dart/Kotlin sin compilar | nadie ha pasado `flutter analyze`/`kotlinc`; el puente y el servicio son lo más nuevo y lo más frágil | `lib/`, `android/` |
| R2 | Sin FFmpeg en Android | `.m4a/.aac/.alac` no suenan si no se compila el estático | `build_android.sh` |
| R3 | 48 kHz fijos | en PC con DAC a 44,1 kHz todo pasa por resample | `root.zig` |
| R4 | Pausa cerca del fin de pista | el fundido puede avanzar `played` al segmento siguiente | `root.zig`, render |
| R5 | A-B se cancela al cambiar de pista | la UI debe re-aplicar si quiere loops persistentes | `addSegment` |
| R6 | Vúmetro post-limitador | muestra la señal ya limitada | `applyLevels` |
| R7 | ~~Sin dither a S16~~ | **resuelto** en la fase 2: TPDF ±1 LSB opt-in (`ch_engine_set_s16_output`) y también en el exportador WAV | `audio.c`, `root.zig` |
| R8 | `ffmpeg.tar.xz` en git | ~decenas de MB; decisión de empaquetado pendiente (A4) | `core/third_party/` |
| R9 | Sin CI | ninguna acción de GitHub valida nada | `.github/` (no existe) |
| R10 | Android antes de P0.1 | ~~sin MediaSession ni servicio~~ **resuelto** en P0.1 (notificación, bloqueo, foco, auriculares) | `android/` |
| R11 | ~~Recientes mata el motor~~ | **resuelto**: engine cacheado en `CyberHexApplication`, `shouldDestroyEngineWithHost = false` | `CyberHexApplication.kt` |
| R12 | ~~Icono genérico en la notificación~~ | **resuelto**: `R.drawable.ic_launcher_foreground` (hexágono propio) | `MediaSessionService.kt` |
| R14 | ~~Sesión en Android~~ | **resuelto**: canal `cyberhex/storage` → `filesDir`; en Linux `$XDG_DATA_HOME/cyberhex` o `~/.local/share/cyberhex`; el temporal queda solo como último recurso | `CyberHexApplication.kt`, `session_store.dart` |
| R16 | ~~DSP sin interfaz~~ | **resuelto**: el laboratorio de audio expone los seis procesadores, la medición, el transporte y las herramientas | `audio_lab_sheet.dart` |
| R17 | Coste del DSP | la cadena entera (9D + ancho + punch + crossfeed + noche) son ~40 operaciones por muestra a 48 kHz; en el Redmi es despreciable y `isIdle()` la salta por completo cuando todo está apagado | `dsp_spatial.zig` |
| R20 | ReplayGain on/off sin getter | el núcleo solo exporta `ch_engine_set_replaygain`; el valor se recuerda en `NativePlayer` (arranca activado, como el motor) y se reenvía al restaurar | `native_player.dart` |
| R21 | Exportar/BPM en isolate | las dos tareas decodifican el archivo entero; un tema largo tarda segundos y ocupa CPU. Van en `Isolate.run` y la hoja solo muestra «Exportando…»: no hay barra de progreso | `native_player.dart`, `audio_lab_sheet.dart` |
| R22 | UI sin verificación visual | no hay SDK de Flutter aquí: la sintaxis se parsea con tree-sitter (56/56), las firmas que usa la UI se comprueban contra `PlayerController`/`PlayerSnapshot` por regex y los 14 tests de widget se escriben pero **no se ejecutan**. Alturas, desbordes y contraste los tiene que ver el usuario | `test/audio_lab_test.dart` |
| R28 | Paleta solo en parte de la app | el reproductor, el mini-reproductor y los ajustes leen `paletteOf(context)`; el resto de pantallas siguen con las constantes neón, así que el tema Claro se ve a medias fuera del reproductor | `lib/ui/` |
| R29 | Gestos sin probar en pantalla táctil | doble toque, arrastres y modo bolsillo están probados simulados en `flutter test`; falta verlos con el dedo (zonas, umbrales de velocidad y pulsación larga) | `player_page.dart` |
| R33 | Runner GTK sin compilar aquí | `my_application.cc` y `mpris_bridge.cc` están escritos contra GTK3/GIO, pero en el sandbox no hay `pkg-config`, cabeceras de GTK ni `cmake`: solo se comprobó el balanceo de llaves/paréntesis y que los `#include` propios existen. Falta verlos con `flutter run -d linux` | `linux/runner/` |
| R34 | Sin atajos globales fuera de la app | las teclas multimedia y los botones del teclado del portátil no se capturan con `XGrabKey` (rompería Wayland): se delegan en MPRIS, que es lo que usan GNOME/KDE/`playerctl`/Bluetooth. Fuera de un entorno de escritorio no hay teclas globales | `mpris_bridge.cc` |
| R30 | Widget, azulejo y `MediaBrowserService` sin compilar ni ejecutar | escritos contra la API del sistema (sin AndroidX ni paquetes nuevos), pero aquí no hay JDK/Gradle/emulador: faltan por verificar el aspecto real de los `RemoteViews`, que el lanzador acepte los dos `<receiver>` y que Android Auto liste la app | `android/app/src/main/` |
| R31 | El navegador de medios solo publica la pista actual | `onLoadChildren` devuelve `cyberhex_now` (título, artista, álbum) desde `PlaybackCache`; no hay catálogo ni carpetas porque la biblioteca vive en Dart y no se puede consultar de forma síncrona desde Kotlin | `CyberHexBrowserService.kt` |
| R32 | Auto-play por Bluetooth condicionado a un permiso | `ACTION_ACL_CONNECTED` solo se entrega con `BLUETOOTH_CONNECT` (Android 12+), que se declara pero no se pide en runtime: si el usuario no lo concede, ese auto-play no ocurre (el de la clavija sí) | `MediaSessionService.kt` |
| R26 | Descargas sin verificar en red real | el descargador se prueba contra un `HttpServer` local y contra los parsers del JSON de Archive; falta comprobar la API real (límites, ítems enormes, redirecciones) y que el archivo descargado suene | `audio_downloader.dart` |
| R27 | Automix sin audio real | el plan y la máquina de estados están probados con un `BpmProbe` inyectado; falta oír una mezcla de verdad y decidir si ±8 % es el límite bueno | `automix_engine.dart` |
| R24 | Etiquetas sin comprobar en el teléfono | el escritor ID3v2.3/Vorbis se ha probado contra sus propios lectores y bytes sintéticos; falta validar con archivos reales de la biblioteca del usuario (carátulas grandes, nombres con emoji, FLAC con bloques raros) | `tag_editor.dart` |
| R35 | Radio y nube con búfer, no continuas | el núcleo abre archivos: la radio se captura en ventanas de 12 s/24 MB y suena desde el temporal (hay un salto entre ventanas y no hay metadatos en directo); un archivo de nube se baja entero antes de sonar | `radio_store.dart` |
| R36 | Credenciales en claro | usuario/contraseña de WebDAV y tokens de ListenBrainz/Last.fm se guardan legibles en el directorio privado de la app; cifrarlos exige `flutter_secure_storage` (paquete nuevo) | `network_page.dart`, `scrobbler.dart` |
| R37 | WebDAV mínimo | solo `PROPFIND Depth: 1`, Basic/Bearer y descarga por URL; sin `MKCOL`, `PUT`, `LOCK`, ni paginación. Los enlaces «compartidos» de Nextcloud/Dropbox/Drive solo funcionan si la URL descarga el archivo directamente | `network_page.dart` |
| R25 | Forma de onda decorativa | la tarjeta compartible dibuja una silueta determinista, no los picos reales, porque el núcleo no los expone | `share_card_sheet.dart` |
| R23 | Presets a 36 llamadas | aplicar un preset dispara 36 `ch_engine_set_band_gain` seguidos (cada uno recalcula los coeficientes de su banda): es instantáneo, pero si algún día la cadena se vuelve pesada hará falta un volcado en bloque en el núcleo | `eq_presets.dart` |
| R18 | ~~Paisaje sin mando en la UI~~ | **resuelto**: atajo en el pie del reproductor y control con nivel en el laboratorio | `player_page.dart` |
| R19 | Coste del exportador | decodifica y procesa a velocidad de CPU; un tema de 5 min tarda unos segundos y ocupa 57 MB en disco. Si el decodificador no sabe la duración, hace dos pasadas | `root.zig` |
| R15 | Duración en la biblioteca | el núcleo solo da rutas: no hay consulta de duración por ruta (`ch_loudness_scan` decodifica el archivo entero). La ordenación por duración y el filtro «< 30 s» solo ven las pistas ya reproducidas; el resto sale con «—» y nunca se oculta | `library_page.dart` |
| R13 | FGS desde segundo plano | Android 12+ prohíbe arrancar un FGS en background salvo excepciones; aquí se arranca al pulsar play con la app delante | `MediaBridge.ensureServiceStarted` |

---

## 10. Backlog priorizado

### P0 — completar la app de móvil

| # | Tarea | Alcance | Bloqueos |
|---|---|---|---|
| P0.1 | ~~`MediaSession` + servicio en primer plano~~ **HECHO** (turno 9): servicio, foco, notificación y bloqueo, sin dependencias nuevas | Kotlin + manifest + Dart | falta compilar y probar en el teléfono |
| P0.4 | ~~`FlutterEngine` cacheado en una `Application`~~ **HECHO**: `CyberHexApplication` + `provideFlutterEngine` + `shouldDestroyEngineWithHost = false` | Kotlin + manifest | falta probar en el teléfono |
| P0.6 | Escritorio: consumir `%U` (el `.desktop` ya lo pasa, el runner no lo entrega a Dart) | runner C++ o `dart:io` con `Platform.environment` | requiere tocar el runner de Linux |
| P0.5 | Bindear en Dart la API que trajo `main`: R128 (`ch_engine_analyze_loudness`), picos de forma de onda, ganancia manual en dB, crossfeed, hojas CUE y guardado de carátula | Dart | círculo de 1 turno; el núcleo ya está fusionado y verificado |
| P0.2 | Pantallas de **biblioteca** (escaneo con `ch_library_*`) y **cola** (reordenar, quitar, saltar) | Dart | no verificable aquí |
| P0.3 | ~~Abrir archivos desde el gestor~~ **HECHO en Android** (`ACTION_VIEW` + copia de `content://` + canal `cyberhex/intent`); el `.desktop` ya lleva `Exec=cyberhex %U` | Kotlin + Dart | en Linux falta el puente de argv (P0.6) |

### P1 — calidad y plataforma

| # | Tarea | Notas |
|---|---|---|
| P1.1 | MPRIS en Linux (`org.mpris.MediaPlayer2`) | D-Bus por MethodChannel o FFI; da controles desde el escritorio |
| P1.2 | Sample rate nativo (44,1/48/96) con `ma_device` a la tasa del dispositivo | toca `ch_audio_create`, decodificadores y EQ |
| P1.3 | Dither TPDF al convertir a S16 | 20 líneas en `audio.c` |
| P1.4 | Crossfeed Bauer para auriculares | 30 líneas en `render` |
| P1.5 | ~~UI del vúmetro y del espectro~~ **HECHO** (turno 16): `VisualizerWidget` con barras o hexágonos y medidores RMS/pico | falta verlo en el teléfono |
| P1.6 | ~~UI de ReplayGain por álbum, balance, mono y loop A-B~~ **HECHO** (turno 16) en el laboratorio de audio | falta verlo en el teléfono |

### P2 — alcance

CUE sheets · trim de `skip_samples` (gapless real) · Windows/macOS como tercer
target · streaming HTTP (requiere FFmpeg con red) · CI con `zig build test` y
`zig build smoke`.

### P3 — grande, solo con pedido explícito

Multicala · grabadora · separación de fuentes / IA · letras karaoke avanzadas.

---

## 11. Entorno del agente (importante para dimensionar pedidos)

| Tiene | No tiene |
|---|---|
| Zig 0.17.1 (venv en `/tmp`), gcc, python3, cmake 4.4, tree-sitter-dart | Flutter, Dart, NDK, GTK, FFmpeg de desarrollo, `pub.dev` |
| Dispositivo de audio virtual (la prueba de humo reproduce de verdad) | Salida a `storage.googleapis.com`, `pub.dev`, AUR |

- Red permitida: `github.com`, `codeload.github.com`, `api.github.com`,
  `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`.
- El sandbox **se reinicia**: `/tmp` puede perderse (Zig se reinstala con
  `pip install ziglang`), el repo persiste.

---

## 12. Changelog (45 commits + fusión de `main` desde `eca1490`)

```
FASE 7B → app: radios por Internet, WebDAV/nube, exportador con DSP, scrobbling y copia
FASE 7A → linux: MPRIS2, %U, drag & drop, siempre encima y notificaciones
FASE 6B → android: widget 4x1/4x2, azulejo, coche, doble clic del casco y auto-play
FASE 6A → app(ui): cuatro temas, color de carátula, gestos, mini-reproductor y bolsillo
FASE 5 → app(ui): listas .m3u, cinco colas, automix, estadísticas y descargas
FASE 4 → app(ui): letras sincronizadas, estudio .lrc, etiquetas y tarjetas compartibles
FASE 3-3 → app(ui): laboratorio de audio, visualizador, presets y prueba de audición
FASE 3-2 → app(core): toda la API del motor en Dart y DSP persistido en la sesión
FASE 3-1 → core: paisajes sonoros, detector de BPM y exportador WAV
FASE 2-4 → app(core): bindings y estado Dart de todo el DSP
FASE 2-3 → core(dsp): crossfeed Bauer, modo noche y dither TPDF en S16
FASE 2-2 → core(dsp): motor 9D espacial, potenciador estéreo y modo karaoke
FASE 2-1 → app: directorio persistente real para sesión y favoritos (R14)
FASE 1B-3 → app(ui): pantalla de biblioteca con favoritos
FASE 1B-2 → app(ui): pantalla de cola y sesión que sobrevive al cierre
FASE 1B-1 → app(core): cola de reproducción y biblioteca por FFI
FASE 1A-3 → app(ui): repetir (off/todo/una) y aleatorio de punta a punta
FASE 1A-2 → android+app: abrir audios desde el sistema (ACTION_VIEW, %U)
FASE 1A-1 → android: motor cacheado en la Application (P0.4) + icono hexagonal
FUSIÓN → main en la rama: 3 conflictos de núcleo resueltos (build.zig, root.zig, API.md)
PEDIDO 3 → android: servicio en primer plano, MediaSession, foco y notificación
PEDIDO 2 → app(platform): puente Dart ↔ servicio de medios por MethodChannel
PEDIDO 1 → app(core): next/previous desde el FFI hasta el controlador
2a330cd core: EQ de 36 bandas consultable y set_band_gain que conserva el resto
cb70420 app: metadatos, carátula y ecualizador real de 36 bandas
db40214 build(android): tarea del núcleo incremental y opcional
2f55173 docs: README real, LICENSE MIT y análisis del proyecto
b519832 app(eq): estilos const en la hoja del ecualizador
cf08ef1 docs(analisis): estado de las correcciones y verificación con Zig 0.17.1
3db1560 core: cola sin vaciar (play_index/load_add) y audio sin spinlocks
ba04bf0 core(eq): reinicia solo la banda que cambia y no gira en el callback
ced0785 core(library): escaneo a prueba de ciclos, rutas largas e indice hash
0962ae3 app: deja de reconstruir toda la pantalla cada 250 ms
6e19f24 docs(analisis): estado tras la segunda tanda (cola, RT, EQ, biblioteca)
46772ef app(core): PlayerApi, PlayerEvent y PlayerSnapshot sobre FFI
e0767b3 app: PlayerController y pantalla conectada al estado
d82e41b core(audio): vumetro, preamp, ReplayGain de album, fade de pausa y loop A-B
1aa636d app: bindear las funciones nuevas del motor
e2b8308 docs: API y estado tras la tanda de audio
1dc1399 test(app): desmontar la página al final de cada test de widget
6a5e44a core(build): decodificador auto y prueba de humo para PC y Android
77dc231 core(audio): balance, modo de canales y version de ABI
f5f5f46 app: bindear balance, modo de canales y ABI del nucleo
1bfe206 docs: dos plataformas con un solo nucleo y funciones nuevas
276868c linux: build del núcleo correcto, incremental y con decoder configurable
c1ff6af packaging(arch): PKGBUILD, lanzador .desktop e icono
a9767fd android: icono adaptativo propio y permisos de biblioteca
a3e5f31 docs: Arch, permisos de Android y banderas reales de Zig 0.17
c2755c3 core(build): error claro si se pide FFmpeg y no está
```
