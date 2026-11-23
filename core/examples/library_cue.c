/**
 * @file library_cue.c
 * @brief Ejemplo de escaneo de biblioteca y lectura de CUE sheets.
 *
 * Compilar:
 *   cc -std=c23 -I../include library_cue.c -lcyberhex_core -o library_cue
 */

#include <stdio.h>
#include <stdlib.h>
#include "cyberhex_core.h"

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "Uso: %s <directorio_musica> [archivo.cue]\n", argv[0]);
        return 1;
    }

    /* Escanear biblioteca */
    void* lib = ch_library_create();
    if (!lib) return 1;

    printf("Escaneando %s...\n", argv[1]);
    int32_t added = ch_library_scan(lib, argv[1], NULL, 0);
    printf("Añadidas %d pistas\n", added);
    printf("Total en biblioteca: %d\n", ch_library_count(lib));

    /* Buscar */
    int32_t count = 0;
    int32_t* idxs = ch_library_search(lib, "beatles", &count);
    if (idxs) {
        printf("Resultados para 'beatles': %d\n", count);
        for (int32_t i = 0; i < count && i < 5; i++) {
            printf("  %s\n", ch_library_path(lib, idxs[i]));
        }
        ch_file_free(idxs);
    }

    /* CUE sheet (si se proporciona) */
    if (argc >= 3) {
        ch_cue* cue = ch_cue_read(argv[2]);
        if (cue) {
            printf("\nCUE: %s - %s\n",
                   ch_cue_album(cue), ch_cue_album_performer(cue));
            for (int32_t i = 0; i < ch_cue_count(cue); i++) {
                printf("  %02d. %s - %s (%.2fs)\n",
                       ch_cue_number(cue, i),
                       ch_cue_performer(cue, i),
                       ch_cue_title(cue, i),
                       ch_cue_start(cue, i));
            }
            ch_cue_free(cue);
        } else {
            printf("Error leyendo CUE\n");
        }
    }

    ch_library_destroy(lib);
    return 0;
}