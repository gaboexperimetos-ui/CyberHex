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

/* ¿La linea "KEY=valor" corresponde a `key`? (sin distinguir mayusculas). */
static int comment_key_is(const unsigned char* line, uint32_t len, const char* key) {
    size_t klen = strlen(key);
    size_t eq = 0;
    while (eq < len && line[eq] != '=') eq++;
    if (eq != klen) return 0;
    for (size_t j = 0; j < klen; j++) {
        unsigned char a = line[j];
        unsigned char b = (unsigned char)key[j];
        if (a >= 'A' && a <= 'Z') a = (unsigned char)(a + 32);
        if (b >= 'A' && b <= 'Z') b = (unsigned char)(b + 32);
        if (a != b) return 0;
    }
    return 1;
}

/* Construye un bloque VORBIS_COMMENT conservando los comentarios existentes
 * salvo el que coincide con `key`, que se sustituye por el nuevo valor. */
static char* build_comment_block_merged(const unsigned char* old_body,
                                        uint32_t old_len, const char* key,
                                        const char* value, size_t* out_len) {
    buf v = {0};
    const unsigned char* vendor = (const unsigned char*)"CyberHex";
    uint32_t vend_len = 8;
    const unsigned char* p = NULL;
    const unsigned char* end = NULL;
    uint32_t ncomments = 0;

    if (old_body && old_len >= 8) {
        uint32_t vl = rd_u32le(old_body);
        if (4 + (size_t)vl + 4 <= old_len) {
            vendor = old_body + 4;
            vend_len = vl;
            ncomments = rd_u32le(old_body + 4 + vl);
            p = old_body + 8 + vl;
            end = old_body + old_len;
        }
    }

    if (buf_u32le(&v, vend_len) != 0) goto fail;
    if (buf_append(&v, vendor, vend_len) != 0) goto fail;
    size_t count_pos = v.len;
    if (buf_u32le(&v, 0) != 0) goto fail;

    uint32_t kept = 0;
    if (p) {
        for (uint32_t i = 0; i < ncomments; i++) {
            if (p + 4 > end) break;
            uint32_t l = rd_u32le(p);
            p += 4;
            if (p + l > end) break;
            if (!comment_key_is(p, l, key)) {
                if (buf_u32le(&v, l) != 0) goto fail;
                if (buf_append(&v, p, l) != 0) goto fail;
                kept++;
            }
            p += l;
        }
    }
    if (add_comment(&v, key, value) != 0) goto fail;
    kept++;
    wr_u32le((unsigned char*)v.data + count_pos, kept);

    size_t total = 4 + v.len;
    unsigned char* out = malloc(total);
    if (!out) goto fail;
    out[0] = 0x04;
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
    const unsigned char* vc_body = NULL;
    uint32_t vc_len = 0;
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
            /* VORBIS_COMMENT existente: recordar para conservar el resto. */
            vc_body = d + body;
            vc_len = len;
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
    char* vblock = build_comment_block_merged(vc_body, vc_len, key, value, &vlen);
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
/* ------------------------------------------------------------------------- */
/* ID3v2.3 para MP3                                                          */
/* ------------------------------------------------------------------------- */

static const char* id3_frame_for(const char* key) {
    if (strcasecmp(key, "TITLE") == 0) return "TIT2";
    if (strcasecmp(key, "ARTIST") == 0) return "TPE1";
    if (strcasecmp(key, "ALBUM") == 0) return "TALB";
    if (strcasecmp(key, "GENRE") == 0) return "TCON";
    if (strcasecmp(key, "YEAR") == 0 || strcasecmp(key, "DATE") == 0) return "TYER";
    if (strcasecmp(key, "TRACK") == 0) return "TRCK";
    return NULL;
}

/* Sincroniza el tamano de un frame ID3 (4 bytes, syncsafe). */
static void wr_syncsafe(unsigned char* p, uint32_t v) {
    p[0] = (unsigned char)((v >> 21) & 0x7F);
    p[1] = (unsigned char)((v >> 14) & 0x7F);
    p[2] = (unsigned char)((v >> 7) & 0x7F);
    p[3] = (unsigned char)(v & 0x7F);
}

static uint32_t rd_syncsafe(const unsigned char* p) {
    return ((uint32_t)(p[0] & 0x7F) << 21) | ((uint32_t)(p[1] & 0x7F) << 14) |
           ((uint32_t)(p[2] & 0x7F) << 7) | (uint32_t)(p[3] & 0x7F);
}

int32_t ch_tags_mp3_set(const char* path, const char* key, const char* value) {
    if (!path || !key) return -1;
    size_t plen = strlen(path);
    if (plen < 4 || strcasecmp(path + plen - 4, ".mp3") != 0) return -1;
    const char* frame = id3_frame_for(key);
    if (!frame) return -2;

    uint64_t fsize = 0;
    char* raw = ch_file_read_all(path, &fsize);
    if (!raw) return -1;
    const unsigned char* d = (const unsigned char*)raw;

    /* Localizar el final del tag ID3v2 existente (si hay). */
    size_t audio_start = 0;
    int has_id3 = (fsize >= 10 && memcmp(d, "ID3", 3) == 0);
    if (has_id3) {
        audio_start = 10 + (size_t)rd_syncsafe(d + 6);
        if (audio_start > (size_t)fsize) audio_start = (size_t)fsize;
    }

    /* Frame de texto nuevo: encoding 0x00 (ISO-8859-1) + texto. */
    size_t text_len = value ? strlen(value) : 0;
    size_t frame_size = 1 + text_len;
    size_t total_frame = 10 + frame_size;
    unsigned char* frame_buf = malloc(total_frame);
    if (!frame_buf) {
        ch_file_free(raw);
        return -1;
    }
    memcpy(frame_buf, frame, 4);
    wr_syncsafe(frame_buf + 4, (uint32_t)frame_size);
    frame_buf[8] = 0;
    frame_buf[9] = 0;
    frame_buf[10] = 0x00;
    if (text_len > 0) memcpy(frame_buf + 11, value, text_len);

    /* Copiar los frames existentes salvo el que se va a sustituir. */
    buf frames = {0};
    if (has_id3) {
        size_t pos = 10;
        size_t limit = audio_start;
        /* Cabecera extendida (flag 0x40 en v2.3). */
        if ((d[5] & 0x40) && pos + 4 <= limit) {
            uint32_t ext = ((uint32_t)d[pos] << 24) | ((uint32_t)d[pos + 1] << 16) |
                           ((uint32_t)d[pos + 2] << 8) | (uint32_t)d[pos + 3];
            pos += 4 + (size_t)ext;
        }
        while (pos + 10 <= limit) {
            if (d[pos] == 0) break; /* relleno */
            uint32_t fsz = rd_syncsafe(d + pos + 4);
            size_t ftotal = 10 + (size_t)fsz;
            if (pos + ftotal > limit) break;
            if (memcmp(d + pos, frame, 4) != 0) {
                if (buf_append(&frames, d + pos, ftotal) != 0) {
                    free(frames.data);
                    free(frame_buf);
                    ch_file_free(raw);
                    return -1;
                }
            }
            pos += ftotal;
        }
    }
    if (buf_append(&frames, frame_buf, total_frame) != 0) {
        free(frames.data);
        free(frame_buf);
        ch_file_free(raw);
        return -1;
    }
    free(frame_buf);

    /* Reconstruir: cabecera ID3v2.3 + frames + audio. */
    buf out = {0};
    if (buf_append(&out, "ID3", 3) != 0) goto fail;
    unsigned char hdr[7];
    hdr[0] = 0x03;
    hdr[1] = 0x00;
    hdr[2] = 0x00;
    wr_syncsafe(hdr + 3, (uint32_t)frames.len);
    if (buf_append(&out, hdr, 7) != 0) goto fail;
    if (buf_append(&out, frames.data, frames.len) != 0) goto fail;
    free(frames.data);
    frames.data = NULL;

    if (audio_start < (size_t)fsize) {
        if (buf_append(&out, d + audio_start, (size_t)fsize - audio_start) != 0) goto fail;
    }
    ch_file_free(raw);
    int32_t rc = ch_file_write_atomic(path, out.data, (uint64_t)out.len);
    free(out.data);
    return rc == 0 ? 0 : -1;

fail:
    free(frames.data);
    ch_file_free(raw);
    free(out.data);
    return -1;
}
