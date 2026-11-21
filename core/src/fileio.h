#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Lee un archivo completo en memoria (NUL terminado). Devuelve NULL si no
 * existe o no se puede leer; escribe el tamano en `size` (sin el NUL). */
char* ch_file_read_all(const char* path, uint64_t* size);

/* Libera un buffer de ch_file_read_all. */
void ch_file_free(char* data);

/* Escribe `data` en `path` de forma atomica (`.tmp` + rename). 0 si ok. */
int32_t ch_file_write_atomic(const char* path, const char* data, uint64_t size);

#ifdef __cplusplus
}
#endif
