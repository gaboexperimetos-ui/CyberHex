# Bitácora de ejecución

Registro **append-only**: una entrada por turno, la más nueva arriba. Cada
entrada dice qué se pidió, qué se hizo, cómo se verificó, qué commits salieron y
qué quedó abierto. El estado consolidado está en [`INFORME.md`](INFORME.md).

Formato:

```
## AAAA-MM-DD · turno N · <título>
- PEDIDO:
- HECHO:
- VERIFICADO:
- NO VERIFICABLE AQUÍ:
- COMMITS:
- ABIERTO / RIESGOS:
```

---

## 2026-11-21 · turno 11 · ABI completo, absorciones y primera interfaz

- **PEDIDO:** cuatro pasos: (1) comprobar que local y GitHub son iguales,
  (2) añadir todas las funciones posibles, (3) investigar reproductores
  similares y absorber lo útil, (4) empezar la interfaz.
- **HECHO:**
  - Local y `origin/main` ya coincidían en `64b929f`, sin cambios pendientes.
  - Dos bugs reales del controlador: el seek no se acotaba y `pump()`
    sobrescribía con la posición vieja el 0 del evento `TRACK`. Más 5 avisos
    del analizador. `flutter analyze` pasó de 5 avisos a 0.
  - 99 símbolos bindeados en cuatro tandas: cola y modos (28), metadatos,
    letras y carátula (11), medición y DSP (26), biblioteca/marcadores/CUE/
    salida/análisis (34). `PlayerApi` gana miembros con implementación por
    defecto para no romper dobles ni `.so` antiguas.
  - Motor: `ch_engine_queue_item` para que la UI pueda dibujar la cola (180
    exports). `Anterior` reinicia la pista tras 3 s, como Spotify/Strawberry.
  - `docs/REFERENCIAS.md`: fooyin, Strawberry, Tauon, Amberol, Musicolet, con
    tabla de qué se absorbe y qué se descarta (red, CD, conversión).
  - Interfaz: hojas de **cola**, **letra** y **ajustes** (velocidad, tono,
    crossfade, preamp, mono, limitador, salida, temporizador) y visualizador de
    espectro alimentado por `ch_engine_spectrum`.
- **VERIFICADO:** `flutter analyze` sin issues; `flutter test` 31/31;
  `zig build` y `zig build test -Ddecoder=miniaudio` OK; los 99 símbolos
  nuevos comprobados con `nm -D` sobre la `.so` real; 180 exports `ch_*`.
- **NO VERIFICABLE AQUÍ:** reproducción real a través de los bindings nuevos
  (no hay audio de prueba versionado) ni la app en el teléfono.
- **COMMITS:** `a4f6681`, `312237e`, `2de32e8`, `8587acf`, `d27e062`,
  `6220fe9` y el de la interfaz.
- **ABIERTO:** biblioteca con búsqueda, forma de onda, restaurar sesión al
  arrancar, MPRIS (Linux), R11 (`FlutterEngine` cacheado), A4 (FFmpeg en git).

---

## 2026-11-21 · turno 10 · Fusión de `main` y primer merge a `main`

- **PEDIDO:** "mergea todo". Antes hubo que integrar los dos commits que `main`
  ganó mientras trabajábamos (`core: A-B loop, crossfeed, mono/balance,
  medidores, estado persistente y hojas CUE; Android portable ARMv8-A` y
  `core: sonoridad EBU R128, picos, ganancia manual y guardar carátula`).
- **CONFLICTOS (3) y resolución:**
  - `core/build.zig`: la versión de `main` duplicaba la selección de
    decodificador ya refactorizada aquí. Se conserva la de la rama
    (`-Ddecoder=auto|ffmpeg|miniaudio`, `haveFfmpeg*`, mensajes claros) y se
    añaden las tres fuentes C nuevas de `main` (`cue.c`, `fileio.c`,
    `analysis.c`).
  - `core/src/root.zig`: fusión automática dejó **duplicados** que Zig no
    acepta (`balance_bits`, `ab_start`, `ab_end`, `ch_engine_set_balance`,
    `ch_engine_balance`) y un bucle `render` con dos versiones del mismo tramo.
    Se unificó: un solo `balance_bits`, un solo par A-B, un solo export de
    balance; `mono` desaparece como campo y **`ch_engine_set_mono` ahora escribe
    `chan_mode`** (0 estéreo, 1 mono, 2 intercambiados), así que la API vieja
    sigue funcionando y hay un solo mando de canales. El bucle quedó:
    fade con `fade_coeff` (respeta el fundido de pausa de ~50 ms) → modo de
    canales → **crossfeed Bauer** de `main` → balance por canal → limitador →
    medidores.
  - `core/API.md`: una sola cabecera
    `### Android: arm64-v8a portable (objetivo: Redmi Note 13, Snapdragon 685)`,
    conservando la sección de `-Ddecoder` y `zig build smoke`.
