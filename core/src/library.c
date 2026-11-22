#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "library.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <sys/stat.h>

/* Profundidad maxima del arbol: evita recursiones infinitas (symlinks). */
#define CH_MAX_DEPTH 48

typedef struct {
    char* path;
    uint64_t hash;
    long mtime;
    int alive;
} track;

struct ch_library {
    track* items;
    int32_t count;
    int32_t cap;
    int32_t removed;
    /* Indice abierto (indices+1; 0 = libre) para que el escaneo no sea O(n^2). */
    int32_t* map;
    int32_t map_cap;
};

/* Identidad de un directorio, para detectar ciclos al seguir symlinks. */
typedef struct {
    dev_t dev;
    ino_t ino;
} dir_id;

static uint64_t fnv1a(const char* s) {
    uint64_t h = 1469598103934665603ULL;
    for (; *s != '\0'; s++) {
        h ^= (uint64_t)(unsigned char)*s;
        h *= 1099511628211ULL;
    }
    return h;
}

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

static void map_insert(ch_library* lib, int32_t index) {
    if (lib->map_cap == 0) return;
    const uint32_t mask = (uint32_t)lib->map_cap - 1u;
    uint32_t pos = (uint32_t)lib->items[index].hash & mask;
    while (lib->map[pos] != 0) pos = (pos + 1) & mask;
    lib->map[pos] = index + 1;
}

static int map_grow(ch_library* lib, int32_t want) {
    int32_t cap = 64;
    while (cap < want) cap *= 2;
    if (cap <= lib->map_cap) return 0;
    int32_t* table = calloc((size_t)cap, sizeof(int32_t));
    if (table == NULL) return -1;
    free(lib->map);
    lib->map = table;
    lib->map_cap = cap;
    for (int32_t i = 0; i < lib->count; i++) map_insert(lib, i);
    return 0;
}

static void map_rebuild(ch_library* lib) {
    if (lib->map != NULL) {
        memset(lib->map, 0, (size_t)lib->map_cap * sizeof(int32_t));
    }
    for (int32_t i = 0; i < lib->count; i++) map_insert(lib, i);
}

/* Busca una ruta por hash; devuelve su indice o -1. */
static int32_t find_track(const ch_library* lib, const char* path, uint64_t hash) {
    if (lib->map_cap == 0) return -1;
    const uint32_t mask = (uint32_t)lib->map_cap - 1u;
    uint32_t pos = (uint32_t)hash & mask;
    for (int32_t probe = 0; probe < lib->map_cap; probe++) {
        const int32_t slot = lib->map[pos];
        if (slot == 0) return -1;
        const int32_t idx = slot - 1;
        if (lib->items[idx].hash == hash && strcmp(lib->items[idx].path, path) == 0) {
            return idx;
        }
        pos = (pos + 1) & mask;
    }
    return -1;
}

static int append_track(ch_library* lib, const char* path, uint64_t hash, long mtime) {
    if (lib->count == lib->cap) {
        int32_t next = lib->cap ? lib->cap * 2 : 256;
        track* grown = realloc(lib->items, (size_t)next * sizeof(track));
        if (!grown) return -1;
        lib->items = grown;
        lib->cap = next;
    }
    /* Mantener el indice por debajo del 50% de carga. */
    if (lib->count * 2 + 8 > lib->map_cap) {
        if (map_grow(lib, (lib->count + 1) * 4) != 0) return -1;
    }
    char* copy = strdup(path);
    if (!copy) return -1;
    lib->items[lib->count].path = copy;
    lib->items[lib->count].hash = hash;
    lib->items[lib->count].mtime = mtime;
    lib->items[lib->count].alive = 1;
    map_insert(lib, lib->count);
    lib->count++;
    return 0;
}

static void scan_dir(ch_library* lib, const char* dir, dir_id* ancestors, int depth,
                     const char* const* exts, int32_t n, int* added) {
    if (depth >= CH_MAX_DEPTH) return;

    struct stat self;
    if (stat(dir, &self) != 0 || !S_ISDIR(self.st_mode)) return;
    /* Si este directorio ya esta en la cadena de padres, hay un ciclo. */
    for (int i = 0; i < depth; i++) {
        if (ancestors[i].dev == self.st_dev && ancestors[i].ino == self.st_ino) return;
    }
    ancestors[depth].dev = self.st_dev;
    ancestors[depth].ino = self.st_ino;

    DIR* d = opendir(dir);
    if (!d) return;
    struct dirent* ent;
    char sub[4096];
    while ((ent = readdir(d)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;
        const int written = snprintf(sub, sizeof sub, "%s/%s", dir, ent->d_name);
        if (written < 0 || (size_t)written >= sizeof sub) continue; /* ruta truncada */

        struct stat st;
        if (stat(sub, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            scan_dir(lib, sub, ancestors, depth + 1, exts, n, added);
        } else if (S_ISREG(st.st_mode) && has_audio_ext(sub, exts, n)) {
            const uint64_t hash = fnv1a(sub);
            const int32_t idx = find_track(lib, sub, hash);
            if (idx >= 0) {
                lib->items[idx].mtime = (long)st.st_mtime;
                lib->items[idx].alive = 1;
            } else if (append_track(lib, sub, hash, (long)st.st_mtime) == 0) {
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
    free(lib->map);
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

    dir_id ancestors[CH_MAX_DEPTH];
    int added = 0;
    scan_dir(lib, root, ancestors, 0, exts, n, &added);

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
    map_rebuild(lib);
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
/* Busca rutas que contengan `needle` (case-insensitive). Devuelve un buffer
 * con los indices (int32) encontrados y escribe el numero en `count_out`.
 * El buffer se libera con ch_file_free(). NULL si no hay coincidencias. */
int32_t* c_lib_search(const ch_library* lib, const char* needle, int32_t* count_out) {
    if (count_out) *count_out = 0;
    if (!lib || !needle || needle[0] == '\0') return NULL;

    int32_t cap = 16, n = 0;
    int32_t* out = malloc((size_t)cap * sizeof(int32_t));
    if (!out) return NULL;

    for (int32_t i = 0; i < lib->count; i++) {
        const char* p = lib->items[i].path;
        /* substring case-insensitive */
        const char* hay = p;
        size_t nl = strlen(needle);
        int match = 0;
        for (; *hay && !match; hay++) {
            size_t k = 0;
            while (k < nl && hay[k] &&
                   tolower((unsigned char)hay[k]) == tolower((unsigned char)needle[k])) {
                k++;
            }
            if (k == nl) match = 1;
        }
        if (match) {
            if (n == cap) {
                int32_t next = cap * 2;
                int32_t* grown = realloc(out, (size_t)next * sizeof(int32_t));
                if (!grown) { free(out); return NULL; }
                out = grown;
                cap = next;
            }
            out[n++] = i;
        }
    }
    if (n == 0) { free(out); return NULL; }
    if (count_out) *count_out = n;
    return out;
}

int32_t c_lib_remove(ch_library* lib, const char* path) {
    if (!lib || !path) return 0;
    for (int32_t i = 0; i < lib->count; i++) {
        if (strcmp(lib->items[i].path, path) == 0) {
            free(lib->items[i].path);
            lib->items[i] = lib->items[lib->count - 1];
            lib->count--;
            return 1;
        }
    }
    return 0;
}
