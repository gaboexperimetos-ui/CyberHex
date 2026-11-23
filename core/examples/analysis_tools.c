/**
 * @file analysis_tools.c
 * @brief Ejemplo de análisis offline: LUFS, BPM, DR, key, waveform.
 *
 * Compilar:
 *   cc -std=c23 -I../include analysis_tools.c -lcyberhex_core -lm -o analysis_tools
 */

#include <stdio.h>
#include <stdlib.h>
#include "cyberhex_core.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <archivo_audio>\n", argv[0]);
        return 1;
    }

    const char* path = argv[1];

    /* Loudness (LUFS) */
    ch_loudness_result lr = {0};
    if (ch_loudness_scan(path, &lr) == 0) {
        printf("Loudness: %.2f LUFS integrated\n", lr.integrated_lufs);
        printf("True Peak: %.2f dBFS\n", lr.sample_peak_dbfs);
        printf("Duración: %.2f s\n", lr.duration_s);
    } else {
        printf("Loudness scan falló\n");
    }

    /* BPM */
    double bpm = 0;
    if (ch_bpm_detect_path(path, &bpm) == 0) {
        printf("BPM: %.1f\n", bpm);
    } else {
        printf("BPM detect falló\n");
    }

    /* Dynamic Range */
    double dr = 0;
    uint32_t blocks = 0;
    if (ch_dr_measure_path(path, &dr, &blocks) == 0) {
        printf("DR: %.2f dB (%u bloques)\n", dr, blocks);
    } else {
        printf("DR measure falló\n");
    }

    /* Key detection */
    char key[32] = {0};
    double conf = 0;
    if (ch_engine_detect_key(NULL, path, key, sizeof key, &conf) == 0) {
        printf("Tonalidad: %s (conf %.2f)\n", key, conf);
    } else {
        printf("Key detect falló\n");
    }

    /* Waveform peaks (para dibujar overview) */
    const uint32_t buckets = 200;
    float* peaks = calloc(buckets, sizeof(float));
    if (peaks && ch_waveform_peaks(path, buckets, peaks) == 0) {
        printf("Waveform peaks (primeros 10): ");
        for (uint32_t i = 0; i < 10 && i < buckets; i++) {
            printf("%.3f ", peaks[i]);
        }
        printf("\n");
        free(peaks);
    }

    /* Silencio al inicio/fin */
    double lead = 0, tail = 0;
    if (ch_engine_detect_silence(path, -50.0f, &lead, &tail) == 0) {
        printf("Silencio: lead=%.3fs tail=%.3fs\n", lead, tail);
    }

    return 0;
}