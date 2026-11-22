#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Escritura de etiquetas (tags). Por ahora solo FLAC (Vorbis comments), que
 * es texto plano y seguro de editar. Devuelve 0 si ok, -1 si no se pudo.
 *
 * `key` es el nombre del campo (TITLE, ARTIST, ALBUM, ...). `value` puede ser
 * NULL para borrar el campo. Solo soporta archivos .flac.
 */
int32_t ch_tags_set(const char* path, const char* key, const char* value);

#ifdef __cplusplus
}
#endif
/* Escritura de tags ID3v2.3 para MP3 (solo texto). */
int32_t ch_tags_mp3_set(const char* path, const char* key, const char* value);
