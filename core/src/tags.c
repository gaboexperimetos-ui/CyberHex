#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "tags.h"
#include "fileio.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------------- */
/* Utilidades de lectura/escritura de enteros little-endian en el buffer.    */
/* ------------------------------------------------------------------------- */

static uint32_t rd_u24be(const unsigned char* p) {
    return ((uint32_t)p[0] << 16) | ((uint32_t)p[1] << 8) | (uint32_t)p[2];
}

static void wr_u24be(unsigned char* p, uint32_t v) {
    p[0] = (unsigned char)((v >> 16) & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
    p[2] = (unsigned char)(v & 0xFF);
}

static uint32_t rd_u32le(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static void wr_u32le(unsigned char* p, uint32_t v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
    p[2] = (unsigned char)((v >> 16) & 0xFF);
    p[3] = (unsigned char)((v >> 24) & 0xFF);
}

static int is_flac(const unsigned char* d, size_t n) {
    return n >= 4 && memcmp(d, "fLaC", 4) == 0;
}

/* ------------------------------------------------------------------------- */
/* Construye un bloque METADATA_BLOCK de tipo VORBIS_COMMENT (4) con los     */
/* comentarios `KEY=value`. Devuelve un buffer malloc'd y su tamano.         */
/* ------------------------------------------------------------------------- */

typedef struct {
    char* data;
    size_t len;
    size_t cap;
} buf;

static int buf_reserve(buf* b, size_t extra) {
    if (b->len + extra <= b->cap) return 0;
    size_t next = b->cap ? b->cap : 256;
    while (next < b->len + extra) next *= 2;
    char* grown = realloc(b->data, next);
    if (!grown) return -1;
    b->data = grown;
    b->cap = next;
    return 0;
}

static int buf_append(buf* b, const void* p, size_t n) {
    if (buf_reserve(b, n) != 0) return -1;
    memcpy(b->data + b->len, p, n);
    b->len += n;
    return 0;
}

static int buf_u32le(buf* b, uint32_t v) {
    unsigned char tmp[4];
    wr_u32le(tmp, v);
    return buf_append(b, tmp, 4);
}

/* Añade un comentario "KEY=value" (longitud + bytes, sin NUL). */
static int add_comment(buf* v, const char* key, const char* value) {
    char line[8192];
    int n = snprintf(line, sizeof line, "%s=%s", key, value ? value : "");
    if (n < 0) return -1;
    if ((size_t)n >= sizeof line) return -1;
    if (buf_u32le(v, (uint32_t)n) != 0) return -1;
    return buf_append(v, line, (size_t)n);
}

/* Empaqueta el VORBIS_COMMENT en un bloque METADATA_BLOCK (cabecera + datos). */
static char* build_comment_block(const char* vendor, const char* key,
                                 const char* value, size_t* out_len) {
    buf v = {0};
    if (buf_u32le(&v, (uint32_t)strlen(vendor)) != 0) goto fail;
    if (buf_append(&v, vendor, strlen(vendor)) != 0) goto fail;
    if (buf_u32le(&v, 1) != 0) goto fail; /* 1 comentario */
    if (add_comment(&v, key, value) != 0) goto fail;

    /* Cabecera del bloque: 1 byte (last=0, tipo=4) + 3 bytes de longitud. */
    size_t total = 4 + v.len;
    unsigned char* out = malloc(total);
    if (!out) goto fail;
    out[0] = 0x04; /* no es el ultimo, tipo VORBIS_COMMENT */
    wr_u24be(out + 1, (uint32_t)v.len);
    if (v.len > 0) memcpy(out + 4, v.data, v.len);
    free(v.data);
    *out_len = total;
    return (char*)out;
fail:
    free(v.data);
    return NULL;
}

/* ------------------------------------------------------------------------- */
/* API                                                                        */
/* ------------------------------------------------------------------------- */

int32_t ch_tags_set(const char* path, const char* key, const char* value) {
    if (!path || !key) return -1;
    /* Solo FLAC por ahora. */
    size_t plen = strlen(path);
    if (plen < 5 || strcasecmp(path + plen - 5, ".flac") != 0) return -1;

    uint64_t fsize = 0;
    char* raw = ch_file_read_all(path, &fsize);
    if (!raw) return -1;
    const unsigned char* d = (const unsigned char*)raw;
    if (!is_flac(d, (size_t)fsize)) {
        ch_file_free(raw);
        return -1;
    }

    /* Saltar "fLaC" y recorrer los bloques METADATA. */
    size_t pos = 4;
    int found_vendor = 0;
    char vendor[128] = "CyberHex";
    while (pos + 4 <= (size_t)fsize) {
        unsigned char h = d[pos];
        int last = (h & 0x80) != 0;
        int type = h & 0x7F;
        uint32_t len = rd_u24be(d + pos + 1);
        size_t body = pos + 4;
        if (body + len > (size_t)fsize) break;

        if (type == 0) {
            /* STREAMINFO: no se toca. */
        } else if (type == 4) {
            /* VORBIS_COMMENT existente: extraer vendor. */
            const unsigned char* p = d + body;
            if (len >= 4) {
                uint32_t vlen = rd_u32le(p);
                if (vlen < 128 && 4 + vlen <= len) {
                    memcpy(vendor, p + 4, vlen);
                    vendor[vlen] = '\0';
                    found_vendor = 1;
                }
            }
        }
        pos = body + len;
        (void)last;
    }
    (void)found_vendor;

    /* Reconstruir: "fLaC" + STREAMINFO + [otros bloques sin VORBIS] +
     * nuevo VORBIS (marcado como ultimo) + resto de audio. */
    buf out = {0};
    if (buf_append(&out, "fLaC", 4) != 0) goto fail;

    /* Encontrar el final de los bloques metadata (el bloque con bit last). */
    pos = 4;
    size_t audio_start = (size_t)fsize;
    while (pos + 4 <= (size_t)fsize) {
        unsigned char h = d[pos];
        int last = (h & 0x80) != 0;
        uint32_t len = rd_u24be(d + pos + 1);
        pos = pos + 4 + len;
        if (last) {
            audio_start = pos;
            break;
        }
    }

    /* Copiar bloques (sin VORBIS) quitando el bit last. */
    pos = 4;
    while (pos + 4 <= audio_start) {
        unsigned char h = d[pos];
        int type = h & 0x7F;
        uint32_t len = rd_u24be(d + pos + 1);
        size_t body = pos + 4;
        if (body + len > audio_start) break;
        if (type != 4) {
            unsigned char tmp[4];
            tmp[0] = (unsigned char)(h & 0x7F); /* sin bit last */
            wr_u24be(tmp + 1, len);
            if (buf_append(&out, tmp, 4) != 0) goto fail;
            if (buf_append(&out, d + body, len) != 0) goto fail;
        }
        pos = body + len;
    }

    size_t vlen = 0;
    char* vblock = build_comment_block(vendor, key, value, &vlen);
    if (!vblock) goto fail;
    /* Marcar el VORBIS como ultimo bloque (bit 7). */
    ((unsigned char*)vblock)[0] |= 0x80;
    if (buf_append(&out, vblock, vlen) != 0) {
        free(vblock);
        goto fail;
    }
    free(vblock);

    /* Resto del archivo desde el primer frame de audio. */
    if (audio_start < (size_t)fsize) {
        if (buf_append(&out, d + audio_start, (size_t)fsize - audio_start) != 0)
            goto fail;
    }

    ch_file_free(raw);
    int32_t rc = ch_file_write_atomic(path, out.data, (uint64_t)out.len);
    free(out.data);
    return rc == 0 ? 0 : -1;

fail:
    ch_file_free(raw);
    free(out.data);
    return -1;
}