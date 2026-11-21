#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "cue.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct {
    char* file;
    char* title;
    char* performer;
    double start;
    int32_t number;
} cue_track;

struct ch_cue {
    cue_track* tracks;
    int32_t count;
    int32_t cap;
    char* album;
    char* album_performer;
    char* current_file;
};

static char* dup_string(const char* s) {
    const size_t n = strlen(s);
    char* out = malloc(n + 1);
    if (out == NULL) return NULL;
    memcpy(out, s, n + 1);
    return out;
}

static void trim(char* s) {
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == '\r' || s[n - 1] == '\n' || s[n - 1] == ' ' || s[n - 1] == '\t')) {
        s[--n] = '\0';
    }
    char* p = s;
    while (*p == ' ' || *p == '\t') p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
}

/* Quita comillas envolventes si las hay. */
static char* unquote(char* s) {
    const size_t n = strlen(s);
    if (n >= 2 && s[0] == '"' && s[n - 1] == '"') {
        s[n - 1] = '\0';
        return s + 1;
    }
    return s;
}

static char* resolve(const char* dir, const char* file) {
    if (file == NULL || file[0] == '\0') return NULL;
    if (file[0] == '/') return dup_string(file);
    const size_t need = strlen(dir) + 1 + strlen(file) + 1;
    char* out = malloc(need);
    if (out == NULL) return NULL;
    snprintf(out, need, "%s/%s", dir, file);
    return out;
}

/* "mm:ss:ff" (75 frames por segundo) -> segundos; <0 si invalido. */
static double parse_time(const char* s) {
    int mm = 0, ss = 0, ff = 0;
    if (sscanf(s, "%d:%d:%d", &mm, &ss, &ff) != 3) return -1.0;
    if (mm < 0 || ss < 0 || ss >= 60 || ff < 0 || ff >= 75) return -1.0;
    return (double)mm * 60.0 + (double)ss + (double)ff / 75.0;
}

static int32_t ensure_cap(ch_cue* c) {
    if (c->count < c->cap) return 0;
    int32_t next = c->cap ? c->cap * 2 : 16;
    cue_track* grown = realloc(c->tracks, (size_t)next * sizeof(cue_track));
    if (grown == NULL) return -1;
    c->tracks = grown;
    c->cap = next;
    return 0;
}