- **VERIFICADO AQUÍ:** `zig build test -Ddecoder=miniaudio` → *test success*
  (13 tests, ahora compilando también `cue.c`, `fileio.c` y `analysis.c`);
  `zig build -Drelease=true` → `.so` de 4,3 MB con **173 exports `ch_*`**;
  `gcc -fsyntax-only -std=c2x -Wall -Wextra` limpio en las 9 fuentes C;
  comprobador de símbolos: los **40** que pide `native_player.dart` están en la
  `.so` (ninguno queda sin `providesSymbol`); ABI sigue en **3**.
- **NO VERIFICABLE AQUÍ:** nada nuevo; sigue sin haber SDK de Flutter ni JDK.
- **COMMITS:** merge `main` → `arena/3351fdb0-cyberhex`, y el merge de la rama a
  `main` por PR.
- **ABIERTO / RIESGOS:** R11 (Recientes mata el motor), R12 (icono de
  notificación), R13 (FGS desde background). La nueva API de `main` (R128, CUE,
  picos) **no está bindeada en Dart todavía**: es P0.5.

---

## 2026-11-21 · turno 9 · P0.1: next/previous, canal de medios y servicio Kotlin

- **PEDIDO:** tres pedidos estrictos, un commit reversible cada uno: (1) exponer
  `next()`/`previous()` desde el FFI hasta `PlayerApi`; (2) puente Dart del canal
  `cyberhex/media` enganchado en `main.dart` solo en Android; (3) servicio en
  primer plano con `MediaSession` en Kotlin. `RIESGO ACEPTABLE`: no, no, **sí**.
- **HECHO (P1, commit `f43f040`):** `_Bindings` enlaza `ch_engine_next` y
  `ch_engine_previous` con `providesSymbol` (si la `.so` no los exporta quedan en
  `null` y son no-op); `PlayerApi` declara `next()`/`previous()`; `NativePlayer`,
  `PlayerController` (con `_refresh()`) y `FakePlayer` los implementan; 2 tests
  nuevos (llegan al motor / se ignoran tras `dispose`). No toca `core/`,
  `android/`, `pubspec.yaml` ni `lib/ui/`.
- **HECHO (P2, commit `fdf07ed`):** `lib/platform/media_session_channel.dart`
  (247 líneas): escucha el controlador y su `position`; `updateMetadata` al
  cambiar pista/etiquetas/duración/carátula; `updateState` con throttle por
  **segundo entero** de posición; comandos entrantes `play`, `pause`, `toggle`,
  `next`, `previous`, `seek` (recortado a `[0, duración]`), `setVolume`, `duck`
  (25 % del volumen guardado, restaurado exacto; `duck(true)` repetido no pierde
  el original); `MissingPluginException` ignorado; `main.dart` lo engancha bajo
  `Platform.isAndroid` y lo suelta en `dispose()` antes del controlador. 7 tests
  con `TestDefaultBinaryMessengerBinding`. Sin paquetes nuevos.
- **HECHO (P3, este commit):** `MediaSessionService.kt` (566 líneas) y
  `MediaBridge.kt` (205), `MainActivity.kt` (52), `AndroidManifest.xml`.
  FGS `mediaPlayback` (`START_NOT_STICKY`, `stopWithTask="false"`); pausa →
  `STOP_FOREGROUND_DETACH` (`stopForeground(false)` < API 24) con
  `setOngoing(false)` + `deleteIntent` para cerrar deslizando; `MediaMetadata`
  con duración y carátula (≤1024 px); `PlaybackState` con play/pause/play-pause/
  skip next/skip previous/seek/stop; receptor dinámico de
  `ACTION_AUDIO_BECOMING_NOISY`; audio focus completo (LOSS→pausa,
  LOSS_TRANSIENT→pausa+reanuda en GAIN, CAN_DUCK→`duck(true)`/`duck(false)`);
  `FLAG_IMMUTABLE` desde API 23; ramas por SDK en 26/29/33; `POST_NOTIFICATIONS`
  en runtime desde `onPostResume`. `MediaBridge` encola hasta 16 comandos si el
  canal no está adjunto y los drena en `configureFlutterEngine`.
- **VERIFICADO:** tree-sitter-dart 14/14 sin errores; comprobador de firmas
  (25/25 miembros en `NativePlayer` y `FakePlayer`); grep cruzado del canal
  (Dart acepta los 7 comandos que Kotlin emite; Kotlin acepta los 2 métodos que
  Dart envía; mismo nombre de canal); `ElementTree` valida el manifest (6
  permisos, servicio `mediaPlayback`); escáner de llaves/paréntesis en los 3
  `.kt` (balanceados). Sin `core/`, `build.gradle.kts`, `settings.gradle.kts` ni
  `libs.versions.toml` en el diff.
