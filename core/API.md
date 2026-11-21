# CyberHex Core — API

Núcleo de reproducción de audio en Zig 0.17.1 + C23. Exporta una API C estable
pensada para FFI (Flutter/Dart en el cliente). Decodifica en streaming: nunca
carga la canción completa en RAM.

## Compilar

```bash
cd core
zig build -Drelease=true          # -> zig-out/lib/libcyberhex_core.so
zig build test                    # tests unitarios del núcleo
./build_ffmpeg_android.sh         # FFmpeg estático para las 3 ABIs (una vez)
./build_android.sh                # -> jniLibs/{arm64-v8a,armeabi-v7a,x86_64}
```

Linux/PC enlaza la FFmpeg del sistema (libavformat, libavcodec, libavutil,
libswresample). Android enlaza FFmpeg estático desde
`third_party/ffmpeg-android/<abi>` (generado por `build_ffmpeg_android.sh`, no
versionado); si no existe, `build.zig` permite `-Dandroid-ffmpeg=false` para
volver a miniaudio.

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
| Android (FFmpeg estático) | La misma cobertura que Linux |
| Android (`-Dandroid-ffmpeg=false`) | WAV, FLAC, MP3, OGG/Vorbis (miniaudio) |

El `.so` Android enlaza FFmpeg de forma estática: solo depende de `libc`,
`libm` y `libdl` del sistema.

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

/* ReplayGain (activado por defecto; sin tag el factor es 1.0). */
int32_t ch_engine_set_replaygain(ch_engine* engine, int32_t enabled);
float   ch_engine_replaygain_gain_db(ch_engine* engine);
float   ch_engine_replaygain_peak(ch_engine* engine);

/* Dispositivos de salida. index -1 = predeterminado del sistema. */
int32_t     ch_engine_output_device_count(void);
const char* ch_engine_output_device_name(int32_t index);
int32_t     ch_engine_output_device(ch_engine* engine);
int32_t     ch_engine_set_output_device(ch_engine* engine, int32_t index);

/* Cola de reproducción y avance gapless. */
int32_t ch_engine_queue_add(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_queue_count(ch_engine* engine);
int32_t ch_engine_queue_index(ch_engine* engine);
int32_t ch_engine_queue_clear(ch_engine* engine);
int32_t ch_engine_next(ch_engine* engine);
int32_t ch_engine_previous(ch_engine* engine);
int32_t ch_engine_set_gapless(ch_engine* engine, int32_t enabled);
int32_t ch_engine_gapless(ch_engine* engine);

/* Crossfade equal-power entre pistas (0 = desactivado, máximo 12 s). */
int32_t ch_engine_set_crossfade(ch_engine* engine, float seconds);
float   ch_engine_crossfade(ch_engine* engine);

/* Velocidad sin cambiar el tono (0.25 - 4.0) y tono en semitonos (-12 a +12). */
int32_t ch_engine_set_speed(ch_engine* engine, float speed);
float   ch_engine_speed(ch_engine* engine);
int32_t ch_engine_set_pitch(ch_engine* engine, float semitones);
float   ch_engine_pitch(ch_engine* engine);

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

- **Carga**: `ch_engine_load` reemplaza la cola por el archivo indicado y lo
  deja listo para reproducir. `ch_engine_queue_add` añade al final y devuelve
  el índice; `queue_clear` vacía la cola.
- **Gapless** (activado por defecto): al terminar una pista el decodificador
  abre la siguiente sin silencio. `ch_engine_next/previous` saltan de pista;
  `queue_index` refleja la pista que **suena**, no la que se está precargando.
- **Crossfade**: con `set_crossfade(segundos)` las pistas se solapan con curva
  equal-power (coseno/seno). Requiere gapless; el último tramo de A se mezcla
  con el inicio de B en el ring, así que no hay silencio ni salto. La duración
  reportada de A se acorta en el solape, y la posición avanza de forma continua
  hacia B.
- **Play desde el final**: rebobina a 0 automáticamente.
- **Velocidad**: `set_speed(0.25..4)` aplica time-stretch WSOLA que preserva el
  tono; la posición y la duración siguen en tiempo musical (una pista de 2 s a
  velocidad 2 suena en ~1 s y termina en posición 2 s). El cambio se aplica al
  vaciarse el búfer; el crossfade se desactiva mientras hay velocidad/tono.
- **Tono**: `set_pitch(-12..+12)` remuestrea con interpolación cúbica y
  time-stretch compensatorio, así que cambia la frecuencia sin cambiar la
  duración. Velocidad y tono se combinan (p. ej. +12 semitonos a 2x).
- **Seek**: relativo al inicio de la pista audible, acotado a su duración. La
  posición se actualiza al instante aunque el audio tarde un bloque.
- **ReplayGain**: se aplica por pista al pasar a ella; la ganancia se limita
  para no superar 0 dBFS usando `REPLAYGAIN_TRACK_PEAK`.
- **Salida**: `set_output_device` recrea el dispositivo en caliente y mantiene
  la reproducción y la posición.
- **EQ**: cualquier banda en 0 dB se salta en el procesado; todas en 0 es
  identidad (sin coste).
- **Fin de cola**: `is_playing` pasa a 0 cuando termina de sonar la última
  pista, aunque el decodificador ya haya precargado todo.

## Errores

| Código | Significado |
|---|---|
| `-1` | puntero nulo o parámetro base inválido |
| `-2` | no se pudo abrir/decodificar el archivo, o no hay pista cargada |
| `-3` | el motor no respondió (timeout al cambiar de pista) |

El detalle está en `ch_engine_last_error` (o `ch_core_last_error` si falla la
creación del motor, p. ej. sin dispositivo de audio).

## Aún no implementado

Motor de conversión, descargador y funciones de IA.
