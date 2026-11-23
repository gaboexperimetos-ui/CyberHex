/**
 * @file basic_playback.c
 * @brief Ejemplo mínimo de reproducción de audio con CyberHex Core.
 *
 * Compilar:
 *   cc -std=c23 -I../include basic_playback.c -lcyberhex_core -o basic_playback
 *
 * Ejecutar:
 *   ./basic_playback /ruta/archivo.flac
 */

#include <stdio.h>
#include <stdlib.h>
#include "cyberhex_core.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <archivo_audio>\n", argv[0]);
        return 1;
    }

    printf("CyberHex %s (ABI %d)\n", ch_core_version(), ch_engine_abi_version());

    ch_engine* engine = ch_engine_create();
    if (!engine) {
        fprintf(stderr, "Error creando motor: %s\n", ch_core_last_error());
        return 1;
    }

    if (ch_engine_load(engine, argv[1]) != 0) {
        fprintf(stderr, "Error cargando archivo: %s\n", ch_engine_last_error(engine));
        ch_engine_destroy(engine);
        return 1;
    }

    printf("Reproduciendo: %s\n", ch_engine_title(engine) ?: argv[1]);
    printf("Duración: %.2f s\n", ch_engine_duration(engine));

    ch_engine_play(engine);

    /* Bucle simple: espera a que termine o el usuario pulse Enter */
    printf("Pulsa Enter para detener...\n");
    getchar();

    ch_engine_pause(engine);
    ch_engine_destroy(engine);
    return 0;
}