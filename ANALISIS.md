# Análisis de CyberHex

Fecha: 2026-11-21 · Rama: `arena/3351fdb0-cyberhex` · Base: `eca1490`

## Resumen ejecutivo

CyberHex es un reproductor de música con una arquitectura poco común y bien
planteada: **motor nativo en Zig 0.17 + C23 con API C estable**, hilo de audio
separado, decodificación en streaming con FFmpeg, y **UI Flutter por FFI**.
El núcleo (`core/`) está claramente por delante de la app.

- **Motor**: sólido, con API amplia (78 funciones exportadas), seqlock para el
  EQ, atómicos para play/pause/seek, ring buffer de 4 s, gapless, crossfade,
  ReplayGain, limitador, estiramiento de tiempo/tono, espectro FFT, letras LRC,
  biblioteca incremental, marcadores persistentes. Compila limpio.
- **App**: es hoy un **demo funcional** (abrir archivo, play/pausa, seek,
  volumen, un EQ de 10 sliders). Usa **14 de las 78** funciones del núcleo.
  No muestra metadatos ni carátula, no tiene cola, ni letras, ni visualizador,
  aunque el motor ya lo soporta todo.
- **Repositorio**: el problema más serio no es el código, es el **peso**:
  11.026 archivos de FFmpeg versionados (113 MB de árbol, ~34 MB de pack).
  El README sigue siendo el del template de Flutter y no hay LICENSE.
- **Build Android**: frágil. Un `Exec` en `preBuild` ejecuta el script del
  núcleo **en cada compilación** y exige Zig + NDK + FFmpeg estático ya
  compilado; un clon limpio no puede generar el APK.

Veredicto: **excelente base técnica, producto a medio camino y repo
desordenado**. Nada crítico de arquitectura; sí bastantes detalles de calidad,
uno o dos bugs reales y dos decisiones de empaquetado que conviene corregir ya.

### Estado de las correcciones

Ya aplicadas en esta rama (cada una en su commit):

| Hallazgo | Estado | Commit |
|---|---|---|
| A1 EQ de 10 bandas con etiquetas falsas | ✅ 36 bandas reales, etiquetas del núcleo | `app: metadatos, carátula y ecualizador…` |
| A2 `set_band_gain` borraba las demás bandas | ✅ guarda las ganancias vigentes | `core: EQ de 36 bandas consultable…` |
| A5 Gradle recompilaba siempre / no se podía saltar | ✅ inputs/outputs + `-PskipCoreBuild` | `build(android): tarea del núcleo…` |
| A6 README de plantilla / sin LICENSE | ✅ README real + MIT | `docs: README real, LICENSE MIT…` |
| B1 sin metadatos ni carátula | ✅ title/artist/album + portada | `app: metadatos, carátula…` |
| B2 carga bloqueando el hilo de UI | ✅ `loadAsync` en isolate + spinner | `app: metadatos, carátula…` |
| C1 `-Drelease=true` inexistente | ✅ corregido en `core/API.md` | `core: EQ de 36 bandas…` |

Siguen pendientes: A3 (load vacía la cola), A4 (FFmpeg versionado), B3 (rebuild
cada 250 ms), B4/B5 (EQ y spinlocks en el hilo de audio), B6 (deriva en pausa),
B7 (symlinks en la biblioteca), B8 (background en Android) y B9 (tests).

---

## 1. Mapa del proyecto

| Componente | Archivos | Líneas aprox. |
|---|---|---|
| UI Flutter (Dart) | `lib/main.dart`, `theme.dart`, `ui/player_page.dart`, `ui/eq_sheet.dart`, `core/native_player.dart` | ~955 |
| Motor (Zig) | `core/src/root.zig` (2309), `stretch.zig` (407), `eq.zig` (165), `fft.zig` (80) | ~2961 |
| Motor (C23) | `audio.c`, `decode_ffmpeg.c`, `decode_miniaudio.c`, `library.c`, `lyrics.c`, `markers.c`, `playlist.c` + headers | ~1930 |
| Empaquetado | `core/build.zig`, `build_android.sh`, `build_ffmpeg_android.sh`, Gradle | — |
| Pruebas | 6 tests Zig (EQ/FFT/stretch) + 1 test de tema en Dart | — |
| Vendor | `core/vendor` (miniaudio + dr_flac/dr_mp3/dr_wav, 5 MB) y `core/third_party/ffmpeg-src` (113 MB, **versionado**) | — |

