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
