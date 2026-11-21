#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Lectura y escritura de listas de reproducción (M3U/M3U8 y PLS).
 * Las rutas relativas se resuelven respecto al directorio del archivo.
 */

typedef struct {
    char** items;
    int32_t count;
} ch_playlist;

/* Lee una lista. Si falla, items = NULL y count = -1. */
ch_playlist ch_playlist_read(const char* path);

/* Libera la memoria de una lista devuelta por ch_playlist_read. */
void ch_playlist_free(ch_playlist* playlist);

/* Escribe un M3U8 con `count` rutas. Devuelve 0 si tuvo éxito. */
int32_t ch_playlist_write(const char* path, const char* const* items, int32_t count);

#ifdef __cplusplus
}
#endif