Flujo: Dart → `NativePlayer` (FFI) → `libcyberhex_core.so` → `ch_engine_*` →
ring buffer ← hilo decodificador (FFmpeg/miniaudio) → callback de miniaudio.

## 2. Lo que está bien (y conviene no tocar)

1. **Frontera FFI limpia**: API C plana, handles opacos, códigos de error
   numéricos + `last_error`. Es la forma correcta de envolver un motor nativo.
2. **Nada de bloqueos en `play/pause/seek`**: solo atómicos; el trabajo pesado
   vive en el hilo decodificador. `render()` nunca asigna memoria.
3. **Seqlock del EQ** (`eq.zig`): el hilo de audio lee una configuración
   consistente sin bloquear al escritor. Buena técnica.
4. **Streaming real**: buffer de 4 s, nunca se carga la canción entera.
5. **Cobertura de formatos** vía FFmpeg estático, y fallback a miniaudio
   (`-Dandroid-ffmpeg=false`) para no quedar atado a una toolchain.
6. **Documentación del núcleo** (`core/API.md`): extensa y honesta, incluso
   lista lo que falta.
7. **C compila sin un solo warning** con `gcc -std=c2x -Wall -Wextra -Wshadow`
   (`playlist.c`, `lyrics.c`, `library.c`, `markers.c`, `audio.c`). El código C
   es ordenado, con `error` centralizado y escapes bien resueltos en marcadores.
8. **Privacidad**: sin permisos de red, FFmpeg con `--disable-network`.

## 3. Hallazgos por severidad

### 🔴 Alta

**A1. El ecualizador de la UI miente y no llega a los agudos.**
El núcleo expone **36 bandas logarítmicas de 20 Hz a 20 kHz, ±18 dB**
(`core/src/eq.zig`, `BAND_COUNT = 36`, `FREQS`). La hoja de EQ muestra **10
sliders** (`lib/ui/eq_sheet.dart:16`) con etiquetas de un EQ de 1/3 de octava
(31 Hz … 16 kHz) y el texto «Rango ±12 dB · 10 bandas» (línea 60).

Como el slider `i` controla la banda `i` real:

| Slider | Etiqueta mostrada | Frecuencia real |
|---|---|---|
| 1 | 31 Hz | 20 Hz |
| 2 | 62 Hz | 24.4 Hz |
| … | … | … |
| 10 | **16k** | **118 Hz** |

Es decir: el usuario cree estar realzando 16 kHz y en realidad mueve 118 Hz, y
**todo el espectro de 118 Hz a 20 kHz es inalcanzable**. Es el bug de producto
más visible.
*Arreglo*: generar las etiquetas desde el núcleo (p. ej. exportar
`ch_engine_eq_band_freq(i)`), dibujar las 36 bandas (scroll horizontal) y
corregir el texto a ±18 dB.

**A2. `ch_engine_set_band_gain` borra las otras 35 bandas.**
`core/src/root.zig:2024`: construye un array `@splat(0)` y solo escribe la banda
pedida, así que cada llamada deja el resto del EQ en 0. La UI no lo usa (usa
`set_eq_gains` con el array completo), pero la API pública sí está rota.
*Arreglo*: guardar el último array de ganancias en el `Engine` y hacer
read-modify-write.

**A3. `ch_engine_load` vacía la cola.**
`root.zig:1457` hace `clearPlaylist()` y deja una sola pista. No existe una
función «reemplazar la pista actual conservando la cola», así que cualquier
mejora de UI (abrir otro archivo sin perder la lista) choca con la API.
*Arreglo*: añadir `ch_engine_load_keep_queue()` o un flag.

