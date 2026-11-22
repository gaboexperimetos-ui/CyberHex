#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Lista archivos de audio en un directorio (no recursivo).
 *
 * Devuelve un buffer con las rutas completas concatenadas y separadas por '\n'
 * (una por linea), y escribe el numero de archivos en `count_out`. El buffer
 * se libera con ch_file_free(). NULL si no hay archivos o error.
 *
 * `extensions` es una lista de extensiones permitidas (p. ej. ".flac", ".mp3")
 * terminada en NULL.
 */
char* ch_dir_list_audio(const char* dir, const char* const* extensions, int32_t* count_out);

#ifdef __cplusplus
}
#endif