/**
 * @file playlist_eq.c
 * @brief Ejemplo de gestión de cola y ecualizador.
 *
 * Compilar:
 *   cc -std=c23 -I../include playlist_eq.c -lcyberhex_core -o playlist_eq
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cyberhex_core.h"

static void print_queue(ch_engine* e) {
    int32_t n = ch_engine_queue_count(e);
    int32_t cur = ch_engine_queue_index(e);
    for (int32_t i = 0; i < n; i++) {
        const char* p = ch_engine_queue_path(e, i);
        const char* t = ch_engine_queue_title(e, i);
        printf("  %d: %s%s\n", i, t && *t ? t : p, i == cur ? " <-- actual" : "");
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <archivo1> [archivo2...]\n", argv[0]);
        return 1;
    }

    ch_engine* e = ch_engine_create();
    if (!e) return 1;

    /* Cargar primera pista */
    ch_engine_load(e, argv[1]);

    /* Añadir el resto a la cola */
    for (int i = 2; i < argc; i++) {
        ch_engine_queue_add(e, argv[i]);
    }

    printf("Cola inicial:\n");
    print_queue(e);

    /* Configurar EQ: 10 bandas, subir graves y agudos */
    int32_t bands = ch_engine_eq_band_count();
    float* gains = calloc(bands, sizeof(float));
    if (gains) {
        gains[0] = 6.0f;   /* 60 Hz  +6 dB */
        gains[1] = 3.0f;   /* 170 Hz +3 dB */
        gains[bands - 2] = 3.0f; /* 6 kHz  +3 dB */
        gains[bands - 1] = 6.0f; /* 16 kHz +6 dB */
        ch_engine_set_eq_gains(e, gains, bands);
        free(gains);
    }

    /* Preamp para evitar clipping */
    ch_engine_set_eq_preamp(e, -6.0f);

    /* Crossfade 2 segundos */
    ch_engine_set_crossfade(e, 2.0f);

    /* Reproducir */
    ch_engine_play(e);

    /* Mostrar eventos */
    ch_event ev;
    while (ch_engine_poll_event(e, &ev) == 1) {
        if (ev.kind == CH_EVENT_TRACK) {
            printf("\nNueva pista: %d/%d\n", ev.a, ev.b);
            print_queue(e);
        }
    }

    ch_engine_destroy(e);
    return 0;
}