- **NO VERIFICABLE AQUÍ:** `flutter analyze`, `flutter test`, `kotlinc`, Gradle y
  cualquier prueba en el teléfono (no hay SDK ni JDK). El Kotlin se entrega
  "escrito, no compilado".
- **COMMITS:** `f43f040` (P1), `fdf07ed` (P2), este (P3).
- **ABIERTO / RIESGOS:** R11 (quitar la tarea de Recientes destruye el
  `FlutterEngine` y con él el audio → P0.4), R12 (falta un *small icon*
  monocromo propio), R13 (Android 12+ prohíbe arrancar el FGS desde background:
  hoy se arranca al pulsar play con la app delante).

---

## 2026-11-21 · turno 8 · Informe para el arquitecto

- **PEDIDO:** resumen del trabajo y traspaso a un arquitecto externo; todo lo
  que se haga debe quedar documentado en `.md` para control y visión.
- **HECHO:** creado `docs/INFORME.md` (estado real, contratos, riesgos, backlog
  P0–P3, entorno del agente, protocolo de pedidos) y esta bitácora. Sin cambios
  de código.
- **VERIFICADO:** datos del informe medidos, no estimados: 26 commits, 5 691
  líneas de núcleo, 1 762 de app, 327 de tests, 97 exports FFI, ABI 3, 13 tests
  Zig, 11 Dart.
- **NO VERIFICABLE AQUÍ:** —
- **COMMITS:** `docs: informe maestro y bitácora para el arquitecto`
- **ABIERTO:** ningún pedido del arquitecto todavía. Siguiente candidato P0:
  MediaSession + servicio en primer plano (Android) o biblioteca/cola (Dart).

---

## 2026-11-21 · turno 7 · Escritorio Arch + icono y permisos en Android

- **PEDIDO:** "app de escritorio para Arch y app completa para Android", sin web.
- **HECHO:**
  - `linux/CMakeLists.txt`: vigila `include/`, `vendor/`, `build.zig.zon`;
    `-DCYBERHEX_DECODER`; `touch` tras compilar para que el `--prefix` de Zig no
    dispare recompilaciones.
  - `packaging/linux/`: `PKGBUILD`, `cyberhex.desktop`, `cyberhex.svg`.
  - Ventana `CyberHex` 1000×780.
  - Android: icono adaptativo propio (hexágono), permisos `READ_MEDIA_AUDIO`,
    `READ_EXTERNAL_STORAGE` ≤12 y `WAKE_LOCK`; los de servicio en primer plano
    quedan comentados hasta que exista el servicio.
- **VERIFICADO:** harness de CMake 4.4 + Zig 0.17.1 sobre el bloque real
  (compila, 2ª pasada no-op, `touch build.zig` recompila). XMLs del icono
  válidos. `.so` con los símbolos nuevos.
- **NO VERIFICABLE AQUÍ:** `flutter build linux`, `flutter build apk`, `makepkg`.
- **COMMITS:** `276868c`, `c1ff6af`, `a9767fd`, `a3e5f31`, `c2755c3`
- **ABIERTO:** R10 (la música se corta al salir de la app), R2 (sin FFmpeg en
  Android no hay `.m4a`), abrir archivos desde el gestor.

---

## 2026-11-21 · turno 6 · Núcleo multiplataforma: decoder auto y prueba de humo

- **PEDIDO:** "enfoquémonos al 100 % en el core, funciones y todo" con dos
  versiones (PC y Android).
- **HECHO:**
  - `build.zig`: `-Ddecoder=auto|ffmpeg|miniaudio`; en PC detecta FFmpeg con
    `pkg-config`, en Android comprueba `third_party/ffmpeg-android/<abi>/lib`;
    si falta, avisa y compila con miniaudio. `-Ddecoder=ffmpeg` falla con
    mensaje claro (paso `addFail`, sin traza de pila).
  - `core/tests/smoke.c` + `zig build smoke`: sintetiza un WAV, reproduce y
    comprueba niveles, pausa, loop A-B, eventos, preamp, ReplayGain, balance y
    modo de canales. Portable a Android (`nanosleep`, sin libm).
  - Núcleo: `ch_engine_set_balance`, `ch_engine_set_channel_mode`,
    `ch_engine_abi_version` (ABI 3), versión 0.8.0.
  - `native_player.dart`: bindings de las cinco funciones nuevas.
- **VERIFICADO:** `zig build test` 13/13; `zig build smoke` **0 fallos**;
  build nativo y cruzado aarch64; `-Ddecoder=ffmpeg` falla como debe.
- **NO VERIFICABLE AQUÍ:** nada nuevo de Dart.
- **COMMITS:** `6a5e44a`, `77dc231`, `f5f5f46`, `1bfe206`
- **ABIERTO:** latencia/búfer configurable, crossfeed, dither, CUE.