**A4. El repositorio pesa por FFmpeg.**
`git ls-files core/third_party | wc -l` → **11.026 archivos**, 113 MB de árbol,
~34 MB comprimidos en el pack. Además `core/third_party/ffmpeg.tar.xz` (12 MB)
está en disco pero **ignorado** por `.gitignore`, mientras que su contenido sí
está versionado: lo peor de ambos mundos.
*Arreglo*: borrar `ffmpeg-src` del índice y dejar que
`build_ffmpeg_android.sh` lo descargue (ya sabe hacerlo, con
`FFMPEG_VERSION`/tarball) o moverlo a submódulo. Ganancia inmediata: el clon
pasa de ~166 MB a ~5 MB + vendor.

**A5. `flutter build apk` no funciona desde un clon limpio.**
`android/app/build.gradle.kts` registra:

```kotlin
val buildCyberHexCore by tasks.registering(Exec::class) {
    workingDir = rootProject.file("../core")
    commandLine("./build_android.sh")
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(buildCyberHexCore) }
```

Problemas: (a) exige Zig en PATH, NDK y `third_party/ffmpeg-android/arm64-v8a`
(no versionado), y si falta **falla el build entero**; (b) no declara `@Inputs`
ni `@Outputs`, así que se recompila siempre (y rompe la configuración
incremental); (c) no se puede saltar sin editar el Gradle. Además no hay CI
(`.github/` no existe) ni `LICENSE`.
*Arreglo*: declarar inputs/outputs, permitir `-Pskip-core-build=true`, y
versionar los `.so` solo si se quiere un build «listo para usar».

**A6. README de plantilla.**
`README.md` sigue diciendo «A new Flutter project». Toda la documentación real
está en `core/API.md`. Falta un README que explique arquitectura, cómo compilar
el núcleo, y **falta licencia** (el proyecto se llama «privado» en `pubspec`).

### 🟠 Media

**B1. La app usa 14 de 78 funciones.** Sin bindings para `title/artist/album`,
`cover*`, cola (`queue_*`), `next/previous`, `repeat`, `shuffle`, `crossfade`,
`speed/pitch`, `spectrum`, `lyrics`, `library`, `markers`, `sleep_timer`,
`replaygain`, `limiter`, `output_device`, `poll_event`. La pantalla muestra el
**nombre del archivo** (`_fileName`) en vez del tag `title`, y una línea fija
«motor nativo 48 kHz» (`player_page.dart:354`). El motor ya trae carátula,
letras y visualizador: es la mayor oportunidad de producto del proyecto.

**B2. Carga sincrónica en el hilo de UI.** `_openFile()` → `player.load()` →
`ch_engine_load()` corre en el isolate de UI y hace: `waitIdle` (hasta 2 s de
espera activa), apertura del decoder, copia de hasta 4 carátulas a memoria,
parseo del `.lrc` y `flushRing`. Con un FLAC en red/almacenamiento lento se
congela la UI sin spinner ni cancelación. *Arreglo*: `Isolate.run` +
estado de carga.

**B3. Reconstrucción completa cada 250 ms.** `_tick()` llama `setState(() {})`
(`player_page.dart:66`) y `build()` vuelve a consultar FFI (`isPlaying`,
`position`, `duration`) varias veces por widget. *Arreglo*: `ValueListenable`
para posición y estado, `AnimatedBuilder` para el disco, y `RepaintBoundary`.

**B4. Ecualizador: mucho trabajo por cada píxel de arrastre.**
`setBand` (`native_player.dart:125`) reenvía **las 36 ganancias** en cada
`onChanged`, el núcleo recalcula 36 biquads (`pow/sin/cos`) y **reinicia el
estado de los filtros** (`generation` → `resetState()` en `eq.zig`). Eso puede
producir zipper/clicks al arrastrar. *Arreglo*: usar `set_band_gain` (una vez
arreglado A2), no resetear todo el estado, y limitar a ~30 envíos/s.

