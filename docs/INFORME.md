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
- Núcleo (tras fusionar `main`): **6 807 líneas**, **173 funciones FFI**, ABI **3**.
  Decodifica con FFmpeg si está; si no, con miniaudio (WAV/FLAC/MP3/Vorbis).
- App: **2 074 líneas Dart** + **578 de tests**. Estado centralizado en
  `PlayerController` (testeable **sin** la `.so`).
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
core/                       motor nativo (Zig 0.17.1 + C23)          6 807 líneas
  src/root.zig              173 exports FFI, hilo de audio, render, cola, EQ, eventos
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
lib/                        app Flutter                                  2 074 líneas
  core/player_api.dart      contrato PlayerApi + PlayerSnapshot + PlayerEvent
  core/player_controller.dart  estado + bombeo de eventos cada 80 ms
  core/native_player.dart   bindings FFI (única frontera con el núcleo)
  platform/media_session_channel.dart  puente Dart del canal cyberhex/media
  ui/{player_page,eq_sheet,core_error_screen}.dart
  main.dart                 crea motor + controlador (o recibe uno inyectado)
test/                       20 tests Dart                                578 líneas
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

---

## 5. Capa Dart

| Archivo | Responsabilidad |
|---|---|
| `player_api.dart` | `PlayerApi` (contrato), `PlayerSnapshot` (inmutable, `==`), `PlayerEvent` |
| `player_controller.dart` | `ChangeNotifier`; drena eventos, refresca snapshot, `ValueNotifier<double> position` |
| `native_player.dart` | Implementa `PlayerApi` sobre FFI; **todo símbolo opcional con `providesSymbol`** (una `.so` vieja sigue cargando) |
| `platform/media_session_channel.dart` | Puente con Android: `updateMetadata`/`updateState` (throttle 1 s) hacia Kotlin y comandos (`play`, `pause`, `toggle`, `next`, `previous`, `seek`, `setVolume`, `duck`) hacia el controlador |
| `ui/player_page.dart` | Consume `ListenableBuilder` + `ValueListenableBuilder`; teclado (espacio) |
| `ui/eq_sheet.dart` | 36 bandas contra el controlador |

`PlayerApi` incluye `next()`/`previous()`; `NativePlayer` los bindea con
`providesSymbol` y quedan en `null` (no-op) si la `.so` es anterior a la ABI que
los exporta.

Tests: 9 del controlador + 7 del canal de medios + 3 de widget + 1 de tema, todos
con `FakePlayer`/canal simulado (sin FFI, sin teléfono).

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

> **Limitación conocida (P0.4):** el `FlutterEngine` pertenece a `MainActivity`;
> si se quita la tarea de Recientes, la actividad —y con ella el motor de
> audio— se destruye aunque el servicio siga vivo. Para que la música sobreviva
> a Recientes hace falta un `FlutterEngine` cacheado en una clase `Application`
> (un cuarto archivo Kotlin, fuera del ALCANCE de este pedido).

---

## 7. Verificación

### 7.1 Lo que el agente **sí** puede ejecutar aquí

| Qué | Comando | Resultado último |
|---|---|---|
| Tests Zig (13) | `cd core && zig build test -Ddecoder=miniaudio` | 13/13 |
| `.so` nativa | `zig build-lib … -O ReleaseFast` | 4,0 MB, 97 símbolos |
| `.so` aarch64 | `zig build-lib … -target aarch64-linux-gnu -mcpu cortex_a73` | 3,9 MB |
| Humo con audio real | `cd core && zig build smoke` | 0 fallos (RMS 0.4997, pausa 0.4000→0.4000, loop 10/10) |
| Sintaxis C | `gcc -fsyntax-only -std=c2x -Wall -Wextra` | limpio |
| Sintaxis Dart | tree-sitter-dart sobre `lib/` y `test/` | 14/14 sin errores |
| Firmas de `PlayerApi` | comprobador propio: 25 miembros en `NativePlayer` y `FakePlayer` | 25/25 en ambos |
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
| R7 | Sin dither a S16 | conversión final sin dithering (inaudible, pero es deuda) | `audio.c` |
| R8 | `ffmpeg.tar.xz` en git | ~decenas de MB; decisión de empaquetado pendiente (A4) | `core/third_party/` |
| R9 | Sin CI | ninguna acción de GitHub valida nada | `.github/` (no existe) |
| R10 | Android antes de P0.1 | ~~sin MediaSession ni servicio~~ **resuelto** en P0.1 (notificación, bloqueo, foco, auriculares) | `android/` |
| R11 | Recientes mata el motor | el `FlutterEngine` vive en la actividad: quitar la tarea corta el audio aunque el servicio siga | `MainActivity.kt` → P0.4 |
| R12 | Icono de la notificación | `android.R.drawable.ic_media_play` como *small icon* (monocromo del sistema); falta un vector propio | `MediaSessionService.kt` |
| R13 | FGS desde segundo plano | Android 12+ prohíbe arrancar un FGS en background salvo excepciones; aquí se arranca al pulsar play con la app delante | `MediaBridge.ensureServiceStarted` |

---

## 10. Backlog priorizado

### P0 — completar la app de móvil

| # | Tarea | Alcance | Bloqueos |
|---|---|---|---|
| P0.1 | ~~`MediaSession` + servicio en primer plano~~ **HECHO** (turno 9): servicio, foco, notificación y bloqueo, sin dependencias nuevas | Kotlin + manifest + Dart | falta compilar y probar en el teléfono |
| P0.4 | `FlutterEngine` cacheado en una `Application` propia para que la música sobreviva a "quitar de Recientes" | Kotlin (archivo nuevo) + manifest | requiere otra clase y cambiar el `android:name` del `<application>` |
| P0.5 | Bindear en Dart la API que trajo `main`: R128 (`ch_engine_analyze_loudness`), picos de forma de onda, ganancia manual en dB, crossfeed, hojas CUE y guardado de carátula | Dart | círculo de 1 turno; el núcleo ya está fusionado y verificado |
| P0.2 | Pantallas de **biblioteca** (escaneo con `ch_library_*`) y **cola** (reordenar, quitar, saltar) | Dart | no verificable aquí |
| P0.3 | Abrir archivos desde el gestor: `Intent.ACTION_VIEW` (Android) y `%U` en `.desktop` | Kotlin/Dart + runner C | requiere pasar argv a Dart |

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

## 12. Changelog (29 commits + fusión de `main` desde `eca1490`)

```
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
