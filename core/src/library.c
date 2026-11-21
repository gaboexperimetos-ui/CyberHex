#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "library.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct {
    char* path;
    long mtime;
    int alive;
} track;

struct ch_library {
    track* items;
    int32_t count;
    int32_t cap;
    int32_t removed;
};

static const char* default_exts[] = {
    ".flac", ".mp3", ".wav", ".ogg", ".opus", ".m4a", ".aac", ".alac",
    ".aiff", ".aif", ".wma", ".mpc", ".ape", ".wv", ".tta",
};

static int has_audio_ext(const char* path, const char* const* exts, int32_t n) {
    const char* dot = strrchr(path, '.');
    if (!dot) return 0;
    for (int32_t i = 0; i < n; i++) {
        const char* e = exts[i];
        if (e[0] == '.') e++;
        const char* a = dot + 1;
        if (strcasecmp(a, e) == 0) return 1;
    }
    return 0;
}

static int append_track(ch_library* lib, const char* path, long mtime) {
    if (lib->count == lib->cap) {
        int32_t next = lib->cap ? lib->cap * 2 : 256;
        track* grown = realloc(lib->items, (size_t)next * sizeof(track));
        if (!grown) return -1;
        lib->items = grown;
        lib->cap = next;
    }
    char* copy = strdup(path);
    if (!copy) return -1;
    lib->items[lib->count].path = copy;
    lib->items[lib->count].mtime = mtime;
    lib->items[lib->count].alive = 1;
    lib->count++;
    return 0;
}

/* Busca una ruta; devuelve su indice o -1. */
static int32_t find_track(ch_library* lib, const char* path) {
    for (int32_t i = 0; i < lib->count; i++) {
        if (strcmp(lib->items[i].path, path) == 0) return i;
    }
    return -1;
}

static void scan_dir(ch_library* lib, const char* dir,
                     const char* const* exts, int32_t n, int* added) {
    DIR* d = opendir(dir);
    if (!d) return;
    struct dirent* ent;
    char sub[4096];
    while ((ent = readdir(d)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;
        snprintf(sub, sizeof sub, "%s/%s", dir, ent->d_name);

        struct stat st;
        if (stat(sub, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            scan_dir(lib, sub, exts, n, added);
        } else if (S_ISREG(st.st_mode) && has_audio_ext(sub, exts, n)) {
            int32_t idx = find_track(lib, sub);
            if (idx >= 0) {
                lib->items[idx].mtime = (long)st.st_mtime;
                lib->items[idx].alive = 1;
            } else if (append_track(lib, sub, (long)st.st_mtime) == 0) {
                (*added)++;
            }
        }
    }
    closedir(d);
}

ch_library* c_lib_create(void) {
    return calloc(1, sizeof(ch_library));
}

void c_lib_destroy(ch_library* lib) {
    if (!lib) return;
    for (int32_t i = 0; i < lib->count; i++) free(lib->items[i].path);
    free(lib->items);
    free(lib);
}

int32_t c_lib_scan(ch_library* lib, const char* root,
                        const char* const* extensions, int32_t ext_count) {
    if (!lib || !root) return -1;
    struct stat st;
    if (stat(root, &st) != 0 || !S_ISDIR(st.st_mode)) return -1;

    const char* const* exts = extensions;
    int32_t n = ext_count;
    if (!exts || n <= 0) {
        exts = default_exts;
        n = (int32_t)(sizeof default_exts / sizeof default_exts[0]);
    }

    /* Marcar todos como no vistos; se reactivan los que sigan existiendo. */
    for (int32_t i = 0; i < lib->count; i++) lib->items[i].alive = 0;

    int added = 0;
    scan_dir(lib, root, exts, n, &added);

    /* Compactar: eliminar los que no se vieron y contar los nuevos reales. */
    int32_t w = 0;
    int32_t removed = 0;
    for (int32_t i = 0; i < lib->count; i++) {
        if (!lib->items[i].alive) {
            free(lib->items[i].path);
            removed++;
            continue;
        }
        if (w != i) lib->items[w] = lib->items[i];
        w++;
    }
    lib->count = w;
    lib->removed = removed;
    return added;
}

int32_t c_lib_count(const ch_library* lib) {
    return lib ? lib->count : 0;
}

const char* c_lib_path(const ch_library* lib, int32_t index) {
    if (!lib || index < 0 || index >= lib->count) return NULL;
    return lib->items[index].path;
}

int32_t c_lib_removed(const ch_library* lib) {
    return lib ? lib->removed : 0;
}