**B5. Spinlocks dentro del callback de audio (RT).**
`render()` toma `buf_lock` (contador de underflows), `sleep_lock`,
`sp_lock` y, vía `pushEvent`, `ev_lock`. Un spinlock tomado por el hilo de UI
puede hacer que el hilo de audio gire varios ms → glitch. Peor: `snapshot()` del
EQ hace **busy-wait sin ceder** si el escritor queda preemptado entre las dos
escrituras del seqlock (`eq.zig:90`). *Arreglo*: cola SPSC lock-free para
eventos, contadores atómicos sueltos, y en el seqlock usar `tryLock`/lectura
optimista con fallback a la configuración anterior.

**B6. Pausa: se pierden ~50 ms de audio ya decodificado.**
`render()` sigue consumiendo del ring mientras `fade_gain` baja a 0 (≈50 ms),
pero `played` **no** avanza porque `playing` es false (`root.zig:1055`).
Al reanudar, el audio arranca ~50 ms más adelante que la posición mostrada; se
acumula con cada pausa. *Arreglo*: no avanzar el cursor de lectura en pausa, o
contabilizar esos frames en `played`.

**B7. `library.c`: escaneo peligroso.**
`scan_dir` usa `stat` (sigue symlinks) y **recursión sin límite ni conjunto de
visitados** → un symlink circular cuelga o revienta la pila. Además
`find_track` es lineal → escaneo O(n²) en la biblioteca, y `snprintf(sub, 4096)`
trunca rutas largas en silencio. *Arreglo*: `lstat` + `(dev,ino)` visitados +
profundidad máxima + hash de rutas.

**B8. Android sin reproducción en segundo plano.**
No hay `Service` en primer plano ni `PARTIAL_WAKE_LOCK` en el manifest, y no se
pide audio focus. Con la pantalla apagada o la app en background el sistema
puede suspender la CPU y cortar el audio; tampoco se silencia ante una llamada.
Para un reproductor esto es casi un requisito.

**B9. Cobertura de pruebas muy baja.** 6 tests unitarios del núcleo (EQ, FFT,
stretch) y 1 test de tema. Nada cubre: ciclo de vida del motor, cola/shuffle/
repeat, gapless, seek, marcadores, biblioteca, ni la capa FFI. Un test de
integración que abra un WAV generado y compruebe posición/duración/eventos
daría muchísimo valor por poco esfuerzo.

### 🟡 Baja

- **C1. Documentación desincronizada**: `API.md` dice `zig build -Drelease=true`
  (no existe; es `-Doptimize=ReleaseFast`, y de hecho ya es el default) y
  `-O3 -ffast-math` (en `build.zig` los archivos C usan `-O2`, solo el script
  Android usa `-O3`). También hay un `\u00fa` literal en el comentario de
  `cyberhex_core.h` («b\u00fafer»).
- **C2. `material_ui: ^1.1.0`** (`1.11.1` en el lock): la app importa
  `package:material_ui/material_ui.dart` en vez de `package:flutter/material.dart`.
  Es una dependencia de terceros para algo que ya viene en el SDK; añade
  superficie de suministro y confusión.
- **C3. Solo `arm64-v8a` en `abiFilters`**: imposible probar en emulador x86_64
  ni en dispositivos de 32 bits. El script ya soporta más ABI; conviene una
  variante `debug` con varios ABI.
- **C4. `minSdk = flutter.minSdkVersion`** vs `CYBERHEX_ANDROID_API=29` en el
  script: si Flutter baja de 29, el `.so` puede llamar símbolos no disponibles.
  Fijar `minSdk = 29` (o 24 y compilar con 24).
- **C5. Sin protección de puntero tras `dispose()`**: `NativePlayer` marca
  `_disposed` pero `play()/seek()/...` pueden llamarse después y hacen
  use-after-free sobre un puntero nativo. Añadir guardas.
