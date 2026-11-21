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
