#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Letras sincronizadas (formato LRC).
 * Un archivo LRC es texto UTF-8 con lineas de la forma:
 *
 *   [ar:Artista]              (metadatos opcionales)
 *   [ti:Titulo]
 *   [offset:+120]             (desplazamiento global en ms)
 *   [00:12.34]Primer verso
 *   [00:12.34][01:05.00]Verso con dos marcas de tiempo
 *
 * La libreria no depende de nada externo: solo libc.
 */

typedef struct ch_lyrics ch_lyrics;

/* Parsea una letra LRC desde una cadena UTF-8. Devuelve NULL si esta vacia
 * o no tiene ninguna linea con marca de tiempo. */
ch_lyrics* ch_lyrics_parse(const char* text);

/* Lee y parsea un archivo LRC. Devuelve NULL si no se puede abrir. */
ch_lyrics* ch_lyrics_read_file(const char* path);

/* Libera una letra devuelta por ch_lyrics_parse/read_file. */
void ch_lyrics_free(ch_lyrics* lyrics);

/* Numero de lineas con marca de tiempo. */
int32_t ch_lyrics_count(const ch_lyrics* lyrics);

/* Devuelve el texto (UTF-8, valido hasta ch_lyrics_free) de la linea activa en
 * `time_s`, y su instante de inicio en `line_start`. Si no hay linea activa,
 * devuelve NULL. `index` recibe el indice de la linea (puede ser NULL). */
const char* ch_lyrics_line_at(const ch_lyrics* lyrics, double time_s,
                              double* line_start, int32_t* index);

/* Metadatos del LRC ([ar:], [ti:], [al:], [by:]); cadena vacia si no existen.
 * Validos hasta ch_lyrics_free. */
const char* ch_lyrics_artist(const ch_lyrics* lyrics);
const char* ch_lyrics_title(const ch_lyrics* lyrics);
const char* ch_lyrics_album(const ch_lyrics* lyrics);
const char* ch_lyrics_offset_ms(const ch_lyrics* lyrics);

#ifdef __cplusplus
}
#endif