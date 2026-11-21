#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ch_engine ch_engine;

const char* ch_core_version(void);
const char* ch_core_last_error(void);

ch_engine* ch_engine_create(void);
void ch_engine_destroy(ch_engine* engine);

int32_t ch_engine_load(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_play(ch_engine* engine);
int32_t ch_engine_pause(ch_engine* engine);
int32_t ch_engine_seek(ch_engine* engine, double seconds);

/* Cola editable: mover, quitar e insertar pistas sin cortar el audio. */
int32_t ch_engine_queue_move(ch_engine* engine, int32_t from, int32_t to);
int32_t ch_engine_queue_remove(ch_engine* engine, int32_t index);
int32_t ch_engine_queue_insert(ch_engine* engine, int32_t index, const char* utf8_path);

int32_t ch_engine_set_volume(ch_engine* engine, float volume);

/*
 * Temporizador de apagado: pausa (o termina) tras `seconds`, con fundido
 * final de `fade_seconds`. `seconds <= 0` lo desactiva. `ch_engine_sleep_remaining`
 * devuelve los segundos que faltan o -1 si no hay temporizador activo.
 * Al agotarse se emite CH_EVENT_SLEEP y CH_EVENT_STATE(0).
 */
int32_t ch_engine_set_sleep_timer(ch_engine* engine, double seconds, double fade_seconds);
double  ch_engine_sleep_remaining(ch_engine* engine);

/* ReplayGain: aplica la ganancia de pista si el archivo trae la etiqueta. */
int32_t ch_engine_set_replaygain(ch_engine* engine, int32_t enabled);
float   ch_engine_replaygain_gain_db(ch_engine* engine);
float   ch_engine_replaygain_peak(ch_engine* engine);

/* Limitador de picos en caliente (ceiling en dBFS, p.ej. -1.0). */
int32_t ch_engine_set_limiter(ch_engine* engine, int32_t enabled, float ceiling_db);
int32_t ch_engine_limiter(ch_engine* engine);

/* Dispositivos de salida. index -1 = predeterminado del sistema. */
int32_t     ch_engine_output_device_count(void);
const char* ch_engine_output_device_name(int32_t index);
int32_t     ch_engine_output_device(ch_engine* engine);
int32_t     ch_engine_set_output_device(ch_engine* engine, int32_t index);

/* Lista de reproducción y avance gapless. */
int32_t ch_engine_queue_add(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_queue_count(ch_engine* engine);
int32_t ch_engine_queue_index(ch_engine* engine);
int32_t ch_engine_queue_clear(ch_engine* engine);
/* Mueve la pista `from` a la posición `to` (reordena sin cortar el audio). */
int32_t ch_engine_queue_move(ch_engine* engine, int32_t from, int32_t to);
/* Quita la pista `index`. Si es la que suena, continúa con la siguiente. */
int32_t ch_engine_queue_remove(ch_engine* engine, int32_t index);
/* Inserta `utf8_path` en la posición `index` (<=0 = principio, negativo = final). */
int32_t ch_engine_queue_insert(ch_engine* engine, int32_t index, const char* utf8_path);
/* Importa M3U/M3U8/PLS y añade sus pistas al final; devuelve cuántas añadió. */
int32_t ch_engine_queue_import(ch_engine* engine, const char* list_path);
/* Exporta la cola actual como M3U8. */
int32_t ch_engine_queue_export(ch_engine* engine, const char* list_path);
int32_t ch_engine_next(ch_engine* engine);
int32_t ch_engine_previous(ch_engine* engine);
int32_t ch_engine_set_gapless(ch_engine* engine, int32_t enabled);
int32_t ch_engine_gapless(ch_engine* engine);

/* Repeticion: 0 = apagada, 1 = toda la cola, 2 = pista actual. */
int32_t ch_engine_set_repeat(ch_engine* engine, int32_t mode);
int32_t ch_engine_repeat(ch_engine* engine);

/* Orden aleatorio reproducible: la semilla manda en el orden de la cola. */
int32_t ch_engine_set_shuffle(ch_engine* engine, int32_t enabled);
int32_t ch_engine_shuffle(ch_engine* engine);
int32_t ch_engine_set_shuffle_seed(ch_engine* engine, uint32_t seed);

/* Crossfade entre pistas al pasar de una a otra (0 = desactivado). */
int32_t ch_engine_set_crossfade(ch_engine* engine, float seconds);
float   ch_engine_crossfade(ch_engine* engine);

/* Velocidad de reproduccion sin cambiar el tono (0.25 - 4.0, 1 = normal). */
int32_t ch_engine_set_speed(ch_engine* engine, float speed);
float   ch_engine_speed(ch_engine* engine);

/* Tono en semitonos sin cambiar la duracion (-12 a +12, 0 = normal). */
int32_t ch_engine_set_pitch(ch_engine* engine, float semitones);
float   ch_engine_pitch(ch_engine* engine);

/*
 * Analizador de espectro sobre el audio que suena (post-EQ, post-volumen).
 * Escribe `bands` valores 0.0-1.0 en `out`, repartidos logaritmicamente de
 * 20 Hz a 20 kHz (-80 dB .. 0 dB). Pensado para vúmetros/visualizadores.
 */
int32_t ch_engine_spectrum(ch_engine* engine, float* out, int32_t bands);

int32_t ch_engine_eq_band_count(void);
int32_t ch_engine_set_eq_gains(ch_engine* engine, const float* gains_db, int32_t count);
int32_t ch_engine_set_band_gain(ch_engine* engine, int32_t band, float db);

const char* ch_engine_title(ch_engine* engine);
const char* ch_engine_artist(ch_engine* engine);
const char* ch_engine_album(ch_engine* engine);

/* Etiquetas adicionales y acceso generico ("" si no existe). */
const char* ch_engine_tag(ch_engine* engine, const char* key);
const char* ch_engine_date(ch_engine* engine);
const char* ch_engine_genre(ch_engine* engine);
const char* ch_engine_composer(ch_engine* engine);
int32_t     ch_engine_track_number(ch_engine* engine);
int32_t     ch_engine_disc_number(ch_engine* engine);
/* Devuelve la carátula embebida (JPEG/PNG) o NULL; escribe el tamaño en bytes. */
const uint8_t* ch_engine_cover(ch_engine* engine, uint64_t* size);
/* Numero de caratulas embebidas en la pista audible. */
int32_t ch_engine_cover_count(ch_engine* engine);
/* Caratula `index` (0 = primera) de la pista audible; NULL si no existe. */
const uint8_t* ch_engine_cover_at(ch_engine* engine, int32_t index, uint64_t* size);

/* Letra sincronizada (LRC) buscada junto al audio (.lrc con el mismo nombre). */
int32_t ch_engine_lyrics_count(ch_engine* engine);
/* Copia la linea activa en `out` (UTF-8). Devuelve bytes escritos o -1. */
int32_t ch_engine_lyric_line(ch_engine* engine, char* out, uint32_t out_size);

double ch_engine_position(ch_engine* engine);
double ch_engine_duration(ch_engine* engine);
double ch_engine_sample_rate(ch_engine* engine);
int32_t ch_engine_channels(ch_engine* engine);
int32_t ch_engine_is_playing(ch_engine* engine);

/*
 * Eventos de reproduccion (sondeo sin callbacks, seguro desde el hilo de UI).
 * `ch_engine_poll_event` devuelve 1 y llena `out` si hay evento, 0 si la cola
 * esta vacia, o -1 si el motor es NULL. La cola guarda 63 eventos; si se llena,
 * se descarta el mas antiguo.
 *
 * kind = CH_EVENT_STATE: a = 1 reproduciendo / 0 en pausa o fin.
 * kind = CH_EVENT_TRACK: a = indice de pista, b = numero de pistas en la cola.
 * kind = CH_EVENT_QUEUE: a = numero de pistas en la cola.
 * kind = CH_EVENT_END:   fin natural de la cola (no se emite al pausar).
 */
typedef struct ch_event {
    int32_t kind;
    int32_t a;
    int32_t b;
    double  value;
} ch_event;

#define CH_EVENT_STATE 1
#define CH_EVENT_TRACK 2
#define CH_EVENT_QUEUE 3
#define CH_EVENT_END   4
#define CH_EVENT_SLEEP 5

int32_t ch_engine_poll_event(ch_engine* engine, ch_event* out);

const char* ch_engine_last_error(ch_engine* engine);

/* Estadisticas de b\u00fafer para diagnostico. */
double ch_engine_buffered_seconds(ch_engine* engine);
uint64_t ch_engine_buffer_underflows(ch_engine* engine);

/* Detecta silencio al principio/fin de un archivo (dBFS). lead/tail en segundos. */
int32_t ch_engine_detect_silence(const char* utf8_path, float threshold_db, double* lead, double* tail);

/* Biblioteca de audio: escaneo incremental de carpetas (handle opaco void*). */
void*     ch_library_create(void);
void      ch_library_destroy(void* lib);
int32_t   ch_library_scan(void* lib, const char* root);
int32_t   ch_library_count(const void* lib);
const char* ch_library_path(const void* lib, int32_t index);
int32_t   ch_library_removed(const void* lib);

/* Marcadores por pista (marcas de posicion persistentes). */
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

#ifdef __cplusplus
}
#endif
