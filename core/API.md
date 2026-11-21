# CyberHex Core — API

Núcleo de reproducción de audio en Zig 0.17.1 + C23. Exporta una API C estable
pensada para FFI (Flutter/Dart en el cliente). Decodifica en streaming: nunca
carga la canción completa en RAM.

## Compilar

```bash
cd core
zig build                         # ReleaseFast por defecto -> zig-out/lib/libcyberhex_core.so
zig build -Doptimize=ReleaseSafe  # misma build con comprobaciones de seguridad
zig build test                    # tests unitarios del núcleo
./build_ffmpeg_android.sh         # FFmpeg estático para arm64-v8a (una vez)
./build_android.sh                # -> jniLibs/arm64-v8a/libcyberhex_core.so
```

### Objetivo: Redmi Note 13 (Snapdragon 685)

El build de Android compila **solo `arm64-v8a`**, optimizado para el SoC del
Redmi Note 13 (4× Cortex-A73 @ 2.8 GHz + 4× Cortex-A53 @ 1.9 GHz, Adreno 610):

- `-mcpu cortex_a73` (tuning de pipeline del núcleo grande; el código sigue
  siendo ARMv8-A genérico y corre en cualquier Android 64-bit).
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

/* Temporizador de apagado: pausa tras `seconds` con fundido de `fade_seconds`.
 * seconds <= 0 lo desactiva. ch_engine_sleep_remaining: segundos restantes o -1. */
int32_t ch_engine_set_sleep_timer(ch_engine* engine, double seconds, double fade_seconds);
double  ch_engine_sleep_remaining(ch_engine* engine);

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

/* Metadatos y carátula embebida (JPEG/PNG). */
const char*    ch_engine_title(ch_engine* engine);
const char*    ch_engine_artist(ch_engine* engine);
const char*    ch_engine_album(ch_engine* engine);
const uint8_t* ch_engine_cover(ch_engine* engine, uint64_t* size);

/* Letra sincronizada (LRC): se busca un .lrc junto al audio. */
int32_t ch_engine_lyrics_count(ch_engine* engine);
int32_t ch_engine_lyric_line(ch_engine* engine, char* out, uint32_t out_size);

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

/* Limitador de picos (dBFS) y estadisticas de búfer. */
int32_t  ch_engine_set_limiter(ch_engine* engine, int32_t enabled, float ceiling_db);
int32_t  ch_engine_limiter(ch_engine* engine);
double   ch_engine_buffered_seconds(ch_engine* engine);
uint64_t ch_engine_buffer_underflows(ch_engine* engine);

/* Detecta silencio al principio/fin de un archivo (dBFS). */
int32_t  ch_engine_detect_silence(const char* utf8_path, float threshold_db,
                                   double* lead, double* tail);

/* Biblioteca de audio: escaneo incremental de carpetas (handle opaco void*). */
void*     ch_library_create(void);
void      ch_library_destroy(void* lib);
int32_t   ch_library_scan(void* lib, const char* root);
int32_t   ch_library_count(const void* lib);
const char* ch_library_path(const void* lib, int32_t index);
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

## Aún no implementado

Motor de conversión, descargador y funciones de IA. Las carátulas múltiples se
limitan a 4 por pista en memoria.
