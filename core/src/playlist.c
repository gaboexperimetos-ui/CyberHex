#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "playlist.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char* dup_string(const char* s) {
    const size_t n = strlen(s);
    char* out = malloc(n + 1);
    if (!out) return NULL;
    memcpy(out, s, n + 1);
    return out;
}

static char* base_directory(const char* path) {
    const char* slash = strrchr(path, '/');
    if (!slash) return dup_string(".");
    if (slash == path) return dup_string("/");
    const size_t n = (size_t)(slash - path);
    char* out = malloc(n + 1);
    if (!out) return NULL;
    memcpy(out, path, n);
    out[n] = '\0';
    return out;
}

static char* resolve_entry(const char* base, const char* entry) {
    while (*entry == ' ' || *entry == '\t') entry++;
    if (*entry == '\0') return NULL;
    if (*entry == '/') return dup_string(entry);

    const size_t need = strlen(base) + 1 + strlen(entry) + 1;
    char* joined = malloc(need);
    if (!joined) return NULL;
    snprintf(joined, need, "%s/%s", base, entry);

    char* canonical = realpath(joined, NULL);
    if (canonical) {
        free(joined);
        return canonical;
    }
    return joined;
}

static char* trim(char* s) {
    while (*s && isspace((unsigned char)*s)) s++;
    size_t n = strlen(s);
    while (n > 0 && isspace((unsigned char)s[n - 1])) s[--n] = '\0';
    return s;
}

static int is_pls_line(const char* line) {
    const char* eq = strchr(line, '=');
    if (!eq) return 0;
    if (strncmp(line, "File", 4) != 0) return 0;
    for (const char* p = line + 4; p < eq; p++) {
        if (!isdigit((unsigned char)*p)) return 0;
    }
    return 1;
}

static int append(ch_playlist* pl, int32_t* cap, char* item) {
    if (pl->count == *cap) {
        int32_t next = *cap ? *cap * 2 : 16;
        char** grown = realloc(pl->items, (size_t)next * sizeof(char*));
        if (!grown) return -1;
        pl->items = grown;
        *cap = next;
    }
    pl->items[pl->count++] = item;
    return 0;
}

ch_playlist ch_playlist_read(const char* path) {
    ch_playlist pl = { NULL, -1 };
    if (!path) return pl;

    FILE* f = fopen(path, "rb");
    if (!f) return pl;

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return pl;
    }
    long size = ftell(f);
    if (size < 0) {
        fclose(f);
        return pl;
    }
    rewind(f);

    char* data = malloc((size_t)size + 1);
    if (!data) {
        fclose(f);
        return pl;
    }
    size_t got = fread(data, 1, (size_t)size, f);
    fclose(f);
    data[got] = '\0';

    char* text = data;
    if (got >= 3 && (unsigned char)text[0] == 0xEF &&
        (unsigned char)text[1] == 0xBB && (unsigned char)text[2] == 0xBF) {
        text += 3;
    }

    char* base = base_directory(path);
    if (!base) {
        free(data);
        return pl;
    }

    int is_pls = 0;
    for (char* line = text; *line;) {
        char* nl = strchr(line, '\n');
        size_t len = nl ? (size_t)(nl - line) : strlen(line);
        char saved = line[len];
        line[len] = '\0';
        if (is_pls_line(line)) {
            is_pls = 1;
            line[len] = saved;
            break;
        }
        line[len] = saved;
        if (!nl) break;
        line = nl + 1;
    }

    pl.items = NULL;
    pl.count = 0;
    int32_t cap = 0;

    for (char* line = text; *line;) {
        char* nl = strchr(line, '\n');
        size_t len = nl ? (size_t)(nl - line) : strlen(line);
        char saved = line[len];
        line[len] = '\0';

        char* entry = NULL;
        if (is_pls) {
            if (is_pls_line(line)) {
                char* eq = strchr(line, '=');
                entry = eq + 1;
            }
        } else {
            char* t = trim(line);
            if (*t && *t != '#' && *t != ';') entry = t;
        }

        if (entry) {
            char* resolved = resolve_entry(base, entry);
            if (resolved) {
                if (append(&pl, &cap, resolved) != 0) {
                    free(resolved);
                    line[len] = saved;
                    break;
                }
            }
        }

        line[len] = saved;
        if (!nl) break;
        line = nl + 1;
    }

    free(base);
    free(data);
    return pl;
}

void ch_playlist_free(ch_playlist* playlist) {
    if (!playlist || !playlist->items) return;
    for (int32_t i = 0; i < playlist->count; i++) free(playlist->items[i]);
    free(playlist->items);
    playlist->items = NULL;
    playlist->count = 0;
}

int32_t ch_playlist_write(const char* path, const char* const* items, int32_t count) {
    if (!path || count < 0 || (count > 0 && !items)) return -1;
    FILE* f = fopen(path, "wb");
    if (!f) return -1;

    int failed = 0;
    if (fputs("#EXTM3U\n", f) == EOF) failed = 1;
    for (int32_t i = 0; i < count && !failed; i++) {
        if (!items[i]) continue;
        if (fputs(items[i], f) == EOF || fputc('\n', f) == EOF) failed = 1;
    }

    if (fclose(f) != 0) failed = 1;
    return failed ? -1 : 0;
}
