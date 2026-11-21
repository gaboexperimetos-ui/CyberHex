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
int32_t ch_engine_set_volume(ch_engine* engine, float volume);

/* ReplayGain: aplica la ganancia de pista si el archivo trae la etiqueta. */
int32_t ch_engine_set_replaygain(ch_engine* engine, int32_t enabled);
float   ch_engine_replaygain_gain_db(ch_engine* engine);
float   ch_engine_replaygain_peak(ch_engine* engine);

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
int32_t ch_engine_next(ch_engine* engine);
int32_t ch_engine_previous(ch_engine* engine);
int32_t ch_engine_set_gapless(ch_engine* engine, int32_t enabled);
int32_t ch_engine_gapless(ch_engine* engine);

int32_t ch_engine_eq_band_count(void);
int32_t ch_engine_set_eq_gains(ch_engine* engine, const float* gains_db, int32_t count);
int32_t ch_engine_set_band_gain(ch_engine* engine, int32_t band, float db);

const char* ch_engine_title(ch_engine* engine);
const char* ch_engine_artist(ch_engine* engine);
const char* ch_engine_album(ch_engine* engine);
/* Devuelve la carátula embebida (JPEG/PNG) o NULL; escribe el tamaño en bytes. */
const uint8_t* ch_engine_cover(ch_engine* engine, uint64_t* size);

double ch_engine_position(ch_engine* engine);
double ch_engine_duration(ch_engine* engine);
double ch_engine_sample_rate(ch_engine* engine);
int32_t ch_engine_channels(ch_engine* engine);
int32_t ch_engine_is_playing(ch_engine* engine);

const char* ch_engine_last_error(ch_engine* engine);

#ifdef __cplusplus
}
#endif
