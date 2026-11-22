# CyberHex Core — API

Núcleo de reproducción de audio en Zig 0.17.1 + C23. Exporta una API C estable
pensada para FFI (Flutter/Dart en el cliente). Decodifica en streaming: nunca
carga la canción completa en RAM.

## Compilar

```bash
cd core
zig build                         # ReleaseFast por defecto -> zig-out/lib/libcyberhex_core.so
zig build --release=safe          # misma build con comprobaciones de seguridad
zig build -Drelease=false         # Debug, para depurar
zig build -Ddecoder=miniaudio     # sin FFmpeg (WAV/FLAC/MP3/Vorbis), cero dependencias
zig build -Ddecoder=ffmpeg        # exige FFmpeg; falla con un mensaje claro si falta
zig build test                    # tests unitarios del núcleo
zig build smoke                   # prueba de humo con audio real (ver más abajo)
./build_ffmpeg_android.sh         # FFmpeg estático para arm64-v8a (una vez)
./build_android.sh                # -> jniLibs/arm64-v8a/libcyberhex_core.so
```

### Android: `arm64-v8a` portable (objetivo: Redmi Note 13, Snapdragon 685)

El build de Android compila **solo `arm64-v8a`** para cualquier móvil 64-bit
(ARMv8-A + NEON, obligatorio en AArch64). No asume un SoC concreto: sirve igual
en Snapdragon, Helio, Exynos o Tensor.

- Por defecto `-mcpu baseline` (ARMv8-A genérico), sin riesgo de instrucciones
  no soportadas.
- Para afinar a un SoC concreto sin cambiar nada más:
  `CYBERHEX_CPU=cortex_a76 ./build_android.sh` (nombres válidos:
  `zig build-lib -target aarch64-linux-android -mcpu help`). El binario afinado
  sigue siendo ARMv8-A y corre en ese SoC; no lo uses en otros.
- `-O3 -ffast-math -fno-math-errno` en el código C.
- `abiFilters = arm64-v8a` en `android/app/build.gradle.kts`: el APK solo
  empaqueta ese ABI (menos tamaño, sin librerías muertas).

Para otros dispositivos, pasar los ABI como argumentos (`./build_android.sh
arm64-v8a armeabi-v7a x86_64`) o quitar el `abiFilters`.

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

int32_t ch_engine_load(ch_engine* engine, const char* utf8_path);      /* deja la cola con 1 pista */
int32_t ch_engine_play_index(ch_engine* engine, int32_t index);         /* reproduce sin vaciar la cola */
int32_t ch_engine_load_add(ch_engine* engine, const char* utf8_path);   /* añade al final y reproduce */
int32_t ch_engine_play(ch_engine* engine);
int32_t ch_engine_pause(ch_engine* engine);
int32_t ch_engine_seek(ch_engine* engine, double seconds);
int32_t ch_engine_set_volume(ch_engine* engine, float volume); /* 0.0 .. 1.0 */
float   ch_engine_volume(ch_engine* engine);

/* DSP: crossfeed de auriculares, mono, balance y medidores (dBFS). */
int32_t ch_engine_set_crossfeed(ch_engine* engine, int32_t enabled, float strength);
int32_t ch_engine_crossfeed(ch_engine* engine, float* strength);
int32_t ch_engine_set_mono(ch_engine* engine, int32_t enabled);
int32_t ch_engine_mono(ch_engine* engine);
int32_t ch_engine_set_balance(ch_engine* engine, float balance); /* -1 .. +1 */
float   ch_engine_balance(ch_engine* engine);
int32_t ch_engine_set_gain_db(ch_engine* engine, float gain_db); /* -24 .. +24 */
float   ch_engine_gain_db(ch_engine* engine);
int32_t ch_engine_save_cover(ch_engine* engine, int32_t index, const char* path);
int32_t ch_engine_meter(ch_engine* engine, float* peak_l_db, float* peak_r_db, float* rms_db);

/* Bucle A-B. */
int32_t ch_engine_set_ab_loop(ch_engine* engine, double a_seconds, double b_seconds);
int32_t ch_engine_clear_ab_loop(ch_engine* engine);
int32_t ch_engine_ab_loop(ch_engine* engine, double* a_seconds, double* b_seconds);

