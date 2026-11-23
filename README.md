# CyberHex

Reproductor de música nativo para **Linux y Android**: motor propio en **Zig +
C23** con FFmpeg para decodificar, y **UI Flutter** que lo consume por FFI.

Por defecto, todo ocurre en local: no hay cuentas ni telemetría. La integración
opcional con Study Platform usa una conexión autenticada en `localhost`.

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

El núcleo exporta **180 funciones** y la app las alcanza **todas** por FFI:
cola editable con gapless y crossfade, repeat/shuffle, velocidad y tono,
espectro, ReplayGain y normalización R128, limitador, crossfeed, temporizador,
dispositivos de salida, carátulas múltiples, letras LRC, biblioteca incremental,
marcadores persistentes y hojas CUE.

La interfaz adaptable para celular y PC incluye reproducción, biblioteca local
con búsqueda, cola, modos de reproducción, letras, ajustes de DSP, visualizador
de espectro, forma de onda por pista, metadatos y EQ real de 36 bandas. La cola,
la posición y los ajustes de reproducción se restauran automáticamente en el
mismo dispositivo; la sesión vuelve pausada.

La referencia completa de la API está en [`core/API.md`](core/API.md).

## Integración local con Study Platform

CyberHex ofrece una API REST y un servidor MCP stateless en
`http://127.0.0.1:8765`; ambos escuchan solo en loopback y exigen una clave
`Authorization: Bearer`. La clave se genera al iniciar y se guarda con
almacenamiento seguro; se puede copiar desde **Ajustes → Conectar con Study
Platform**. No compartas esa clave: permite controlar el reproductor y su cola.

La REST v1 expone:

| Método y ruta | Función |
|---|---|
| `GET /api/v1/status` | Estado y metadatos de la pista actual |
| `GET /api/v1/library?q=<texto>` | Buscar en la biblioteca ya escaneada |
| `GET /api/v1/queue` | Leer la cola |
| `POST /api/v1/command` | `play`, `pause`, `toggle`, `next`, `previous` o `seek` |
| `POST /api/v1/volume` | Definir volumen entre `0` y `1` |
| `POST /api/v1/queue` | Añadir pista indexada, reproducir/eliminar por índice o vaciar |

Todas las rutas requieren `Authorization: Bearer <clave>`. Añadir pistas solo
acepta rutas devueltas por la biblioteca escaneada. El MCP en `/mcp` publica
`cyberhex_status`, `cyberhex_search_library`, `cyberhex_queue`,
`cyberhex_control` y `cyberhex_queue_add`.

Study Platform puede exponer las herramientas MCP `cyberhex_status`,
`cyberhex_library_search`, `cyberhex_queue`, `cyberhex_playback`,
`cyberhex_set_volume` y `cyberhex_queue_add`, respaldadas por la REST local.
Configura allí `CYBERHEX_API_URL=http://127.0.0.1:8765` y
`CYBERHEX_API_KEY=<clave copiada desde CyberHex>`.

Para el sentido inverso, configura el endpoint MCP de Study Platform
(`http://127.0.0.1:8090/mcp` por defecto) y su `CUSTOM_MCP_API_KEY` en los
ajustes de CyberHex. La conexión se prueba con `initialize` y `tools/list`;
las credenciales se almacenan de forma segura.

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
