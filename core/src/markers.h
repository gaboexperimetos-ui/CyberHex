#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Marcadores por pista (marcas de posición tipo "A", "estribillo", ...).
 *
 * El almacen es independiente del motor: se le pasan rutas de archivo y
 * posiciones en segundos. Persiste en un archivo de texto plano (una marca por
 * linea, campos separados por tabulador) para sobrevivir entre sesiones.
 */

typedef struct ch_markers ch_markers;

/* Crea un almacen vacio. NULL si no hay memoria. */
ch_markers* ch_markers_create(void);

/* Libera el almacen y todas sus marcas. */
void ch_markers_destroy(ch_markers* markers);

/* Carga las marcas de `path` (sobrescribe las actuales). Devuelve 0 si ok,
 * -1 si el archivo no se pudo abrir por otro motivo que no sea inexistente. */
int32_t ch_markers_load(ch_markers* markers, const char* path);

/* Guarda las marcas en `path`. Devuelve 0 si ok. */
int32_t ch_markers_save(const ch_markers* markers, const char* path);

/* Anade una marca a `track` en `position` segundos. `name` puede ser NULL.
 * Devuelve el indice de la marca anadida, o -1 si falla. */
int32_t ch_markers_add(ch_markers* markers, const char* track, double position,
                       const char* name);

/* Numero de marcas de `track`. */
int32_t ch_markers_count(const ch_markers* markers, const char* track);

/* Posicion (segundos) de la marca `index`, o -1.0 si no existe. */
double ch_markers_position(const ch_markers* markers, const char* track,
                           int32_t index);

/* Nombre de la marca `index` ("" si no existe). Valido hasta modificarla. */
const char* ch_markers_name(const ch_markers* markers, const char* track,
                            int32_t index);

/* Elimina la marca `index` de `track`. Devuelve 0 si ok. */
int32_t ch_markers_remove(ch_markers* markers, const char* track, int32_t index);

/* Elimina todas las marcas de `track`. Devuelve cuantas borro. */
int32_t ch_markers_clear(ch_markers* markers, const char* track);

#ifdef __cplusplus
}
#endif
