#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "lyrics.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    double time;      /* segundos */
    char* text;       /* UTF-8 */
} lyric_line;

struct ch_lyrics {
    lyric_line* lines;
    int32_t count;
    int32_t cap;
    char* artist;
    char* title;
    char* album;
    char* offset_ms;
};

static char* dup_range(const char* start, size_t len) {
    char* out = malloc(len + 1);
    if (!out) return NULL;
    memcpy(out, start, len);
    out[len] = '\0';
    return out;
}

/* Divide una linea por \n conservando el texto; devuelve punteros a cada linea
 * (modifica `text` poniendo '\0'). No se usa: se recorre manualmente. */

static int parse_timestamp(const char* s, const char** end, double* out) {
    /* [mm:ss.xx] o [hh:mm:ss.xx] */
    int parts[3] = { 0, 0, 0 };
    int nparts = 0;
    const char* p = s;
    while (nparts < 3) {
        if (!isdigit((unsigned char)*p)) return 0;
        int v = 0;
        while (isdigit((unsigned char)*p)) {
            v = v * 10 + (*p - '0');
            p++;
        }
        parts[nparts++] = v;
        if (*p == ':') {
            p++;
            continue;
        }
        break;
    }
    if (nparts < 2) return 0;

    double frac = 0.0;
    if (*p == '.') {
        p++;
        double scale = 0.1;
        while (isdigit((unsigned char)*p)) {
            frac += (*p - '0') * scale;
            scale *= 0.1;
            p++;
        }
    }
    if (*p != ']') return 0;
    p++;

    double total;
    if (nparts == 3) {
        total = parts[0] * 3600.0 + parts[1] * 60.0 + parts[2] + frac;
    } else {
        total = parts[0] * 60.0 + parts[1] + frac;
    }
    *out = total;
    *end = p;
    return 1;
}

static int is_metadata_tag(const char* s, size_t len) {
    /* s apunta tras '['; len = longitud hasta ']' */
    if (len >= 7 && strncmp(s, "offset:", 7) == 0) return 1;
    if (len >= 3 && s[2] == ':') {
        if (strncmp(s, "ar:", 3) == 0) return 1;
        if (strncmp(s, "ti:", 3) == 0) return 1;
        if (strncmp(s, "al:", 3) == 0) return 1;
        if (strncmp(s, "by:", 3) == 0) return 1;
    }
    return 0;
}

static void set_meta(char** field, const char* value, size_t len) {
    char* copy = dup_range(value, len);
    if (!copy) return;
    free(*field);
    *field = copy;
}

static int append_line(ch_lyrics* l, double time, const char* text, size_t len) {
    if (l->count == l->cap) {
        int32_t next = l->cap ? l->cap * 2 : 32;
        lyric_line* grown = realloc(l->lines, (size_t)next * sizeof(lyric_line));
        if (!grown) return -1;
        l->lines = grown;
        l->cap = next;
    }
    char* copy = dup_range(text, len);
    if (!copy) return -1;
    l->lines[l->count].time = time;
    l->lines[l->count].text = copy;
    l->count++;
    return 0;
}

static void handle_meta_tag(ch_lyrics* l, const char* s, size_t len) {
    /* s apunta tras '['; len = longitud hasta ']' */
    if (len >= 7 && strncmp(s, "offset:", 7) == 0) {
        set_meta(&l->offset_ms, s + 7, len - 7);
    } else if (len >= 3 && strncmp(s, "ar:", 3) == 0) {
        set_meta(&l->artist, s + 3, len - 3);
    } else if (len >= 3 && strncmp(s, "ti:", 3) == 0) {
        set_meta(&l->title, s + 3, len - 3);
    } else if (len >= 3 && strncmp(s, "al:", 3) == 0) {
        set_meta(&l->album, s + 3, len - 3);
    }
    /* [by:...] se ignora */
}

ch_lyrics* ch_lyrics_parse(const char* text) {
    if (!text) return NULL;

    ch_lyrics* l = calloc(1, sizeof(ch_lyrics));
    if (!l) return NULL;

    const char* p = text;
    while (*p) {
        const char* nl = strchr(p, '\n');
        size_t line_len = nl ? (size_t)(nl - p) : strlen(p);
        const char* line = p;

        size_t i = 0;
        while (i < line_len && (line[i] == ' ' || line[i] == '\t' || line[i] == '\r')) i++;

        if (i < line_len && line[i] == '[') {
            /* Puede haber varias marcas de tiempo seguidas: [00:12][00:15]texto */
            double times[16];
            int ntimes = 0;
            size_t cursor = i;
            int parsed_any = 0;
            while (cursor < line_len && line[cursor] == '[') {
                size_t close = cursor + 1;
                while (close < line_len && line[close] != ']') close++;
                if (close >= line_len) break;
                const char* end = NULL;
                double t = 0;
                if (parse_timestamp(line + cursor + 1, &end, &t) && end == line + close + 1) {
                    if (ntimes < 16) times[ntimes++] = t;
                    parsed_any = 1;
                    cursor = close + 1;
                    continue;
                }
                if (is_metadata_tag(line + cursor + 1, close - cursor - 1)) {
                    handle_meta_tag(l, line + cursor + 1, close - cursor - 1);
                    cursor = close + 1;
                    continue;
                }
                break;
            }

            if (parsed_any) {
                size_t text_start = cursor;
                while (text_start < line_len && (line[text_start] == ' ' || line[text_start] == '\t')) text_start++;
                size_t text_len = line_len - text_start;
                while (text_len > 0 && line[text_start + text_len - 1] == '\r') text_len--;
                for (int k = 0; k < ntimes; k++) {
                    if (append_line(l, times[k], line + text_start, text_len) != 0) {
                        ch_lyrics_free(l);
                        return NULL;
                    }
                }
            }
        }

        if (!nl) break;
        p = nl + 1;
    }

    if (l->count == 0) {
        ch_lyrics_free(l);
        return NULL;
    }
    return l;
}

