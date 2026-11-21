# CyberHex

Reproductor de música nativo para **Linux y Android**: motor propio en **Zig +
C23** con FFmpeg para decodificar, y **UI Flutter** que lo consume por FFI.

Todo ocurre en local: no hay cuentas, ni red, ni telemetría.

```
┌──────────────────────────────┐
│  Flutter (Dart)              │  lib/ui, lib/core/native_player.dart
│  play · pausa · seek · EQ    │
└──────────────┬───────────────┘
               │  FFI (libcyberhex_core.so)
┌──────────────▼───────────────┐
│  Núcleo Zig + C23            │  core/src/root.zig
│  · hilo decodificador        │  core/src/{audio,decode_ffmpeg}.c
│  · ring buffer de 4 s        │
│  · EQ de 36 bandas (seqlock) │  core/src/eq.zig
│  · FFT, stretch, ReplayGain  │
│  · letras, biblioteca, marcas│
└──────────────────────────────┘
```

## Estado

El **motor está muy por delante de la app**. El núcleo exporta 78 funciones
(cola con gapless y crossfade, repeat/shuffle, velocidad y tono, espectro FFT,
ReplayGain, limitador, temporizador, dispositivos de salida, carátulas
múltiples, letras LRC, biblioteca incremental y marcadores persistentes), y la
interfaz usa hoy una parte: abrir un archivo, play/pausa, seek, volumen, EQ real
de 36 bandas, metadatos y carátula.

La referencia completa de la API está en [`core/API.md`](core/API.md).

## Requisitos

| Para… | Necesitas |
|---|---|
| La app | Flutter (stable) con Dart ≥ 3.14 |
| El núcleo en Linux | Zig 0.17 + cabeceras de FFmpeg (`libavformat`, `libavcodec`, `libavutil`, `libswresample`) |
| El núcleo en Android | Zig 0.17 + Android NDK (API 29) + FFmpeg estático compilado una vez |

## Compilar y ejecutar en Linux

```bash
# 1. Núcleo -> core/zig-out/lib/libcyberhex_core.so
cd core && zig build && cd ..    # si no hay libav*-dev, compila con miniaudio (aviso)

# 2. App
flutter pub get
flutter run -d linux
```

La app busca `libcyberhex_core.so` con `DynamicLibrary.open`, así que en
desarrollo conviene dejarla en el `LD_LIBRARY_PATH` o copiarla junto al
ejecutable:

```bash
export LD_LIBRARY_PATH="$PWD/core/zig-out/lib:$LD_LIBRARY_PATH"
flutter run -d linux
```

## Compilar el APK

```bash
# Solo la primera vez: FFmpeg estático para arm64-v8a (~10-20 min)
cd core && ./build_ffmpeg_android.sh arm64-v8a && cd ..

# APK
flutter build apk --release
```

La tarea de Gradle `buildCyberHexCore` compila el `.so` antes del APK y
**solo se recompila si cambian los fuentes**. Si ya tienes el `.so` en
`android/app/src/main/jniLibs/arm64-v8a/` o no tienes el NDK a mano:

```bash
flutter build apk --release --android-project-arg=skipCoreBuild=true
```

Sin FFmpeg estático se puede compilar el núcleo con el backend miniaudio
(menos formatos: WAV, FLAC, MP3 y OGG/Vorbis):

```bash
cd core && zig build -Dandroid-ffmpeg=false
```

El APK empaqueta solo `arm64-v8a` (Redmi Note 13 / Snapdragon 685). Para otros
ABI hay que pasar los argumentos a `build_android.sh` y ajustar `abiFilters`
en `android/app/build.gradle.kts`.

## Estructura

```
lib/
  main.dart                 arranque de la app
  theme.dart                paleta y ThemeData
  core/native_player.dart   bindings FFI (única frontera con el núcleo)
  ui/player_page.dart       pantalla del reproductor
  ui/eq_sheet.dart          hoja del ecualizador (36 bandas)
core/
  include/cyberhex_core.h   API C pública
  src/root.zig              motor, hilo decodificador, cola, eventos
  src/eq.zig, fft.zig       EQ de 36 bandas y FFT
  src/stretch.zig           velocidad/tono sin cambiar el otro
  src/*.c                   audio (miniaudio), decodificadores, biblioteca…
  build.zig                 build de escritorio y tests
  build_android.sh          build del .so para Android
  third_party/ffmpeg-src/   fuentes de FFmpeg (no se compilan en cada build)
```

## Pruebas

```bash
cd core && zig build test     # EQ, FFT y speed/pitch
cd core && zig build smoke    # motor real: niveles, pausa, loop A-B, eventos
flutter test                  # tema
```

## Notas legales

- **FFmpeg** se enlaza de forma estática y sin `--enable-gpl`, es decir bajo
  **LGPL v2.1 o posterior**. Si distribuyes un APK con ese binario, la LGPL
  exige poder reenlazarlo: publica el código de CyberHex y las instrucciones
  (`build_ffmpeg_android.sh`) junto al binario.
- **miniaudio** y **dr_libs** son de dominio público / MIT-0.
- Las tipografías **Poppins** y **Righteous** son SIL OFL 1.1.

## Licencia

MIT. Ver [`LICENSE`](LICENSE).