ch_cue* ch_cue_read(const char* path) {
    if (path == NULL) return NULL;
    FILE* f = fopen(path, "r");
    if (f == NULL) return NULL;

    ch_cue* c = calloc(1, sizeof(ch_cue));
    if (c == NULL) {
        fclose(f);
        return NULL;
    }

    /* Carpeta del .cue para resolver FILE. */
    char dir[4096];
    const char* slash = strrchr(path, '/');
    if (slash == NULL) {
        snprintf(dir, sizeof dir, ".");
    } else {
        const size_t n0 = (size_t)(slash - path);
        const size_t n = n0 >= sizeof dir ? sizeof dir - 1 : n0;
        memcpy(dir, path, n);
        dir[n] = '\0';
        if (n == 0) snprintf(dir, sizeof dir, "/");
    }

    char line[4096];
    int in_track = 0;
    cue_track* cur = NULL;

    while (fgets(line, sizeof line, f) != NULL) {
        trim(line);
        if (line[0] == '\0') continue;

        char keyword[32] = {0};
        const char* rest = line;
        if (sscanf(line, "%31s", keyword) != 1) continue;
        rest = line + strlen(keyword);
        while (*rest == ' ' || *rest == '\t') rest++;

        if (strcasecmp(keyword, "FILE") == 0) {
            /* FILE "nombre.ext" WAVE */
            char name[2048] = {0};
            if (sscanf(rest, "\"%2047[^\"]\"", name) == 1 || sscanf(rest, "%2047s", name) == 1) {
                free(c->current_file);
                c->current_file = resolve(dir, name);
            }
        } else if (strcasecmp(keyword, "TRACK") == 0) {
            int number = 0;
            if (sscanf(rest, "%d", &number) != 1) continue;
            if (ensure_cap(c) != 0) break;
            cur = &c->tracks[c->count];
            memset(cur, 0, sizeof *cur);
            cur->number = number;
            cur->start = -1.0;
            cur->file = dup_string(c->current_file ? c->current_file : "");
            c->count++;
            in_track = 1;
        } else if (strcasecmp(keyword, "TITLE") == 0) {
            char* value = unquote((char*)rest);
            if (in_track && cur != NULL) {
                free(cur->title);
                cur->title = dup_string(value);
            } else if (c->album == NULL) {
                c->album = dup_string(value);
            }
        } else if (strcasecmp(keyword, "PERFORMER") == 0) {
            char* value = unquote((char*)rest);
            if (in_track && cur != NULL) {
                free(cur->performer);
                cur->performer = dup_string(value);
            } else if (c->album_performer == NULL) {
                c->album_performer = dup_string(value);
            }
        } else if (strcasecmp(keyword, "INDEX") == 0) {
            int index = 0;
            char timecode[64] = {0};
            if (in_track && cur != NULL &&
                sscanf(rest, "%d %63s", &index, timecode) == 2 && index == 1) {
                const double t = parse_time(timecode);
                if (t >= 0.0) cur->start = t;
            }
        }
    }
    fclose(f);
    free(c->current_file);
    c->current_file = NULL;

    /* Descartar pistas sin INDEX 01. */
    int32_t w = 0;
    for (int32_t i = 0; i < c->count; i++) {
        if (c->tracks[i].start < 0.0) {
            free(c->tracks[i].file);
            free(c->tracks[i].title);
            free(c->tracks[i].performer);
            continue;
        }
        if (w != i) c->tracks[w] = c->tracks[i];
        w++;
    }
    c->count = w;

    if (c->count == 0) {
        ch_cue_free(c);
        return NULL;
    }
    return c;
}

void ch_cue_free(ch_cue* c) {
    if (c == NULL) return;
    for (int32_t i = 0; i < c->count; i++) {
        free(c->tracks[i].file);
        free(c->tracks[i].title);
        free(c->tracks[i].performer);
    }
    free(c->tracks);
    free(c->album);
    free(c->album_performer);
    free(c);
}

int32_t ch_cue_count(const ch_cue* c) {
    return c ? c->count : 0;
}

const char* ch_cue_album(const ch_cue* c) {
    return (c && c->album) ? c->album : "";
}

const char* ch_cue_album_performer(const ch_cue* c) {
    return (c && c->album_performer) ? c->album_performer : "";
}

const char* ch_cue_file(const ch_cue* c, int32_t index) {
    if (!c || index < 0 || index >= c->count || c->tracks[index].file == NULL) return "";
    return c->tracks[index].file;
}

const char* ch_cue_title(const ch_cue* c, int32_t index) {
    if (!c || index < 0 || index >= c->count || c->tracks[index].title == NULL) return "";
    return c->tracks[index].title;
}

const char* ch_cue_performer(const ch_cue* c, int32_t index) {
    if (!c || index < 0 || index >= c->count || c->tracks[index].performer == NULL) return "";
    return c->tracks[index].performer;
}

double ch_cue_start(const ch_cue* c, int32_t index) {
    if (!c || index < 0 || index >= c->count) return -1.0;
    return c->tracks[index].start;
}

double ch_cue_end(const ch_cue* c, int32_t index) {
    if (!c || index < 0 || index >= c->count) return -1.0;
    if (index + 1 < c->count) return c->tracks[index + 1].start;
    return -1.0;
}

int32_t ch_cue_number(const ch_cue* c, int32_t index) {
    if (!c || index < 0 || index >= c->count) return -1;
    return c->tracks[index].number;
}
