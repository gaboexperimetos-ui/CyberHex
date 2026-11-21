#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Backend de decodificación del núcleo CyberHex.
 * Dos implementaciones cumplen esta interfaz:
 *   - decode_ffmpeg.c   (Linux/PC): libavformat + libavcodec + libswresample.
 *   - decode_miniaudio.c (Android y respaldo): ma_decoder de miniaudio.
 */

typedef struct ch_decoder ch_decoder;

/* Abre `path` y prepara salida f32 entrelazada a out_rate/out_channels. */
ch_decoder* ch_decode_open(const char* path, uint32_t out_rate, uint32_t out_channels);

/* Lee hasta `frames` frames. Devuelve frames leídos; 0 significa fin de pista. */
uint64_t ch_decode_read(ch_decoder* decoder, float* out, uint64_t frames);

/* Salta al frame indicado (a la tasa de salida). Devuelve 0 si tuvo éxito. */
int32_t ch_decode_seek_frame(ch_decoder* decoder, uint64_t frame);

/* Duración en segundos, o 0 si se desconoce. */
double ch_decode_duration(ch_decoder* decoder);

/* Metadatos; cadena vacía si no existen. Válidas hasta ch_decode_close. */
const char* ch_decode_title(ch_decoder* decoder);
const char* ch_decode_artist(ch_decoder* decoder);
const char* ch_decode_album(ch_decoder* decoder);

/* Carátula embebida (JPEG/PNG); NULL si no hay. Válida hasta ch_decode_close. */
const uint8_t* ch_decode_cover(ch_decoder* decoder, uint64_t* size);

void ch_decode_close(ch_decoder* decoder);

/* Último error del backend. */
const char* ch_decode_last_error(void);

#ifdef __cplusplus
}
#endif