---

## 2026-11-21 · turno 5 · Verificación real y corrección de banderas

- **PEDIDO:** "¿no podés hacer esto?" (`flutter analyze && flutter test`,
  `zig build`).
- **HECHO:** intento de instalar Dart/Flutter (imposible: solo hay salida a
  github/npm/pypi y el SDK vive en `storage.googleapis.com`). Sustitutos:
  tree-sitter-dart sobre los 12 archivos, verificación del layout de `ch_event`
  contra el header, revisión de imports y constantes de tema, cross-compile
  aarch64, y corrección de la documentación de banderas de Zig 0.17.
- **VERIFICADO:** 12/12 archivos Dart sin errores de sintaxis; `sizeof(ch_event)`
  = 24 B con offsets 0/4/8/16 = `_ChEvent`; `--release=*` y `-Drelease=*`
  válidos, `-Doptimize=*` **no**.
- **NO VERIFICABLE AQUÍ:** tipos de Dart (necesita el analizador real).
- **COMMITS:** `1dc1399` (y correcciones de docs en turnos siguientes)
- **ABIERTO:** R1 (nadie ha pasado `flutter analyze`).

---

## 2026-11-21 · turno 4 · Motor de audio: vúmetro, preamp, fade, A-B

- **PEDIDO:** "añadir al motor de audio" (segunda mitad de la tanda elegida).
- **HECHO:** `ch_engine_levels` (RMS/pico por canal, caída 200 ms, a cero al
  pausar), `ch_engine_set_eq_preamp`, `ch_engine_set_replaygain_mode` (+R128),
  `ch_engine_set_pause_fade`, `ch_engine_set_loop/loop_start/loop_end`,
  `ch_engine_skipped_tracks`; `openNextAuto` salta pistas ilegibles. La posición
  cuenta el audio del fundido (**arregla B6**).
- **VERIFICADO:** `zig test` 13/13; `.so` con los 11 símbolos; humo en C: RMS
  0,3514 y pico 0,4984 para un tono de 0,5, pausa con delta `0,00000`, 10/10
  muestras dentro del tramo A-B.
- **NO VERIFICABLE AQUÍ:** la UI del vúmetro (no existe).
- **COMMITS:** `d82e41b`, `1aa636d`, `e2b8308`
- **ABIERTO:** que A-B se cancele al cambiar de pista (documentado), R4.

---

## 2026-11-21 · turno 3 · Motor de estado en Dart

- **PEDIDO:** "añadir al motor de estado" (primera mitad de la tanda elegida).
- **HECHO:** `PlayerApi`, `PlayerSnapshot`, `PlayerEvent`; `PlayerController`
  (bombeo 80 ms, `ValueNotifier` de posición, snapshot con `==`); `NativePlayer`
  implementa el contrato y por fin consume `ch_engine_poll_event`; `main.dart`
  crea el motor; `PlayerPage` pasa a `ListenableBuilder`; `FakePlayer` + 10
  tests Dart sin la `.so`.
- **VERIFICADO:** sintaxis (tree-sitter) y revisión manual; el resto queda del
  lado del usuario.
- **NO VERIFICABLE AQUÍ:** `flutter test`, `flutter analyze`.
- **COMMITS:** `46772ef`, `e0767b3`, `1dc1399`
- **ABIERTO:** R1.

---

## 2026-11-21 · turnos 1–2 · Auditoría y dos tandas de correcciones

- **PEDIDO:** "analiza esto", "¿qué podés mejorar?", ejecutar fases 1 y 2.
- **HECHO:** `ANALISIS.md` con hallazgos A/B/C; EQ de 36 bandas real (antes 10
  con etiquetas inventadas) y `set_band_gain` que conserva el resto; metadatos y
  carátula en la UI; carga en isolate con spinner; tarea de Gradle incremental;
  cola sin vaciar (`play_index`/`load_add`); fuera los spinlocks del callback;
  reinicio del EQ por banda; biblioteca a prueba de ciclos y O(n²); la pantalla
  deja de reconstruirse cada 250 ms; README real y LICENSE MIT.
- **VERIFICADO:** `gcc -fsyntax-only` de los 5 `.c`; `zig test` 6→12 tests; humo
  C con WAV; ASan/UBSan sobre la biblioteca.
- **NO VERIFICABLE AQUÍ:** nada de Flutter.
- **COMMITS:** `2a330cd`, `cb70420`, `db40214`, `2f55173`, `b519832`, `cf08ef1`,
  `3db1560`, `ba04bf0`, `ced0785`, `0962ae3`, `6e19f24`
- **ABIERTO:** A4 (FFmpeg en git), B8 (Android en segundo plano), B9 ampliado.
