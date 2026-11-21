#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*ch_render_fn)(void* user, float* out, uint32_t frames);

void* ch_audio_create(ch_render_fn render, void* user, uint32_t sample_rate, uint32_t channels);
void ch_audio_destroy(void* audio);
int32_t ch_audio_start(void* audio);
int32_t ch_audio_stop(void* audio);

typedef struct ch_decoder ch_decoder;

ch_decoder* ch_decoder_open(const char* path, uint32_t sample_rate, uint32_t channels);
uint64_t ch_decoder_read(ch_decoder* decoder, float* out, uint64_t frames);
void ch_decoder_close(ch_decoder* decoder);

const char* ch_audio_last_error(void);

#ifdef __cplusplus
}
#endif
