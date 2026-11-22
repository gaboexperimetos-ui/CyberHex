#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "dirlist.h"
#include "fileio.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

static int has_ext(const char* name, const char* const* exts) {
    const char* dot = strrchr(name, '.');
    if (!dot) return 0;
    for (int i = 0; exts[i] != NULL; i++) {
        if (strcasecmp(dot, exts[i]) == 0) return 1;
    }
    return 0;
}

char* ch_dir_list_audio(const char* dir, const char* const* extensions, int32_t* count_out) {
    if (count_out) *count_out = 0;
    if (!dir || !extensions) return NULL;

    DIR* d = opendir(dir);
    if (!d) return NULL;

    size_t cap = 4096, len = 0;
    char* out = malloc(cap);
    if (!out) {
        closedir(d);
        return NULL;
    }
    int32_t count = 0;

    struct dirent* ent;
    while ((ent = readdir(d)) != NULL) {
        const char* name = ent->d_name;
        if (name[0] == '.') continue;
        if (!has_ext(name, extensions)) continue;

        /* Comprobar que es archivo (no directorio). */
        char full[8192];
        int n = snprintf(full, sizeof full, "%s/%s", dir, name);
        if (n < 0 || (size_t)n >= sizeof full) continue;
        struct stat st;
        if (stat(full, &st) != 0 || !S_ISREG(st.st_mode)) continue;

        size_t need = (size_t)n + 2; /* ruta + \n + NUL */
        while (len + need > cap) {
            cap *= 2;
            char* grown = realloc(out, cap);
            if (!grown) {
                free(out);
                closedir(d);
                return NULL;
            }
            out = grown;
        }
        memcpy(out + len, full, (size_t)n);
        len += (size_t)n;
        out[len++] = '\n';
        count++;
    }
    closedir(d);

    if (count == 0) {
        free(out);
        return NULL;
    }
    out[len] = '\0';
    if (count_out) *count_out = count;
    return out;
}