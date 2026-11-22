#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Escaneo de sonoridad y picos de un archivo (independiente del motor).
 *
 * Sonoridad integrada segun ITU-R BS.1770-4 (K-weighting, bloques de 400 ms
 * con solape del 75%, puerta absoluta -70 LUFS y relativa -10 LU). Sirve para
 * calcular un ReplayGain propio cuando el archivo no trae etiquetas.
 */

typedef struct {
    double integrated_lufs;
    double sample_peak_dbfs;
    double duration_s;
} ch_loudness_result;

/* Escanea `path` y rellena `out`. Devuelve 0 si ok, -1 si no se pudo leer. */
int32_t ch_loudness_scan(const char* path, ch_loudness_result* out);

/* Picos de forma de onda: maximo por cubo en [0..1]. `buckets` salidas.
 * Devuelve 0 si ok, -1 si no se pudo leer. */
int32_t ch_waveform_peaks(const char* path, uint32_t buckets, float* out_max);

/* Estima el tempo (BPM) por autocorrelacion de la envolvente de energia.
 * Devuelve 0 si ok, -1 si no se pudo leer, -3 si la pista es demasiado corta. */
int32_t ch_bpm_detect(const char* path, double* out_bpm);

/* Mide el rango dinamico (DR) con bloques de 3 s.
 * Devuelve 0 si ok, -1 si no se pudo leer, -3 si no hay bloques validos. */
int32_t ch_dr_measure(const char* path, double* out_dr, uint32_t* out_blocks);

#ifdef __cplusplus
}
#endif