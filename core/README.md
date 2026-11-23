# CyberHex Core — Documentación API

**CyberHex Core** es una biblioteca C multiplataforma para reproducción de audio con capacidades avanzadas de DSP, gestión de metadatos, análisis de señal y biblioteca musical.

## Características principales

- **Reproducción**: Gapless, crossfade, speed/pitch shifting, A-B loop, sleep timer
- **DSP**: EQ paramétrico (31 bandas), crossfeed, reverb, compresor, limiter, 8D audio, HRTF
- **Metadatos**: Tags (FLAC/MP3/Ogg/Opus), letras LRC sincronizadas, carátulas, CUE sheets
- **Análisis**: LUFS (BS.1770), BPM, Dynamic Range, detección de tonalidad, waveform
- **Biblioteca**: Escaneo incremental, búsqueda case-insensitive, marcadores persistentes
- **Cola**: Reordenación, shuffle reproducible, import/export M3U/JSON/CSV
- **Multiplataforma**: Linux, Windows, macOS, Android (ARM64/ARMv7/x86_64/x86)

## Inicio rápido

```c
#include "cyberhex_core.h"

int main(int argc, char** argv) {
    ch_engine* e = ch_engine_create();
    ch_engine_load(e, "track.flac");
    ch_engine_play(e);
    // ...
    ch_engine_destroy(e);
}
```

## Arquitectura

```
cyberhex_core.h          # API pública completa (C99/C23)
├── audio.c              # miniaudio: dispositivos, decodificación
├── decode_ffmpeg.c      # FFmpeg: formatos extensos
├── decode_miniaudio.c   # miniaudio/dr_*: WAV/FLAC/MP3/Ogg/Vorbis
├── playlist.c           # M3U/M3U8/PLS
├── tags.c               # FLAC VorbisComment, ID3v2.3
├── ogg_tags.c           # Ogg Vorbis / Opus
├── library.c            # Escaneo recursivo + hash map
├── cue.c                # Parser CUE sheets
├── lyrics.c             # Parser/generador LRC
├── analysis.c           # LUFS, BPM, DR, Key, silence
├── markers.c            # Marcadores persistentes
├── fileio.c             # Lectura/escritura atómica
├── dirlist.c            # Listado no recursivo
└── error.c              # Códigos de error tipados
```

## Compilación

### Requisitos
- Zig 0.13+ (sistema de build)
- Opcional: FFmpeg development headers (`libavcodec-dev`, `libavformat-dev`)

### Build nativo (Linux/macOS/Windows)
```bash
# Solo miniaudio (sin dependencias externas)
zig build -Ddecoder=miniaudio

# Con FFmpeg (cobertura total de formatos)
zig build -Ddecoder=ffmpeg

# Release optimizado
zig build -Drelease=true -Ddecoder=miniaudio
```

### Cross-compilation
```bash
# Windows
zig build -Dtarget=x86_64-windows-gnu

# Android (requiere NDK y build_ffmpeg_android.sh para FFmpeg)
zig build -Dtarget=aarch64-linux-android
zig build -Dtarget=arm-linux-android
zig build -Dtarget=x86_64-linux-android
zig build -Dtarget=x86-linux-android

# macOS
zig build -Dtarget=x86_64-macos
zig build -Dtarget=aarch64-macos
```

### Tests
```bash
# Tests unitarios (11 módulos)
zig build test

# Test de integración con audio real
zig build smoke
```

## Estructura de la API

### Motor principal (`ch_engine_*`)
| Función | Descripción |
|---------|-------------|
| `ch_engine_create/destroy` | Ciclo de vida |
| `ch_engine_load/play/pause/seek` | Control básico |
| `ch_engine_queue_*` | Gestión de cola |
| `ch_engine_set_*/get_*` | DSP, volumen, EQ, etc. |
| `ch_engine_poll_event` | Eventos sin callbacks |

### Biblioteca (`ch_library_*`)
| Función | Descripción |
|---------|-------------|
| `ch_library_create/destroy` | Handle opaco |
| `ch_library_scan` | Escaneo incremental |
| `ch_library_search` | Búsqueda substring case-insensitive |
| `ch_library_path/count/removed` | Consulta |

### CUE sheets (`ch_cue_*`)
Parser completo para imágenes de audio con pista múltiple.

### Letras (`ch_lyrics_*`)
Parser/generador LRC con múltiples timestamps por línea y shift.

### Análisis offline
- `ch_loudness_scan` — LUFS integrated + true peak + duration
- `ch_bpm_detect_path` — BPM vía autocorrelación de novedad espectral
- `ch_dr_measure_path` — Dynamic Range (EBU R128)
- `ch_key_detect` — Krumhansl-Schmuckler con filtros Goertzel
- `ch_waveform_peaks` — Peaks por bucket para overview visual

### Códigos de error (`ch_result`)
```c
typedef enum {
    CH_OK = 0,
    CH_ERR_NOMEM = -1,
    CH_ERR_INVALID_ARG = -2,
    CH_ERR_DECODE = -3,
    CH_ERR_DEVICE = -4,
    CH_ERR_IO = -5,
    CH_ERR_FORMAT = -6,
    CH_ERR_NOT_FOUND = -7,
    CH_ERR_UNSUPPORTED = -8,
    CH_ERR_STATE = -9,
    CH_ERR_BUSY = -10,
    CH_ERR_CANCELLED = -11,
} ch_result;

const char* ch_result_str(ch_result r);
```

## Ejemplos

Ver `examples/`:
- `basic_playback.c` — Reproducción mínima
- `playlist_eq.c` — Cola + EQ + crossfade
- `analysis_tools.c` — LUFS, BPM, DR, Key, waveform
- `library_cue.c` — Escaneo biblioteca + CUE sheets

## Binding Dart/Flutter

Ver `../lib/core/native_player.dart` — FFI completo con `providesSymbol` para compatibilidad ABI.

## Licencia

MIT — ver `LICENSE` en la raíz del proyecto.