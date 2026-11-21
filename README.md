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
| El núcleo en Linux | Zig 0.17. FFmpeg (`ffmpeg`) **opcional**: sin él compila con miniaudio (WAV/FLAC/MP3/OGG) |
| El núcleo en Android | Zig 0.17 + Android NDK (API 29). FFmpeg estático opcional (una vez) |

## Compilar y ejecutar en Linux (escritorio)

```bash
flutter pub get
flutter run -d linux        # el CMake compila el núcleo y lo empaqueta solo
```

`linux/CMakeLists.txt` invoca `zig build -Drelease=true -Ddecoder=auto` y copia
`libcyberhex_core.so` a `build/linux/x64/<modo>/bundle/lib/`, donde el runner lo
encuentra por su `RPATH` (`$ORIGIN/lib`). No hace falta `LD_LIBRARY_PATH`.

Para forzar el decodificador:

```bash
flutter build linux --release -d linux      # auto (FFmpeg si está)
flutter build linux -DCYBERHEX_DECODER=miniaudio   # sin FFmpeg
```

### Instalar en Arch Linux

Dependencias (repos oficiales + AUR para Flutter):

```bash
sudo pacman -S --needed base-devel flutter zig cmake ninja clang pkgconf \
  gtk3 ffmpeg alsa-lib libpulse fontconfig libxkbcommon libglvnd
```

Paquete nativo con `.desktop` e icono incluidos:

```bash
cd packaging/linux
makepkg -si
cyberhex                  # o desde el menú de aplicaciones
```

El `PKGBUILD` instala la app en `/usr/lib/cyberhex/`, el lanzador en
`/usr/share/applications/` y el icono en `hicolor/scalable/apps/`. Para probar
sin instalar:

```bash
flutter build linux --release
./build/linux/x64/release/bundle/cyberhex
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
(menos formatos: WAV, FLAC, MP3 y OGG/Vorbis); `build.zig` lo detecta solo y
avisa si falta el estático:

```bash
cd core && zig build -Dandroid-ffmpeg=false
```

### Qué incluye el APK

- Motor nativo `arm64-v8a` (Zig + C23) generado por la tarea `buildCyberHexCore`.
- Icono adaptativo propio (hexágono) para Android 8+.
- Permisos de **biblioteca de audio** (`READ_MEDIA_AUDIO` en 13+,
  `READ_EXTERNAL_STORAGE` hasta 12) y `WAKE_LOCK` para que no se corte con la
  pantalla apagada.
- Pendiente para que sea "de bolsillo" al 100 %: `MediaSession` + servicio en
  primer plano (`mediaPlayback`) con controles en la notificación, y las
  pantallas de biblioteca/cola.

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
