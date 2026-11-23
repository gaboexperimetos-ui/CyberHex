#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Lectura de hojas CUE (.cue): una imagen de audio dividida en pistas.
 *
 * El parser resuelve el FILE relativo a la carpeta del .cue y expone cada
 * TRACK con titulo, interprete, archivo y tiempos. Para reproducir una pista,
 * cargar su `file` y saltar a `start`; el fin es el `start` de la siguiente.
 */

typedef struct ch_cue ch_cue;

/* Lee `path`; NULL si no se pudo abrir o no hay pistas. */
ch_cue* ch_cue_read(const char* path);
ch_cue* ch_cue_parse(const char* text);

/* Libera la hoja. */
void ch_cue_free(ch_cue* cue);

/* Numero de pistas. */
int32_t ch_cue_count(const ch_cue* cue);

/* Album (TITLE global; "" si no hay). */
const char* ch_cue_album(const ch_cue* cue);

/* Interprete global ("" si no hay). */
const char* ch_cue_album_performer(const ch_cue* cue);

/* Archivo de audio de la pista `i` ("" si no existe). */
const char* ch_cue_file(const ch_cue* cue, int32_t index);

/* Metadatos de la pista `i` ("" si no existen). */
const char* ch_cue_title(const ch_cue* cue, int32_t index);
const char* ch_cue_performer(const ch_cue* cue, int32_t index);

/* Inicio y fin de la pista `i` en segundos. `end` es -1 en la ultima pista. */
double ch_cue_start(const ch_cue* cue, int32_t index);
double ch_cue_end(const ch_cue* cue, int32_t index);

/* Numero de pista declarado (TRACK nn), o -1. */
int32_t ch_cue_number(const ch_cue* cue, int32_t index);

#ifdef __cplusplus
}
#endif