ch_lyrics* ch_lyrics_read_file(const char* path) {
    if (!path) return NULL;
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long size = ftell(f);
    if (size < 0) { fclose(f); return NULL; }
    rewind(f);
    char* data = malloc((size_t)size + 1);
    if (!data) { fclose(f); return NULL; }
    size_t got = fread(data, 1, (size_t)size, f);
    fclose(f);
    data[got] = '\0';
    const char* start = data;
    if (got >= 3 && (unsigned char)start[0] == 0xEF &&
        (unsigned char)start[1] == 0xBB && (unsigned char)start[2] == 0xBF) {
        start += 3;
    }
    ch_lyrics* l = ch_lyrics_parse(start);
    free(data);
    return l;
}

void ch_lyrics_free(ch_lyrics* lyrics) {
    if (!lyrics) return;
    for (int32_t i = 0; i < lyrics->count; i++) free(lyrics->lines[i].text);
    free(lyrics->lines);
    free(lyrics->artist);
    free(lyrics->title);
    free(lyrics->album);
    free(lyrics->offset_ms);
    free(lyrics);
}

int32_t ch_lyrics_count(const ch_lyrics* lyrics) {
    return lyrics ? lyrics->count : 0;
}

const char* ch_lyrics_line_at(const ch_lyrics* lyrics, double time_s,
                              double* line_start, int32_t* index) {
    if (!lyrics || lyrics->count == 0) {
        if (line_start) *line_start = 0;
        if (index) *index = -1;
        return NULL;
    }
    /* Las lineas pueden venir desordenadas si el LRC lo estaba; se busca la
     * ultima cuyo tiempo <= time_s. */
    int32_t best = -1;
    double best_time = -1e18;
    for (int32_t i = 0; i < lyrics->count; i++) {
        double t = lyrics->lines[i].time;
        if (t <= time_s + 1e-6 && t > best_time) {
            best_time = t;
            best = i;
        }
    }
    if (best < 0) {
        if (line_start) *line_start = 0;
        if (index) *index = -1;
        return NULL;
    }
    if (line_start) *line_start = best_time;
    if (index) *index = best;
    return lyrics->lines[best].text;
}

const char* ch_lyrics_artist(const ch_lyrics* lyrics) {
    return (lyrics && lyrics->artist) ? lyrics->artist : "";
}
const char* ch_lyrics_title(const ch_lyrics* lyrics) {
    return (lyrics && lyrics->title) ? lyrics->title : "";
}
const char* ch_lyrics_album(const ch_lyrics* lyrics) {
    return (lyrics && lyrics->album) ? lyrics->album : "";
}
const char* ch_lyrics_offset_ms(const ch_lyrics* lyrics) {
    return (lyrics && lyrics->offset_ms) ? lyrics->offset_ms : "";
}

/* ------------------------------------------------------------------------- */
/* Escritura y desplazamiento                                                */
/* ------------------------------------------------------------------------- */

/* Formatea `t` (segundos) como [mm:ss.xx] o [hh:mm:ss.xx] en `out`. */
static int format_timestamp(char* out, size_t out_size, double t) {
    if (t < 0) t = 0;
    int total_cs = (int)(t * 100.0 + 0.5);
    int cs = total_cs % 100;
    int total_s = total_cs / 100;
    int s = total_s % 60;
    int total_m = total_s / 60;
    int m = total_m % 60;
    int h = total_m / 60;
    if (h > 0) {
        return snprintf(out, out_size, "[%02d:%02d:%02d.%02d]", h, m, s, cs);
    }
    return snprintf(out, out_size, "[%02d:%02d.%02d]", m, s, cs);
}

int32_t ch_lyrics_shift(ch_lyrics* lyrics, double delta_s) {
    if (!lyrics) return -1;
    for (int32_t i = 0; i < lyrics->count; i++) {
        lyrics->lines[i].time += delta_s;
        if (lyrics->lines[i].time < 0) lyrics->lines[i].time = 0;
    }
    return 0;
}

int32_t ch_lyrics_write_file(const ch_lyrics* lyrics, const char* path) {
    if (!lyrics || !path) return -1;
    FILE* f = fopen(path, "wb");
    if (!f) return -1;

    /* Metadatos primero. */
    if (lyrics->offset_ms) fprintf(f, "[offset:%s]\n", lyrics->offset_ms);
    if (lyrics->artist) fprintf(f, "[ar:%s]\n", lyrics->artist);
    if (lyrics->title) fprintf(f, "[ti:%s]\n", lyrics->title);
    if (lyrics->album) fprintf(f, "[al:%s]\n", lyrics->album);

    /* Una linea por marca de tiempo, en el orden en que estan almacenadas. */
    char ts[32];
    for (int32_t i = 0; i < lyrics->count; i++) {
        int n = format_timestamp(ts, sizeof ts, lyrics->lines[i].time);
        if (n < 0) continue;
        fprintf(f, "%s%s\n", ts, lyrics->lines[i].text);
    }
    int ok = (ferror(f) == 0);
    fclose(f);
    return ok ? 0 : -1;
}
