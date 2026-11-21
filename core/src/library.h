#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Biblioteca de audio: escaneo incremental de carpetas.
 *
 * No hay base de datos persistente propia: se mantiene en memoria una lista de
 * rutas con su mtime. Un escaneo:
 *   1. Camina la carpeta raiz buscando extensiones de audio conocidas.
 *   2. Anade los archivos nuevos.
 *   3. Marca como desaparecidos los que ya no estan.
 *
 * La lista es opaca; se consulta con ch_library_*.
 */

typedef struct ch_library ch_library;

/* Crea una biblioteca vacia. NULL si no hay memoria. */
ch_library* c_lib_create(void);

/* Libera la biblioteca y sus rutas. */
void c_lib_destroy(ch_library* lib);

/* Escanea `root` (recursivo) y actualiza la lista. `extensions` es una lista
 * de extensiones en minusculas sin punto (p.ej. {".flac",".mp3"}), o NULL para
 * usar las predeterminadas. Devuelve el numero de archivos nuevos anadidos, o
 * -1 si no se pudo abrir la raiz. */
int32_t c_lib_scan(ch_library* lib, const char* root,
                        const char* const* extensions, int32_t ext_count);

/* Numero de pistas en la biblioteca. */
int32_t c_lib_count(const ch_library* lib);

/* Ruta (UTF-8) de la pista `index`, valida hasta el siguiente escaneo. NULL si
 * el indice no existe. */
const char* c_lib_path(const ch_library* lib, int32_t index);

/* Numero de pistas que desaparecieron en el ultimo escaneo. */
int32_t c_lib_removed(const ch_library* lib);

#ifdef __cplusplus
}
#endif