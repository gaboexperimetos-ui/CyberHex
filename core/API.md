# CyberHex Core — API

Núcleo de reproducción de audio en Zig 0.17.1 + C23. Exporta una API C estable
pensada para FFI (Flutter/Dart en el cliente). Decodifica en streaming: nunca
carga la canción completa en RAM.

## Compilar

```bash
cd core
zig build -Drelease=true          # -> zig-out/lib/libcyberhex_core.so
zig build test                    # tests unitarios del núcleo
./build_android.sh                # -> jniLibs/{arm64-v8a,armeabi-v7a,x86_64}
```

Linux/PC enlaza FFmpeg (libavformat, libavcodec, libavutil, libswresample).
Android usa miniaudio (sin FFmpeg en el APK por ahora).

## Arquitectura

- **Hilo de audio**: miniaudio llama al callback `render` cada bloque.
- **Hilo decodificador**: lee del decoder a un ring buffer de 4 s.
- `ch_engine_play/pause/seek` solo tocan atómicos; el hilo decodificador hace
  el trabajo pesado.
- El EQ de 36 bandas corre en el callback con seqlock: los cambios de ganancia
  son atómicos y no bloquean el audio.

## Cobertura de formatos

| Backend | Formatos |
|---|---|
| Linux (FFmpeg) | FLAC, MP3, WAV, OGG/Vorbis, Opus, M4A/AAC, ALAC, AIFF, WMA, APE, WavPack, prácticamente todo lo que soporte FFmpeg |
| Android (miniaudio) | WAV, FLAC, MP3, OGG/Vorbis |

M4A/AAC/ALAC/Opus/AIFF en Android requieren compilar FFmpeg con el NDK
(pendiente).

## API

Todas las funciones devuelven `int32_t` (`0` = éxito, negativo = error) salvo
las indicadas. Las cadenas son UTF-8 y válidas hasta la siguiente carga o
`ch_engine_destroy`.

```c
const char* ch_core_version(void);
const char* ch_core_last_error(void);   /* error de creación global */

ch_engine* ch_engine_create(void);
void       ch_engine_destroy(ch_engine* engine);

int32_t ch_engine_load(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_play(ch_engine* engine);
int32_t ch_engine_pause(ch_engine* engine);
int32_t ch_engine_seek(ch_engine* engine, double seconds);
int32_t ch_engine_set_volume(ch_engine* engine, float volume); /* 0.0 .. 1.0 */

/* Ecualizador: 36 bandas logarítmicas de 20 Hz a 20 kHz, ganancia ±18 dB. */
int32_t ch_engine_eq_band_count(void);
int32_t ch_engine_set_eq_gains(ch_engine* engine, const float* gains_db, int32_t count);
int32_t ch_engine_set_band_gain(ch_engine* engine, int32_t band, float db);

/* Metadatos y carátula embebida (JPEG/PNG). */
const char*    ch_engine_title(ch_engine* engine);
const char*    ch_engine_artist(ch_engine* engine);
const char*    ch_engine_album(ch_engine* engine);
const uint8_t* ch_engine_cover(ch_engine* engine, uint64_t* size);

double  ch_engine_position(ch_engine* engine);   /* segundos */
double  ch_engine_duration(ch_engine* engine);   /* segundos, 0 si se desconoce */
double  ch_engine_sample_rate(ch_engine* engine);
int32_t ch_engine_channels(ch_engine* engine);
int32_t ch_engine_is_playing(ch_engine* engine);

const char* ch_engine_last_error(ch_engine* engine);
```

### Ejemplo mínimo

```c
ch_engine* e = ch_engine_create();
if (!e) { fprintf(stderr, "%s\n", ch_core_last_error()); return 1; }
if (ch_engine_load(e, "cancion.flac") != 0) {
    fprintf(stderr, "%s\n", ch_engine_last_error(e));
    ch_engine_destroy(e);
    return 1;
}
printf("%s - %s (%.1f s)\n", ch_engine_artist(e), ch_engine_title(e),
       ch_engine_duration(e));
ch_engine_play(e);
/* ... */
ch_engine_destroy(e);
```

## Comportamiento

- **Carga**: detiene la reproducción, espera al hilo decodificador y cierra el
  decoder anterior. La duración y los metadatos quedan disponibles enseguida.
- **Play desde el final**: rebobina a 0 automáticamente.
- **Seek**: acotado a la duración; la posición se actualiza al instante aunque
  el audio tarde un bloque.
- **EQ**: cualquier banda en 0 dB se salta en el procesado; todas en 0 es
  identidad (sin coste).
- **Fin de pista**: `is_playing` pasa a 0; la posición se queda en la duración.

## Errores

| Código | Significado |
|---|---|
| `-1` | puntero nulo o parámetro base inválido |
| `-2` | no se pudo abrir/decodificar el archivo, o no hay pista cargada |
| `-3` | el motor no respondió (timeout al cambiar de pista) |

El detalle está en `ch_engine_last_error` (o `ch_core_last_error` si falla la
creación del motor, p. ej. sin dispositivo de audio).

## Aún no implementado

Gapless/crossfade, ReplayGain, playlists, selección de dispositivo de salida,
velocidad/tono, motor de conversión, descargador y funciones de IA.
