# CyberHex — Informe para el arquitecto

> **Para qué sirve este archivo.** Un agente (Arena/Claude) ejecuta el código; un
> arquitecto (Gemini/AI Studio) planifica. Este informe es la única fuente de
> verdad del estado real: qué existe, qué está probado, qué no se puede probar
> aquí y qué falta. Se actualiza al final de cada turno; el detalle cronológico
> vive en [`BITACORA.md`](BITACORA.md).
>
> Última actualización: 2026-11-21 · rama `arena/3351fdb0-cyberhex` · HEAD `c2755c3`

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
- App: **6 699 líneas Dart** + **2 693 de tests** (98 casos). Estado
  centralizado en `PlayerController` (testeable **sin** la `.so`). Fases 1B y 2
  cerradas (cola, biblioteca, sesión persistente y DSP audiófilo) y **fase 3 en
  marcha**: paisajes sonoros, detector de BPM, exportador WAV y `.cue` en el
  núcleo, y **toda** la API del motor expuesta a Dart con el DSP persistido en
  la sesión.
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
lib/                        app Flutter                                  6 699 líneas
  core/player_api.dart      contrato PlayerApi (112 miembros) + PlayerSnapshot + AudioSettings
  core/player_controller.dart  estado + bombeo de eventos cada 80 ms
  core/native_player.dart   bindings FFI (única frontera con el núcleo)
  platform/media_session_channel.dart  puente Dart del canal cyberhex/media
  ui/{player_page,eq_sheet,core_error_screen}.dart
  main.dart                 crea motor + controlador (o recibe uno inyectado)
test/                       98 tests Dart                              2 693 líneas
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
| Sintaxis Dart | tree-sitter-dart sobre `lib/` y `test/` | 22/22 sin errores |
| Firmas de `PlayerApi` | comprobador propio: 112 miembros en `NativePlayer` y `FakePlayer` | 112/112 en ambos |
| Tests del núcleo | `cd core && zig build test -Ddecoder=miniaudio` | 31/31 |
| Prueba de humo | `cd core && zig build smoke -Dsmoke-dir=/tmp` | 0 fallos |
| Símbolos del `.so` | `nm -D` | 199 `ch_*`; los 122 que usa el `.dart` presentes |
| Coherencia del canal | grep cruzado Dart↔Kotlin de nombres de método | 2/2 y 7/7 sin huérfanos |
| XML de Android | `ElementTree` sobre `AndroidManifest.xml` | válido; 6 permisos, 1 servicio `mediaPlayback` |
| Llaves/paréntesis Kotlin | escáner propio que ignora strings y comentarios | 3/3 balanceados |
| Layout FFI | `sizeof/offsetof` en C vs `_ChEvent` | 24 B, 0/4/8/16 |
| Integración CMake | harness con CMake 4.4 + Zig 0.17.1 | compila; 2ª pasada no-op |

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
| R16 | DSP sin interfaz todavía | los seis procesadores nuevos se manejan solo por API; la pantalla de ajustes audiófilos es la fase siguiente | `lib/ui/` |
| R17 | Coste del DSP | la cadena entera (9D + ancho + punch + crossfeed + noche) son ~40 operaciones por muestra a 48 kHz; en el Redmi es despreciable y `isIdle()` la salta por completo cuando todo está apagado | `dsp_spatial.zig` |
| R20 | ReplayGain on/off sin getter | el núcleo solo exporta `ch_engine_set_replaygain`; el valor se recuerda en `NativePlayer` (arranca activado, como el motor) y se reenvía al restaurar | `native_player.dart` |
| R21 | Exportar/BPM en isolate | las dos tareas decodifican el archivo entero; un tema largo tarda segundos y ocupa CPU. Van en `Isolate.run`, pero no hay barra de progreso | `native_player.dart` |
| R18 | Paisaje sin mando en la UI | el núcleo ya lo mezcla, pero hasta la fase 3 de UI no hay control; el nivel interno máximo (0.28) evita sustos | `dsp_ambient.zig` |
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
| P1.5 | UI del vúmetro y del espectro (`levels`/`spectrum` ya existen) | Dart |
| P1.6 | UI de ReplayGain por álbum, balance, mono y loop A-B | Dart |

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

## 12. Changelog (38 commits + fusión de `main` desde `eca1490`)

```
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
