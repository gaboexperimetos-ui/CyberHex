#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Escritura de etiquetas (tags).
 *
 * `key` es el nombre del campo (TITLE, ARTIST, ALBUM, ...). `value` puede ser
 * NULL para borrar el campo. Cada funcion solo soporta su formato y devuelve
 * 0 si ok, negativo si no se pudo.
 *
 * Al escribir se conservan el resto de campos del archivo: solo se sustituye
 * (o borra) la clave indicada.
 */

/* FLAC: bloque VORBIS_COMMENT. Solo archivos .flac. */
int32_t ch_tags_set(const char* path, const char* key, const char* value);

/* MP3: frame de texto en ID3v2.3. Solo archivos .mp3. */
int32_t ch_tags_mp3_set(const char* path, const char* key, const char* value);

/* Ogg Vorbis: paquete de comentarios del segundo paquete del flujo. */
int32_t ch_tags_ogg_set(const char* path, const char* key, const char* value);

/* Opus: paquete "OpusTags". */
int32_t ch_tags_opus_set(const char* path, const char* key, const char* value);

#ifdef __cplusplus
}
#endif