/* Estado persistente (cola, pista, posicion y ajustes). */
int32_t ch_engine_save_state(ch_engine* engine, const char* path);
int32_t ch_engine_load_state(ch_engine* engine, const char* path, double* position_out);
/* Exporta cola + ajustes a un archivo JSON legible (para backups). */
int32_t ch_engine_export_json(ch_engine* engine, const char* path);

/* Sonoridad y picos (analisis offline). */
typedef struct { double integrated_lufs; double sample_peak_dbfs; double duration_s; } ch_loudness_result;
int32_t ch_loudness_scan(const char* utf8_path, ch_loudness_result* out);
int32_t ch_waveform_peaks(const char* utf8_path, uint32_t buckets, float* out_max);

/* Hojas CUE. */
ch_cue*   ch_cue_read(const char* path);
void      ch_cue_free(ch_cue* cue);
int32_t   ch_cue_count(const ch_cue* cue);
const char* ch_cue_album(const ch_cue* cue);
const char* ch_cue_album_performer(const ch_cue* cue);
const char* ch_cue_file(const ch_cue* cue, int32_t index);
const char* ch_cue_title(const ch_cue* cue, int32_t index);
const char* ch_cue_performer(const ch_cue* cue, int32_t index);
double    ch_cue_start(const ch_cue* cue, int32_t index);
double    ch_cue_end(const ch_cue* cue, int32_t index);
int32_t   ch_cue_number(const ch_cue* cue, int32_t index);

/* Analisis, trim, ancho y normalizacion. */
int32_t ch_engine_set_stereo_width(ch_engine* engine, float width); /* 0 mono .. 2 ancho */
float   ch_engine_stereo_width(ch_engine* engine);
int32_t ch_engine_set_trim_silence(ch_engine* engine, int32_t enabled, float threshold_db);
int32_t ch_engine_detect_silence(const char* utf8_path, float threshold_db, double* lead, double* tail);
int32_t ch_engine_trim_silence(ch_engine* engine, float* threshold_db);
int32_t ch_engine_set_fade_out(ch_engine* engine, float seconds); /* 0 .. 30 */
float   ch_engine_fade_out(ch_engine* engine);
int32_t ch_engine_analyze_current(ch_engine* engine, double* lufs, double* peak_db);
int32_t ch_engine_normalize_current(ch_engine* engine, double target_lufs, double* applied_db);

/* Temporizador de apagado: pausa tras `seconds` con fundido de `fade_seconds`.
 * seconds <= 0 lo desactiva. ch_engine_sleep_remaining: segundos restantes o -1. */
int32_t ch_engine_set_sleep_timer(ch_engine* engine, double seconds, double fade_seconds);
double  ch_engine_sleep_remaining(ch_engine* engine);

/* ReplayGain (activado por defecto; sin tag el factor es 1.0). */
int32_t ch_engine_set_replaygain(ch_engine* engine, int32_t enabled);
float   ch_engine_replaygain_gain_db(ch_engine* engine);
float   ch_engine_replaygain_peak(ch_engine* engine);
/* 0 = por pista (def.), 1 = por album: una sola ganancia para todo el disco.
 * Si no hay tags REPLAYGAIN_* se usa R128_TRACK_GAIN/R128_ALBUM_GAIN (Q7.8).
 * Solo afecta a las pistas que se abran después. */
int32_t ch_engine_set_replaygain_mode(ch_engine* engine, int32_t mode);
int32_t ch_engine_replaygain_mode(ch_engine* engine);

/* Dispositivos de salida. index -1 = predeterminado del sistema. */
int32_t     ch_engine_output_device_count(void);
const char* ch_engine_output_device_name(int32_t index);
int32_t     ch_engine_output_device(ch_engine* engine);
int32_t     ch_engine_set_output_device(ch_engine* engine, int32_t index);