- **C6. UX menor**: duración con `toStringAsFixed(0)` («183 s» en vez de
  «3:03»), la barra no responde a teclado cuando el foco está en otro widget,
  «Retroceder 10 s» en pista 0 s queda deshabilitado visualmente pero el
  control de atrás no reinicia la pista (comportamiento esperado en players).
- **C7. Solo `android/` y `linux/`**: la descripción del `pubspec` dice
  «escritorio y Android», pero `_Bindings._open()` lanza `UnsupportedError` en
  macOS/Windows/iOS.

---

## 4. Parches rápidos sugeridos (los primeros 30 minutos)

1. **Etiquetas del EQ desde el núcleo** (A1): exportar
   `ch_engine_eq_band_freq(index)` (ya tienes `eq.FREQS`) y en Dart generar
   etiquetas con `_formatHz`.
2. **Arreglar `set_band_gain`** (A2): guardar `gains_db: [36]f32` en `Engine`,
   actualizar el índice y reenviar el array completo.
3. **Mostrar `title`/`artist` + carátula** (B1): 3 `lookupFunction` más y un
   `Image.memory` en el disco. Es el cambio con mejor relación
   esfuerzo/impacto visual.
4. **Sacar `ffmpeg-src` del índice** (A4): `git rm -r --cached core/third_party/ffmpeg-src`
   (manteniendo la descarga automática) y añadir la ruta al `.gitignore`.
5. **Blindar el Gradle** (A5): `onlyIf { !project.hasProperty("skipCoreBuild") }`
   + `outputs.dir(...)` con la carpeta `jniLibs`.
6. **README + LICENSE** (A6).

## 5. Roadmap técnico sugerido

- **Fase 1 — coherencia**: corregir A1/A2, cargar metadatos y carátula, mover
  la carga a isolate, completar README/LICENSE, limpiar FFmpeg del git.
- **Fase 2 — producto**: cola visible, siguiente/anterior, repeat/shuffle,
  letras LRC, visualizador con `ch_engine_spectrum`, portada real del álbum,
  hojas de dispositivos y temporizador.
- **Fase 3 — robustez**: cola lock-free de eventos, tests de integración del
  motor, servicio en primer plano + audio focus en Android, CI que compile
  núcleo (Linux) y analice Dart.

---

## 6. Cómo se hizo este análisis y sus límites

- Lectura completa de `lib/`, `core/src/root.zig`, `eq.zig`, `fft.zig`,
  `stretch.zig` (parcial), `audio.c`, `decode_ffmpeg.c` (núcleo),
  `library.c`, `markers.c`, `lyrics.c`, `playlist.c`, `build.zig`, scripts de
  build, Gradle y manifest.
- Comprobación con `gcc -std=c2x -fsyntax-only -Wall -Wextra -Wshadow`: 0
  warnings en los 5 archivos C que no requieren FFmpeg.
- Tras aplicar las correcciones se instaló **Zig 0.17.1** (el que declara la
  API) y se verificó de verdad:
  - `zig build-obj src/root.zig -lc` compila sin errores;
  - `zig test` pasa en `eq.zig` (2), `fft.zig` (1) y `stretch.zig` (3);
  - el `.so` completo enlaza con el backend miniaudio
    (`root.zig + audio.c + decode_miniaudio.c + playlist/lyrics/library/markers`);
  - los 20 símbolos que usa `native_player.dart` están exportados;
  - prueba de humo con `dlopen` + C: 36 bandas con sus frecuencias, `0` fuera
    de rango, `set_band_gain(-1) = -2`, y reproducción real de un WAV
    (`load=0`, `duration=1.00`, `position=0.390` tras 400 ms, `covers=0`).
- **No** se pudo compilar ni analizar Flutter/Dart en este entorno: no hay SDK
  y las descargas de Flutter no son accesibles. Los cambios de Dart están
  revisados a mano (balance de bloques y tipos), sin `flutter analyze`.
- Los hallazgos A3, A4, B6 y B7 se verificaron leyendo el código citado; los de
  rendimiento (B3/B4/B5) son análisis estático.
