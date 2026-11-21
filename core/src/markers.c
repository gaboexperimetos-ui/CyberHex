#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "markers.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

typedef struct {
    char* track;
    double position;
    char* name;
} marker;

struct ch_markers {
    marker* items;
    int32_t count;
    int32_t cap;
};

static char* dup_or_empty(const char* s) {
    if (s == NULL || s[0] == '\0') {
        char* empty = malloc(1);
        if (empty != NULL) empty[0] = '\0';
        return empty;
    }
    const size_t len = strlen(s);
    char* copy = malloc(len + 1);
    if (copy != NULL) memcpy(copy, s, len + 1);
    return copy;
}

/* Escapa \\, \t y \n para escribir una linea. */
static void write_escaped(FILE* f, const char* s) {
    for (; *s != '\0'; s++) {
        switch (*s) {
            case '\\': fputs("\\\\", f); break;
            case '\t': fputs("\\t", f); break;
            case '\n': fputs("\\n", f); break;
            case '\r': fputs("\\r", f); break;
            default: fputc(*s, f); break;
        }
    }
}

/* Desescapa en sitio y devuelve `s`. */
static char* unescape(char* s) {
    char* out = s;
    for (char* in = s; *in != '\0'; in++) {
        if (*in == '\\' && in[1] != '\0') {
            in++;
            switch (*in) {
                case 't': *out++ = '\t'; break;
                case 'n': *out++ = '\n'; break;
                case 'r': *out++ = '\r'; break;
                default: *out++ = *in; break;
            }
        } else {
            *out++ = *in;
        }
    }
    *out = '\0';
    return s;
}

static int32_t ensure_cap(ch_markers* m, int32_t want) {
    if (want <= m->cap) return 0;
    int32_t next = m->cap ? m->cap : 32;
    while (next < want) next *= 2;
    marker* grown = realloc(m->items, (size_t)next * sizeof(marker));
    if (grown == NULL) return -1;
    m->items = grown;
    m->cap = next;
    return 0;
}

ch_markers* ch_markers_create(void) {
    return calloc(1, sizeof(ch_markers));
}

void ch_markers_destroy(ch_markers* m) {
    if (m == NULL) return;
    for (int32_t i = 0; i < m->count; i++) {
        free(m->items[i].track);
        free(m->items[i].name);
    }
    free(m->items);
    free(m);
}

int32_t ch_markers_load(ch_markers* m, const char* path) {
    if (m == NULL || path == NULL) return -1;
    FILE* f = fopen(path, "r");
    if (f == NULL) return 0; /* inexistente: almacen vacio, no es error */

    char* line = NULL;
    size_t cap = 0;
    ssize_t n;
    while ((n = getline(&line, &cap, f)) > 0) {
        while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r')) line[--n] = '\0';
        if (n == 0) continue;

        char* first = strchr(line, '\t');
        if (first == NULL) continue;
        char* second = strchr(first + 1, '\t');
        if (second == NULL) continue;

        *first = '\0';
        *second = '\0';
        const double pos = strtod(first + 1, NULL);

        if (ensure_cap(m, m->count + 1) != 0) break;
        char* track = dup_or_empty(unescape(line));
        char* name = dup_or_empty(unescape(second + 1));
        if (track == NULL || name == NULL) {
            free(track);
            free(name);
            break;
        }
        m->items[m->count].track = track;
        m->items[m->count].position = pos;
        m->items[m->count].name = name;
        m->count++;
    }
    free(line);
    fclose(f);
    return 0;
}

int32_t ch_markers_save(const ch_markers* m, const char* path) {
    if (m == NULL || path == NULL) return -1;

    char temp[4096];
    const int written = snprintf(temp, sizeof temp, "%s.tmp", path);
    if (written <= 0 || (size_t)written >= sizeof temp) return -1;

    FILE* f = fopen(temp, "w");
    if (f == NULL) return -1;
    for (int32_t i = 0; i < m->count; i++) {
        write_escaped(f, m->items[i].track);
        fputc('\t', f);
        fprintf(f, "%.6f", m->items[i].position);
        fputc('\t', f);
        write_escaped(f, m->items[i].name);
        fputc('\n', f);
    }
    if (fclose(f) != 0) {
        remove(temp);
        return -1;
    }
    if (rename(temp, path) != 0) {
        remove(temp);
        return -1;
    }
    return 0;
}

int32_t ch_markers_add(ch_markers* m, const char* track, double position,
                       const char* name) {
    if (m == NULL || track == NULL || !(position >= 0.0)) return -1;
    if (ensure_cap(m, m->count + 1) != 0) return -1;
    char* tcopy = dup_or_empty(track);
    char* ncopy = dup_or_empty(name);
    if (tcopy == NULL || ncopy == NULL) {
        free(tcopy);
        free(ncopy);
        return -1;
    }
    m->items[m->count].track = tcopy;
    m->items[m->count].position = position;
    m->items[m->count].name = ncopy;
    return m->count++;
}

/* Indice fisico de la marca `index` de `track`, o -1. */
static int32_t find(const ch_markers* m, const char* track, int32_t index) {
    if (m == NULL || track == NULL || index < 0) return -1;
    int32_t seen = 0;
    for (int32_t i = 0; i < m->count; i++) {
        if (strcmp(m->items[i].track, track) != 0) continue;
        if (seen == index) return i;
        seen++;
    }
    return -1;
}

int32_t ch_markers_count(const ch_markers* m, const char* track) {
    if (m == NULL || track == NULL) return 0;
    int32_t n = 0;
    for (int32_t i = 0; i < m->count; i++) {
        if (strcmp(m->items[i].track, track) == 0) n++;
    }
    return n;
}

double ch_markers_position(const ch_markers* m, const char* track, int32_t index) {
    const int32_t i = find(m, track, index);
    return i < 0 ? -1.0 : m->items[i].position;
}

const char* ch_markers_name(const ch_markers* m, const char* track, int32_t index) {
    const int32_t i = find(m, track, index);
    return i < 0 ? "" : m->items[i].name;
}

int32_t ch_markers_remove(ch_markers* m, const char* track, int32_t index) {
    const int32_t i = find(m, track, index);
    if (i < 0) return -1;
    free(m->items[i].track);
    free(m->items[i].name);
    for (int32_t j = i; j + 1 < m->count; j++) m->items[j] = m->items[j + 1];
    m->count--;
    return 0;
}

int32_t ch_markers_clear(ch_markers* m, const char* track) {
    if (m == NULL || track == NULL) return 0;
    int32_t w = 0;
    int32_t removed = 0;
    for (int32_t i = 0; i < m->count; i++) {
        if (strcmp(m->items[i].track, track) == 0) {
            free(m->items[i].track);
            free(m->items[i].name);
            removed++;
            continue;
        }
        if (w != i) m->items[w] = m->items[i];
        w++;
    }
    m->count = w;
    return removed;
}