/* Cola de reproducción y avance gapless. */
int32_t ch_engine_queue_add(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_queue_count(ch_engine* engine);
/* Ruta de la pista `index` de la cola ("" si no existe). Valida hasta que
 * cambie la cola: copiala, no guardes el puntero. */
const char* ch_engine_queue_item(ch_engine* engine, int32_t index);
int32_t ch_engine_queue_index(ch_engine* engine);
int32_t ch_engine_queue_clear(ch_engine* engine);
int32_t ch_engine_queue_move(ch_engine* engine, int32_t from, int32_t to);
int32_t ch_engine_queue_remove(ch_engine* engine, int32_t index);
int32_t ch_engine_queue_insert(ch_engine* engine, int32_t index, const char* utf8_path);
int32_t ch_engine_queue_import(ch_engine* engine, const char* list_path);
int32_t ch_engine_queue_export(ch_engine* engine, const char* list_path);
int32_t ch_engine_next(ch_engine* engine);
int32_t ch_engine_previous(ch_engine* engine);
int32_t ch_engine_set_gapless(ch_engine* engine, int32_t enabled);
int32_t ch_engine_gapless(ch_engine* engine);

/* Repeticion: 0 = apagada, 1 = toda la cola, 2 = pista actual. */
int32_t ch_engine_set_repeat(ch_engine* engine, int32_t mode);
int32_t ch_engine_repeat(ch_engine* engine);

/* Orden aleatorio reproducible (la semilla define el orden). */
int32_t ch_engine_set_shuffle(ch_engine* engine, int32_t enabled);
int32_t ch_engine_shuffle(ch_engine* engine);
int32_t ch_engine_set_shuffle_seed(ch_engine* engine, uint32_t seed);

/* Crossfade equal-power entre pistas (0 = desactivado, máximo 12 s). */
int32_t ch_engine_set_crossfade(ch_engine* engine, float seconds);
float   ch_engine_crossfade(ch_engine* engine);

/* Velocidad sin cambiar el tono (0.25 - 4.0) y tono en semitonos (-12 a +12). */
int32_t ch_engine_set_speed(ch_engine* engine, float speed);
float   ch_engine_speed(ch_engine* engine);
int32_t ch_engine_set_pitch(ch_engine* engine, float semitones);
float   ch_engine_pitch(ch_engine* engine);

/* Analizador de espectro: `bands` valores 0..1 de 20 Hz a 20 kHz (-80..0 dB). */
int32_t ch_engine_spectrum(ch_engine* engine, float* out, int32_t bands);

/* Ecualizador: 36 bandas logarítmicas de 20 Hz a 20 kHz, ganancia ±18 dB.
 * `ch_engine_eq_band_freq` devuelve la frecuencia central de cada banda
 * (útil para etiquetar la UI sin duplicar la tabla). */
int32_t ch_engine_eq_band_count(void);
float   ch_engine_eq_band_freq(int32_t index);
int32_t ch_engine_set_eq_gains(ch_engine* engine, const float* gains_db, int32_t count);
int32_t ch_engine_set_band_gain(ch_engine* engine, int32_t band, float db);
/* Preamp del EQ en dB (0 a -24, nunca amplifica): baja la señal antes del banco
 * de filtros para que un refuerzo no haga recortar al limitador. */
int32_t ch_engine_set_eq_preamp(ch_engine* engine, float db);
float   ch_engine_eq_preamp(ch_engine* engine);
int32_t ch_engine_save_eq_preset(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_load_eq_preset(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_write_replaygain(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_export_spectrum_csv(ch_engine* engine, const char* utf8_path, int32_t points);
int32_t ch_engine_export_waveform_csv(ch_engine* engine, const char* utf8_path, int32_t buckets);
int32_t ch_engine_export_waveform_png(ch_engine* engine, const char* utf8_path, int32_t width, int32_t height);
int32_t ch_engine_export_spectrum_png(ch_engine* engine, const char* utf8_path, int32_t width, int32_t height, int32_t bands);
int32_t ch_engine_eq_preset_count(void);
int32_t ch_engine_eq_preset_name(int32_t index, char* out, int32_t out_len);
int32_t ch_engine_apply_eq_preset(ch_engine* engine, int32_t index);
int32_t ch_engine_copy_tags(const char* src_path, const char* dst_path);
int32_t ch_engine_export_queue_csv(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_save_lyrics(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_load_lyrics(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_shift_lyrics(ch_engine* engine, double delta_s);
double  ch_engine_lyrics_offset_ms(ch_engine* engine);
int32_t ch_engine_cover_count_current(ch_engine* engine);
int32_t ch_engine_save_cover_current(ch_engine* engine, int32_t index, const char* utf8_path);
int32_t ch_engine_eq_preset_find(const char* name);
int32_t ch_engine_write_bpm(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_export_wav(ch_engine* engine, const char* src_path, const char* dst_path, double start_s, double dur_s, int32_t rate, int32_t channels);
double  ch_bpm_detect_path(const char* utf8_path);
double  ch_engine_bpm(ch_engine* engine);
double  ch_dr_measure_path(const char* utf8_path, uint32_t* out_blocks);
double  ch_engine_dr(ch_engine* engine, uint32_t* out_blocks);

/* Metadatos y carátula embebida (JPEG/PNG). */
const char*    ch_engine_title(ch_engine* engine);
const char*    ch_engine_artist(ch_engine* engine);
const char*    ch_engine_album(ch_engine* engine);
const uint8_t* ch_engine_cover(ch_engine* engine, uint64_t* size);

/* Letra sincronizada (LRC): se busca un .lrc junto al audio. */
int32_t ch_engine_lyrics_count(ch_engine* engine);
int32_t ch_engine_lyric_line(ch_engine* engine, char* out, uint32_t out_size);

/* Niveles de salida para vúmetros: escribe rms_l, rms_r, peak_l, peak_r
 * (0..1, medidos después de EQ/ganancia/limitador, caída ~200 ms, bajan a cero
 * al pausar). Devuelve cuántos valores escribió. Seguro desde el hilo de UI. */
int32_t ch_engine_levels(ch_engine* engine, float* out, int32_t count);

/* Fundido al pausar y reanudar, en segundos (0 = corte inmediato, def. 0.05). */
int32_t ch_engine_set_pause_fade(ch_engine* engine, float seconds);
float   ch_engine_pause_fade(ch_engine* engine);

/* Loop A-B de la pista actual, en segundos. Al llegar a B se vuelve a A por el
 * mismo camino que un seek (respeta crossfade y estiramiento); `end <= start`
 * lo desactiva y también se cancela solo al cambiar de pista. */
int32_t ch_engine_set_loop(ch_engine* engine, double start, double end);
double  ch_engine_loop_start(ch_engine* engine);   /* -1 si inactivo */
double  ch_engine_loop_end(ch_engine* engine);     /* -1 si inactivo */

double  ch_engine_position(ch_engine* engine);   /* segundos */
double  ch_engine_duration(ch_engine* engine);   /* segundos, 0 si se desconoce */
double  ch_engine_sample_rate(ch_engine* engine);
int32_t ch_engine_channels(ch_engine* engine);
int32_t ch_engine_is_playing(ch_engine* engine);

/*
 * Eventos de reproduccion por sondeo (sin callbacks): devuelve 1 si lleno
 * `out`, 0 si no hay eventos, -1 si el motor o `out` es NULL.
 * kinds: CH_EVENT_STATE (a=1/0), CH_EVENT_TRACK (a=indice, b=nº pistas),
 *        CH_EVENT_QUEUE (a=nº pistas), CH_EVENT_END (fin natural de la cola).
 */
typedef struct ch_event { int32_t kind; int32_t a; int32_t b; double value; } ch_event;
int32_t ch_engine_poll_event(ch_engine* engine, ch_event* out);

const char* ch_engine_last_error(ch_engine* engine);

/* Etiquetas: date, genre, composer, track/disc number, y acceso generico. */
const char* ch_engine_tag(ch_engine* engine, const char* key);
const char* ch_engine_date(ch_engine* engine);
const char* ch_engine_genre(ch_engine* engine);
const char* ch_engine_composer(ch_engine* engine);
int32_t     ch_engine_track_number(ch_engine* engine);
int32_t     ch_engine_disc_number(ch_engine* engine);

/* Balance (-1 izq .. +1 der, acotado) y modo de canales (0 estereo, 1 mono,
 * 2 cambiados). Se aplican tras el EQ y antes del limitador. */
int32_t ch_engine_set_balance(ch_engine* engine, float balance);
float   ch_engine_balance(ch_engine* engine);
int32_t ch_engine_set_channel_mode(ch_engine* engine, int32_t mode);
int32_t ch_engine_channel_mode(ch_engine* engine);

/* Version del ABI (hoy 3). Sube ante cambios incompatibles. */
int32_t ch_engine_abi_version(void);

/* Limitador de picos (dBFS) y estadisticas de búfer. */
int32_t  ch_engine_set_limiter(ch_engine* engine, int32_t enabled, float ceiling_db);
int32_t  ch_engine_limiter(ch_engine* engine);
double   ch_engine_buffered_seconds(ch_engine* engine);
uint64_t ch_engine_buffer_underflows(ch_engine* engine);
/* Pistas que se saltaron solas por no poder abrirse (archivo roto/incompatible).
 * El avance automático ya no se detiene en una pista ilegible. */
uint64_t ch_engine_skipped_tracks(ch_engine* engine);

/* Detecta silencio al principio/fin de un archivo (dBFS). */
int32_t  ch_engine_detect_silence(const char* utf8_path, float threshold_db,
                                   double* lead, double* tail);

/* Biblioteca de audio: escaneo incremental de carpetas (handle opaco void*). */
void*     ch_library_create(void);
void      ch_library_destroy(void* lib);
int32_t   ch_library_scan(void* lib, const char* root);
int32_t   ch_library_count(const void* lib);
const char* ch_library_path(const void* lib, int32_t index);
/* Busca rutas que contengan el texto (case-insensitive). Devuelve un buffer de
 * indices (int32) y escribe el total en count_out; liberar con ch_file_free. */
int32_t*  ch_library_search(const void* lib, const char* needle, int32_t* count_out);
int32_t   ch_library_removed(const void* lib);

/* Caratulas multiples: una pista puede traer varias (p.ej. FLAC con varios
 * bloques PICTURE). ch_engine_cover() sigue devolviendo la primera. */
int32_t       ch_engine_cover_count(ch_engine* engine);
const uint8_t* ch_engine_cover_at(ch_engine* engine, int32_t index, uint64_t* size);

/* Marcadores por pista, persistentes en un archivo de texto plano. */
typedef struct ch_markers ch_markers;
ch_markers* ch_markers_create(void);
void      ch_markers_destroy(ch_markers* markers);
int32_t   ch_markers_load(ch_markers* markers, const char* path);
int32_t   ch_markers_save(const ch_markers* markers, const char* path);
int32_t   ch_markers_add(ch_markers* markers, const char* track, double position,
                          const char* name);
int32_t   ch_markers_count(const ch_markers* markers, const char* track);
double    ch_markers_position(const ch_markers* markers, const char* track,
                               int32_t index);
const char* ch_markers_name(const ch_markers* markers, const char* track,
                            int32_t index);
int32_t   ch_markers_remove(ch_markers* markers, const char* track, int32_t index);
int32_t   ch_markers_clear(ch_markers* markers, const char* track);
```

### Carátulas múltiples

`ch_engine_cover_count` devuelve cuántas carátulas trae la pista audible
(hasta 4 se conservan en memoria); `ch_engine_cover_at(i, &size)` devuelve la
i-ésima. `ch_engine_cover()` equivale a `ch_engine_cover_at(0)`.

### Marcadores

`ch_markers` es un almacén independiente del motor. Se asocia cada marca a la
ruta del archivo y una posición en segundos; `ch_markers_save` escribe todo en
un archivo de texto (una marca por línea, separada por tabuladores, con
escapes), y `ch_markers_load` lo recupera. La escritura es atómica: se escribe
un `.tmp` y se renombra encima. Para saltar a una marca basta con
`ch_engine_seek(e, position)`.

### DSP y medidores

- **Crossfeed** (`set_crossfeed`): mezcla el canal opuesto filtrado a ~700 Hz
  para reducir la fatiga al escuchar con auriculares. `strength` 0..1.
- **Mono** y **balance** se aplican antes del limitador.
- **Medidores** (`ch_engine_meter`): pico por canal y RMS en dBFS de la ventana
  transcurrida desde la llamada anterior; cada lectura reinicia la ventana.
  Con la pista en pausa devuelve -120 dB.

### Bucle A-B

`set_ab_loop(a, b)` requiere `0 <= a < b`. Al llegar a B, el motor vuelve a A
(se pide un seek al hilo decodificador). `ab_loop()` devuelve 1 y los valores
actuales, o 0 si está desactivado.

### Estado persistente

`ch_engine_save_state` escribe cola completa, pista actual, posición y ajustes
(volumen, repeat, shuffle, crossfade, velocidad, tono, ReplayGain, limitador,
mono, balance, crossfeed). `ch_engine_load_state` reconstruye la cola, carga la
pista actual en pausa y devuelve en `position_out` la posición guardada; la UI
decide si llama a `play` y a `seek`. Formato de texto versionado (`CHSTATE 1`),
escritura atómica.

### Ganancia, carátulas y análisis

- `ch_engine_set_gain_db` aplica una ganancia fija (-24..+24 dB) después del
  volumen y ReplayGain; se incluye en el estado persistente.
- `ch_engine_save_cover(index, path)` escribe la carátula i-ésima de la pista
  audible en un archivo (escritura atómica).
- `ch_loudness_scan` calcula sonoridad integrada ITU-R BS.1770-4 (K-weighting,
  bloques de 400 ms al 75%, puertas -70 LUFS absoluta y -10 LU relativa) y pico
  de muestra, sin tocar el motor. Sirve para generar ReplayGain propio.
- `ch_waveform_peaks(path, buckets, out)` devuelve el máximo por tramo en [0..1]
  para dibujar la forma de onda en la UI.

### Ancho, trim y sonoridad

- `ch_engine_set_stereo_width` controla el ancho de la imagen estereofónica
  mediante matriz mid/side: 0 = mono, 1 = normal, 2 = muy amplio.
- `ch_engine_set_trim_silence(engine, enabled, threshold_db)` recorta el silencio
  inicial (seek) y final (acorta el segmento) al abrir cada pista. El umbral se
  satura a [-90, -20] dBFS; por defecto -60 dBFS.
- `ch_engine_analyze_current` mide la sonoridad integrada (BS.1770-4) y el pico
  de muestra de la pista actual.
- `ch_engine_normalize_current(target_lufs)` mide y aplica una ganancia manual
  (limitada a ±24 dB) para alcanzar el objetivo; devuelve la ganancia aplicada.

### Hojas CUE

`ch_cue_read` parsea un `.cue` (FILE/TRACK/TITLE/PERFORMER/INDEX 01) y resuelve
el `FILE` relativo a la carpeta del `.cue`. `ch_cue_end` devuelve el inicio de
la pista siguiente, o -1 en la última. Para reproducir una pista: cargar
`ch_cue_file`, hacer `seek` a `ch_cue_start` y, si hay fin, detener o saltar en
`ch_cue_end`.

### Eventos de reproducción

El hilo de audio nunca llama a código de la UI. La UI consulta
`ch_engine_poll_event` desde su propio hilo (por ejemplo, un temporizador de
100 ms) y vacía la cola en bucle:

```c
ch_event ev;
while (ch_engine_poll_event(e, &ev) == 1) {
    switch (ev.kind) {
    case CH_EVENT_TRACK: /* nueva pista: ev.a = índice, ev.b = total */ break;
    case CH_EVENT_STATE: /* ev.a = 1 suena / 0 pausa o fin */ break;
    case CH_EVENT_QUEUE: /* ev.a = pistas en la cola */ break;
    case CH_EVENT_END:   /* terminó la cola en modo sin repetición */ break;
    }
}
```

Se emiten `TRACK` al cargar, saltar o cambiar de pista automáticamente;
`STATE` al reproducir, pausar y al agotarse la cola; `QUEUE` al añadir,
importar o vaciar; y `END` solo cuando la cola termina de forma natural. La
cola retiene 63 eventos y descarta el más antiguo si nadie la vacía.

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
- **Listas**: `queue_import` añade las pistas de un M3U/M3U8 o PLS (rutas
  relativas resueltas contra el directorio del archivo) y devuelve cuántas
  añadió. `queue_export` escribe la cola actual como M3U8 con rutas absolutas.
- **Gapless** (activado por defecto): al terminar una pista el decodificador
  abre la siguiente sin silencio. `ch_engine_next/previous` saltan de pista;
  `queue_index` refleja la pista que **suena**, no la que se está precargando.
- **Crossfade**: con `set_crossfade(segundos)` las pistas se solapan con curva
  equal-power (coseno/seno). Requiere gapless; el último tramo de A se mezcla
  con el inicio de B en el ring, así que no hay silencio ni salto. La duración
  reportada de A se acorta en el solape, y la posición avanza de forma continua
  hacia B.
- **Repetición**: `set_repeat(0|1|2)` = apagada, toda la cola o pista actual.
  Con `2`, al terminar la pista se vuelve a abrir desde el principio sin
  silencio. `next`/`previous` manuales siempre saltan de pista; el modo 2 solo
  afecta al avance automático.
- **Aleatorio**: `set_shuffle(1)` recorre la cola en orden aleatorio;
  `set_shuffle_seed(seed)` fija la semilla para que el orden sea reproducible
  (misma semilla, misma secuencia). Cada ciclo recorre todas las pistas sin
  repetir antes de volver a barajar. `next`/`previous` se refieren a la pista
  audible aunque el decodificador ya tenga la siguiente precargada.
- **Sin clics**: el volumen, el ReplayGain y los cambios de pausa/seek se
  aplican con una rampa de ~8 ms en el hilo de audio. Pausar no corta la onda
  en seco.
- **Play desde el final**: rebobina a 0 automáticamente.
- **Velocidad**: `set_speed(0.25..4)` aplica time-stretch WSOLA que preserva el
  tono; la posición y la duración siguen en tiempo musical (una pista de 2 s a
  velocidad 2 suena en ~1 s y termina en posición 2 s). El cambio se aplica al
  vaciarse el búfer; el crossfade se desactiva mientras hay velocidad/tono.
- **Tono**: `set_pitch(-12..+12)` remuestrea con interpolación cúbica y
  time-stretch compensatorio, así que cambia la frecuencia sin cambiar la
  duración. Velocidad y tono se combinan (p. ej. +12 semitonos a 2x).
- **Cambios en caliente**: `set_speed`/`set_pitch` con una pista sonando
  reconfiguran el motor al instante: se vacía el búfer, se reposiciona el
  decodificador en la posición audible y se reanuda. La posición no salta.
- **Espectro**: `ch_engine_spectrum(engine, out, bands)` entrega `bands`
  valores 0..1 repartidos logarítmicamente de 20 Hz a 20 kHz (-80 dB a 0 dB),
  medidos sobre el audio ya ecualizado y con volumen. En pausa devuelve ceros.
  Con 32 bandas, 440 Hz cae en la banda 13 y 880 Hz en la 17.
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

## Notas de mezcla (preamp, pausa, vúmetro)

- El preamp del EQ se aplica antes del banco y se compensa con el limitador:
  `ch_engine_set_eq_preamp(-3)` evita el recorte cuando se suben varias bandas.
- El fundido de pausa es configurable; a `0` el corte es inmediato. La posición
  cuenta el audio que suena durante el fundido, así que no se pierden ~50 ms por
  cada pausa.
- `ch_engine_levels` y `ch_engine_spectrum` no bloquean: se pueden llamar a
  10-30 Hz desde el hilo de UI. El vúmetro cae a cero al pausar.

## Aún no implementado

Motor de conversión, descargador y funciones de IA. Las carátulas múltiples se
limitan a 4 por pista en memoria.

### Búsqueda, fade-out y backup JSON

- `ch_library_search(lib, "texto", &n)` devuelve un buffer con los índices de la
  biblioteca cuya ruta contiene el texto (case-insensitive, así que "FLAC" caza
  la extensión y "radiohead" caza una carpeta). Hay que liberarlo con
  `ch_file_free`.
- `ch_engine_set_fade_out(seconds)` aplica un fundido de salida de N segundos
  (0..30) cuando quedan N segundos de pista; útil para mezclas sin cortes secos.
- `ch_engine_export_json(path)` escribe cola, pista actual, posición y todos los
  ajustes en un JSON legible, ideal para copias de seguridad o migrar a otro
  dispositivo.

### Efecto 8D y reverberación

- `ch_engine_set_8d(engine, enabled, speed, depth)`: auto-paneo giratorio
  (efecto "8D"). `speed` en vueltas/seg (0.05..2), `depth` 0..1. La imagen
  estereofónica rota suavemente entre los dos canales.
- `ch_engine_set_reverb(engine, enabled, mix)`: reverberación estérea
  (delay con feedback cruzado), `mix` 0..1.

### Compresor, EQ parametrico y HRTF

- `ch_engine_set_compressor(engine, enabled, threshold_db, ratio, attack_s, release_s)`
  comprime por encima del umbral para uniformar la sonoridad.
- `ch_engine_set_peq(engine, band, enabled, type, freq, gain_db, q)` para 4
  bandas: `type` 0 = peaking, 1 = low shelf, 2 = high shelf.
- `ch_engine_set_hrtf(engine, enabled, angle)` localizacion binaural
  (`angle` -1 izquierda .. +1 derecha) con retardo interaural.
- `ch_engine_spectrum(engine, out, bands)` ya devuelve `bands` valores 0..1
  para dibujar el visualizador.

### Caratula desde archivo, estadisticas y tags

- Si el audio no trae caratula, el motor busca `cover.jpg/png` (y variantes)
  junto al archivo y la expone como caratula 0.
- `ch_engine_stats(&plays, &seconds)` devuelve reproducciones y tiempo total.
- `ch_engine_set_tag(key, value)` escribe etiquetas en FLAC (Vorbis comments).
  `value = NULL` borra el campo. Solo FLAC por ahora.

### Cola: limpiar, deduplicar y filtrar

- `ch_engine_queue_prune()` elimina rutas que ya no existen.
- `ch_engine_queue_dedup()` elimina duplicados por ruta.
- `ch_engine_queue_dedup_hash()` elimina duplicados por contenido (tamano+hash).
- `ch_engine_queue_filter_dir(dir)` deja solo las pistas de un directorio.

### Favoritos

- `ch_engine_favorites_add/remove/save/load` gestionan una lista persistente.
- `ch_engine_favorites_export_m3u` la exporta como playlist.

### Loudness de album

- `ch_engine_album_loudness` y `ch_engine_normalize_album` normalizan por LUFS
  el promedio del album.

### Fades y gap

- `ch_engine_set_fade_in/out` (fundido de entrada/salida) y `ch_engine_set_gap`
  (silencio entre pistas).

### Historial reciente y pausa por carpeta

- `ch_engine_set_avoid_recent(1)` evita repetir pistas ya sonadas (shuffle).
- `ch_engine_recent_count/clear` consultan/limpian el historial.
- `ch_engine_set_pause_at_dir_end(1)` pausa al terminar una carpeta.

### Exportar biblioteca

- `ch_library_export_csv(path)` exporta a CSV (path;filename).

### Cargar carpeta

- `ch_engine_load_dir(dir)` añade a la cola todos los audios del directorio
  (no recursivo). Devuelve el numero añadido.

### Ganancia automatica

- `ch_engine_set_auto_gain(1, -14)` mide LUFS al abrir cada pista y ajusta la
  ganancia manual para alcanzar el objetivo (por defecto -14 LUFS).

### Gestion de cola

- `ch_engine_queue_sort/reverse/shuffle(seed)` reordenan la cola.
- `ch_engine_queue_insert_sorted(path)` inserta en orden alfabetico.
- `ch_engine_queue_keep_current()` deja solo la pista actual.
- `ch_engine_queue_duplicate_current()` la duplica al final.
- `ch_engine_queue_rotate()` la mueve al final.
- `ch_engine_queue_count_ext(".flac")` cuenta por extension.

### Tags MP3

- `ch_engine_set_tag` ahora soporta FLAC (Vorbis) y MP3 (ID3v2.3).

### Metadatos de cola por indice

- `ch_engine_queue_title/artist/album/genre/date/composer(index)` leen el tag
  sin cargar la pista en el motor.
- `ch_engine_queue_duration/cover_count(index)` dan duracion y caratulas.
- `ch_engine_queue_path/current_index(index)` dan la ruta y el indice actual.

### Ordenar cola por metadatos

- `ch_engine_queue_sort_title/artist/album/year/track/albumartist/genre/composer/duration/filesize`
  ordenan la cola abriendo cada archivo para leer su tag.
