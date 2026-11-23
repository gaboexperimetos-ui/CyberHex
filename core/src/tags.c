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
    if (n == 0) return 0;
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
/* MP4 / M4A / ALAC: arbol de atomos (boxes)                                 */
/* ------------------------------------------------------------------------- */

static uint16_t rd_u16be(const unsigned char* p) {
    return (uint16_t)(((uint16_t)p[0] << 8) | (uint16_t)p[1]);
}

static void wr_u16be(unsigned char* p, uint16_t v) {
    p[0] = (unsigned char)((v >> 8) & 0xFF);
    p[1] = (unsigned char)(v & 0xFF);
}

static uint32_t rd_u32be(const unsigned char* p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static void wr_u32be(unsigned char* p, uint32_t v) {
    p[0] = (unsigned char)((v >> 24) & 0xFF);
    p[1] = (unsigned char)((v >> 16) & 0xFF);
    p[2] = (unsigned char)((v >> 8) & 0xFF);
    p[3] = (unsigned char)(v & 0xFF);
}

static uint64_t rd_u64be(const unsigned char* p) {
    return ((uint64_t)rd_u32be(p) << 32) | (uint64_t)rd_u32be(p + 4);
}

static void wr_u64be(unsigned char* p, uint64_t v) {
    wr_u32be(p, (uint32_t)((v >> 32) & 0xFFFFFFFFu));
    wr_u32be(p + 4, (uint32_t)(v & 0xFFFFFFFFu));
}

/* Emite una caja completa (tamano 32 bits + tipo + cuerpo) en `out`. */
static int emit_box(buf* out, const char* type, const void* body, size_t blen) {
    if ((uint64_t)blen + 8 > 0xFFFFFFFFull) return -1;
    unsigned char hdr[8];
    wr_u32be(hdr, (uint32_t)(blen + 8));
    memcpy(hdr + 4, type, 4);
    if (buf_append(out, hdr, 8) != 0) return -1;
    if (blen) return buf_append(out, body, blen);
    return 0;
}

/* Caja `data`: version/flags (indicador de tipo) + locale + carga. */
static int emit_data(buf* out, uint32_t type_ind, const void* payload, size_t len) {
    buf b = {0};
    unsigned char head[8];
    wr_u32be(head, type_ind);
    wr_u32be(head + 4, 0);
    if (buf_append(&b, head, 8) != 0 ||
        (len && buf_append(&b, payload, len) != 0)) {
        free(b.data);
        return -1;
    }
    int rc = emit_box(out, "data", b.data, b.len);
    free(b.data);
    return rc;
}

/* Caja "full" con version/flags a cero y texto (mean, name...). */
static int emit_full_text(buf* out, const char* type, const char* text) {
    buf b = {0};
    unsigned char z[4] = {0, 0, 0, 0};
    if (buf_append(&b, z, 4) != 0 ||
        (text && *text && buf_append(&b, text, strlen(text)) != 0)) {
        free(b.data);
        return -1;
    }
    int rc = emit_box(out, type, b.data, b.len);
    free(b.data);
    return rc;
}

static void up_key(const char* key, char* out, size_t cap) {
    size_t i = 0;
    for (; key[i] && i + 1 < cap; i++) {
        char c = key[i];
        out[i] = (c >= 'a' && c <= 'z') ? (char)(c - 32) : c;
    }
    out[i] = 0;
}

/* Nombres de caja (4 bytes; el caracter de copyright es 0xA9, no UTF-8). */
static const char MP4_NAM[4] = {(char)0xA9, 'n', 'a', 'm'};
static const char MP4_ART[4] = {(char)0xA9, 'A', 'R', 'T'};
static const char MP4_ALB[4] = {(char)0xA9, 'a', 'l', 'b'};
static const char MP4_AART[4] = {'a', 'A', 'R', 'T'};
static const char MP4_GEN[4] = {(char)0xA9, 'g', 'e', 'n'};
static const char MP4_DAY[4] = {(char)0xA9, 'd', 'a', 'y'};
static const char MP4_CMT[4] = {(char)0xA9, 'c', 'm', 't'};
static const char MP4_WRT[4] = {(char)0xA9, 'w', 'r', 't'};
static const char MP4_TRKN[4] = {'t', 'r', 'k', 'n'};
static const char MP4_DISK[4] = {'d', 'i', 's', 'k'};
static const char MP4_TMPO[4] = {'t', 'm', 'p', 'o'};
static const char MP4_FREE[4] = {'-', '-', '-', '-'};

/* Tipo de valor: 0 texto, 1 par (pista/disco), 2 entero, 3 freeform. */
static int mp4_map(const char* key, char* name_out4) {
    const char* name = NULL;
    int kind = 3;
    if (strcasecmp(key, "TITLE") == 0) { name = MP4_NAM; kind = 0; }
    else if (strcasecmp(key, "ARTIST") == 0) { name = MP4_ART; kind = 0; }
    else if (strcasecmp(key, "ALBUM") == 0) { name = MP4_ALB; kind = 0; }
    else if (strcasecmp(key, "ALBUMARTIST") == 0) { name = MP4_AART; kind = 0; }
    else if (strcasecmp(key, "GENRE") == 0) { name = MP4_GEN; kind = 0; }
    else if (strcasecmp(key, "DATE") == 0 || strcasecmp(key, "YEAR") == 0) { name = MP4_DAY; kind = 0; }
    else if (strcasecmp(key, "COMMENT") == 0) { name = MP4_CMT; kind = 0; }
    else if (strcasecmp(key, "COMPOSER") == 0) { name = MP4_WRT; kind = 0; }
    else if (strcasecmp(key, "TRACK") == 0) { name = MP4_TRKN; kind = 1; }
    else if (strcasecmp(key, "DISC") == 0) { name = MP4_DISK; kind = 1; }
    else if (strcasecmp(key, "BPM") == 0) { name = MP4_TMPO; kind = 2; }
    if (!name) name = MP4_FREE;
    memcpy(name_out4, name, 4);
    return kind;
}

static int mp4_freeform_matches(const unsigned char* p, size_t n, const char* up) {
    size_t pos = 0;
    size_t want = strlen(up);
    while (pos + 8 <= n) {
        uint64_t sz = rd_u32be(p + pos);
        size_t h = 8;
        if (sz == 1) {
            if (pos + 16 > n) break;
            sz = rd_u64be(p + pos + 8);
            h = 16;
        } else if (sz == 0) {
            sz = n - pos;
        }
        if (sz < h || pos + sz > n) break;
        if (memcmp(p + pos + 4, "name", 4) == 0) {
            size_t bl = (size_t)sz - h;
            const unsigned char* body = p + pos + h;
            size_t off = (bl >= 4) ? 4 : 0;
            size_t sl = bl - off;
            if (sl == want) {
                int eq = 1;
                for (size_t i = 0; i < sl; i++) {
                    unsigned char a = body[off + i];
                    unsigned char b = (unsigned char)up[i];
                    if (a >= 'A' && a <= 'Z') a = (unsigned char)(a + 32);
                    if (b >= 'A' && b <= 'Z') b = (unsigned char)(b + 32);
                    if (a != b) { eq = 0; break; }
                }
                return eq;
            }
            return 0;
        }
        pos += (size_t)sz;
    }
    return 0;
}

static int mp4_emit_item(buf* out, const char* name4, int kind, const char* key,
                         const char* value) {
    buf item = {0};
    int rc = 0;
    if (kind == 0) {
        rc = emit_data(&item, 0x00000001u, value, strlen(value));
    } else if (kind == 1) {
        unsigned long a = 0, b = 0;
        const char* slash = strchr(value, '/');
        a = strtoul(value, NULL, 10);
        if (slash) b = strtoul(slash + 1, NULL, 10);
        unsigned char pay[8] = {0, 0, 0, 0, 0, 0, 0, 0};
        wr_u16be(pay + 2, (uint16_t)a);
        wr_u16be(pay + 4, (uint16_t)b);
        rc = emit_data(&item, 0x00000000u, pay, sizeof pay);
    } else if (kind == 2) {
        long v = strtol(value, NULL, 10);
        if (v < 0) v = 0;
        if (v > 65535) v = 65535;
        unsigned char pay[2];
        wr_u16be(pay, (uint16_t)v);
        rc = emit_data(&item, 0x00000015u, pay, sizeof pay);
    } else {
        char up[128];
        up_key(key, up, sizeof up);
        if (emit_full_text(&item, "mean", "com.apple.iTunes") != 0 ||
            emit_full_text(&item, "name", up) != 0 ||
            emit_data(&item, 0x00000001u, value, strlen(value)) != 0) {
            rc = -1;
        }
    }
    if (rc == 0) rc = emit_box(out, name4, item.data, item.len);
    free(item.data);
    return rc;
}

/* Reconstruye `ilst` conservando los items salvo el de `key`. */
static int mp4_build_ilst(const unsigned char* old, size_t old_len,
                          const char* key, const char* value, buf* out) {
    char name4[4];
    int kind = mp4_map(key, name4);
    char up[128];
    up_key(key, up, sizeof up);
    buf items = {0};
    size_t pos = 0;
    while (pos + 8 <= old_len) {
        uint64_t sz = rd_u32be(old + pos);
        size_t h = 8;
        if (sz == 1) {
            if (pos + 16 > old_len) break;
            sz = rd_u64be(old + pos + 8);
            h = 16;
        } else if (sz == 0) {
            sz = old_len - pos;
        }
        if (sz < h || pos + sz > old_len) break;
        const char* itype = (const char*)(old + pos + 4);
        int drop = 0;
        if (kind == 3) {
            if (memcmp(itype, "----", 4) == 0 &&
                mp4_freeform_matches(old + pos + h, (size_t)sz - h, up)) {
                drop = 1;
            }
        } else if (memcmp(itype, name4, 4) == 0) {
            drop = 1;
        }
        if (!drop) {
            if (buf_append(&items, old + pos, (size_t)sz) != 0) goto fail;
        }
        pos += (size_t)sz;
    }
    if (value) {
        if (mp4_emit_item(&items, name4, kind, key, value) != 0) goto fail;
    }
    {
        int rc = emit_box(out, "ilst", items.data, items.len);
        free(items.data);
        return rc;
    }
fail:
    free(items.data);
    return -1;
}

static int mp4_box_size(const unsigned char* p, size_t avail, uint64_t* size, size_t* hdr) {
    if (avail < 8) return -1;
    uint64_t s = rd_u32be(p);
    size_t h = 8;
    if (s == 1) {
        if (avail < 16) return -1;
        s = rd_u64be(p + 8);
        h = 16;
        if (s < 16) return -1;
    } else if (s == 0) {
        s = avail;
    }
    if (s < h || s > avail) return -1;
    *size = s;
    *hdr = h;
    return 0;
}

static int mp4_emit_mdir_hdlr(buf* out) {
    unsigned char body[25];
    memset(body, 0, sizeof body);
    memcpy(body + 8, "mdir", 4);
    memcpy(body + 12, "appl", 4);
    return emit_box(out, "hdlr", body, sizeof body);
}

/* Busca el `ilst` dentro de moov (moov/udta/meta/ilst). */
static int mp4_scan_ilst(const unsigned char* p, size_t n, int meta_mode,
                         const unsigned char** out, size_t* outlen) {
    size_t pos = 0;
    if (meta_mode) {
        pos = 4;
        if (n >= 8) {
            uint32_t first = rd_u32be(p);
            if (!(p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 0) &&
                first >= 8 && (size_t)first <= n) {
                pos = 0;
            }
        }
    }
    while (pos + 8 <= n) {
        uint64_t sz; size_t h;
        if (mp4_box_size(p + pos, n - pos, &sz, &h) != 0) break;
        const char* t = (const char*)(p + pos + 4);
        if (meta_mode) {
            if (memcmp(t, "ilst", 4) == 0) {
                *out = p + pos;
                *outlen = (size_t)sz;
                return 1;
            }
        } else if (memcmp(t, "udta", 4) == 0) {
            if (mp4_scan_ilst(p + pos + h, (size_t)sz - h, 0, out, outlen)) return 1;
        } else if (memcmp(t, "meta", 4) == 0) {
            if (mp4_scan_ilst(p + pos + h, (size_t)sz - h, 1, out, outlen)) return 1;
        }
        pos += (size_t)sz;
    }
    return 0;
}

static int mp4_rebuild_meta(const unsigned char* p, size_t n, const buf* ilst, buf* out) {
    unsigned char ff[4] = {0, 0, 0, 0};
    size_t cstart = 4;
    int has_fullbox = 1;
    if (p && n >= 8) {
        uint32_t first = rd_u32be(p);
        if (!(p[0] == 0 && p[1] == 0 && p[2] == 0 && p[3] == 0) &&
            first >= 8 && (size_t)first <= n) {
            cstart = 0;
            has_fullbox = 0;
        }
    }
    if (has_fullbox && p && n >= 4) memcpy(ff, p, 4);

    buf kids = {0};
    int has_hdlr = 0, has_ilst = 0;
    size_t pos = cstart;
    while (p && pos + 8 <= n) {
        uint64_t sz; size_t h;
        if (mp4_box_size(p + pos, n - pos, &sz, &h) != 0) break;
        const char* t = (const char*)(p + pos + 4);
        if (memcmp(t, "ilst", 4) == 0) {
            has_ilst = 1;
            if (buf_append(&kids, ilst->data, ilst->len) != 0) goto fail;
        } else {
            if (memcmp(t, "hdlr", 4) == 0) has_hdlr = 1;
            if (buf_append(&kids, p + pos, (size_t)sz) != 0) goto fail;
        }
        pos += (size_t)sz;
    }
    if (!has_hdlr) {
        buf tmp = {0};
        if (mp4_emit_mdir_hdlr(&tmp) != 0 ||
            buf_append(&tmp, kids.data, kids.len) != 0) {
            free(tmp.data);
            goto fail;
        }
        free(kids.data);
        kids = tmp;
    }
    if (!has_ilst) {
        if (buf_append(&kids, ilst->data, ilst->len) != 0) goto fail;
    }
    {
        buf body = {0};
        if (buf_append(&body, ff, 4) != 0 ||
            buf_append(&body, kids.data, kids.len) != 0) {
            free(body.data);
            goto fail;
        }
        int rc = emit_box(out, "meta", body.data, body.len);
        free(body.data);
        free(kids.data);
        return rc;
    }
fail:
    free(kids.data);
    return -1;
}

static int mp4_rebuild_udta(const unsigned char* p, size_t n, const buf* ilst, buf* out) {
    buf kids = {0};
    int has_meta = 0;
    size_t pos = 0;
    while (p && pos + 8 <= n) {
        uint64_t sz; size_t h;
        if (mp4_box_size(p + pos, n - pos, &sz, &h) != 0) break;
        const char* t = (const char*)(p + pos + 4);
        if (memcmp(t, "meta", 4) == 0) {
            has_meta = 1;
            if (mp4_rebuild_meta(p + pos + h, (size_t)sz - h, ilst, &kids) != 0) goto fail;
        } else {
            if (buf_append(&kids, p + pos, (size_t)sz) != 0) goto fail;
        }
        pos += (size_t)sz;
    }
    if (!has_meta) {
        if (mp4_rebuild_meta(NULL, 0, ilst, &kids) != 0) goto fail;
    }
    {
        int rc = emit_box(out, "udta", kids.data, kids.len);
        free(kids.data);
        return rc;
    }
fail:
    free(kids.data);
    return -1;
}

static int mp4_rebuild_moov(const unsigned char* body, size_t n, const buf* ilst, buf* out) {
    buf kids = {0};
    int has_udta = 0;
    size_t pos = 0;
    while (pos + 8 <= n) {
        uint64_t sz; size_t h;
        if (mp4_box_size(body + pos, n - pos, &sz, &h) != 0) break;
        const char* t = (const char*)(body + pos + 4);
        if (memcmp(t, "udta", 4) == 0) {
            has_udta = 1;
            if (mp4_rebuild_udta(body + pos + h, (size_t)sz - h, ilst, &kids) != 0) goto fail;
        } else {
            if (buf_append(&kids, body + pos, (size_t)sz) != 0) goto fail;
        }
        pos += (size_t)sz;
    }
    if (!has_udta) {
        if (mp4_rebuild_udta(NULL, 0, ilst, &kids) != 0) goto fail;
    }
    {
        int rc = emit_box(out, "moov", kids.data, kids.len);
        free(kids.data);
        return rc;
    }
fail:
    free(kids.data);
    return -1;
}

static int is_mp4_container(const char* t) {
    return memcmp(t, "moov", 4) == 0 || memcmp(t, "trak", 4) == 0 ||
           memcmp(t, "mdia", 4) == 0 || memcmp(t, "minf", 4) == 0 ||
           memcmp(t, "stbl", 4) == 0;
}

/* Suma `delta` a las tablas de offsets de trozos (stco/co64). */
static int adjust_chunk_offsets(unsigned char* p, size_t n, int64_t delta) {
    size_t pos = 0;
    while (pos + 8 <= n) {
        uint64_t sz = rd_u32be(p + pos);
        size_t h = 8;
        if (sz == 1) {
            if (pos + 16 > n) return -1;
            sz = rd_u64be(p + pos + 8);
            h = 16;
            if (sz < 16) return -1;
        } else if (sz == 0) {
            sz = n - pos;
        }
        if (sz < h || pos + sz > n) return -1;
        unsigned char* body = p + pos + h;
        size_t bl = (size_t)sz - h;
        const char* t = (const char*)(p + pos + 4);
        if (memcmp(t, "stco", 4) == 0) {
            if (bl < 8) return -1;
            uint32_t cnt = rd_u32be(body + 4);
            if (8 + (uint64_t)cnt * 4 > bl) return -1;
            for (uint32_t i = 0; i < cnt; i++) {
                uint32_t v = rd_u32be(body + 8 + (size_t)i * 4);
                int64_t nv = (int64_t)v + delta;
                if (nv < 0 || nv > 0xFFFFFFFFll) return -1;
                wr_u32be(body + 8 + (size_t)i * 4, (uint32_t)nv);
            }
        } else if (memcmp(t, "co64", 4) == 0) {
            if (bl < 8) return -1;
            uint32_t cnt = rd_u32be(body + 4);
            if (8 + (uint64_t)cnt * 8 > bl) return -1;
            for (uint32_t i = 0; i < cnt; i++) {
                uint64_t v = rd_u64be(body + 8 + (size_t)i * 8);
                int64_t nv = (int64_t)v + delta;
                if (nv < 0) return -1;
                wr_u64be(body + 8 + (size_t)i * 8, (uint64_t)nv);
            }
        } else if (is_mp4_container(t)) {
            if (adjust_chunk_offsets(body, bl, delta) != 0) return -1;
        }
        pos += (size_t)sz;
    }
    return 0;
}

static int mp4_ext_ok(const char* path) {
    static const char* const exts[] = {".m4a", ".m4b", ".m4p", ".m4v", ".mp4", ".alac"};
    size_t pl = strlen(path);
    for (size_t i = 0; i < sizeof exts / sizeof exts[0]; i++) {
        size_t el = strlen(exts[i]);
        if (pl >= el && strcasecmp(path + pl - el, exts[i]) == 0) return 1;
    }
    return 0;
}

int32_t ch_tags_mp4_set(const char* path, const char* key, const char* value) {
    if (!path || !key) return -1;
    if (!mp4_ext_ok(path)) return -1;

    uint64_t fsize = 0;
    char* raw = ch_file_read_all(path, &fsize);
    if (!raw) return -1;
    const unsigned char* d = (const unsigned char*)raw;

    uint64_t moff = 0, msize = 0, mdatoff = 0;
    int have_moov = 0, have_mdat = 0;
    size_t pos = 0;
    while (pos + 8 <= (size_t)fsize) {
        uint64_t sz; size_t h;
        if (mp4_box_size(d + pos, (size_t)fsize - pos, &sz, &h) != 0) break;
        const char* t = (const char*)(d + pos + 4);
        if (!have_moov && memcmp(t, "moov", 4) == 0) {
            moff = pos;
            msize = sz;
            have_moov = 1;
        } else if (!have_mdat && memcmp(t, "mdat", 4) == 0) {
            mdatoff = pos;
            have_mdat = 1;
        }
        pos += (size_t)sz;
    }
    if (!have_moov || msize < 8) {
        ch_file_free(raw);
        return -1;
    }
    (void)mdatoff;

    const unsigned char* ilst_p = NULL;
    size_t ilst_len = 0;
    int has_ilst = mp4_scan_ilst(d + moff + 8, (size_t)msize - 8, 0, &ilst_p, &ilst_len);
    const unsigned char* old_items = NULL;
    size_t old_items_len = 0;
    if (has_ilst && ilst_len >= 8) {
        old_items = ilst_p + 8;
        old_items_len = ilst_len - 8;
    }

    buf new_ilst = {0};
    if (mp4_build_ilst(old_items, old_items_len, key, value, &new_ilst) != 0) {
        ch_file_free(raw);
        return -1;
    }

    buf new_moov = {0};
    if (mp4_rebuild_moov(d + moff + 8, (size_t)msize - 8, &new_ilst, &new_moov) != 0) {
        free(new_ilst.data);
        ch_file_free(raw);
        return -1;
    }
    free(new_ilst.data);

    int64_t delta = (int64_t)new_moov.len - (int64_t)msize;
    if (have_mdat && moff < mdatoff && delta != 0) {
        if (delta < -0x7fffffffLL || delta > 0x7fffffffLL) {
            free(new_moov.data);
            ch_file_free(raw);
            return -1;
        }
        if (adjust_chunk_offsets((unsigned char*)new_moov.data + 8, new_moov.len - 8,
                                 delta) != 0) {
            free(new_moov.data);
            ch_file_free(raw);
            return -1;
        }
    }

    buf out = {0};
    if (buf_append(&out, d, (size_t)moff) != 0 ||
        buf_append(&out, new_moov.data, new_moov.len) != 0 ||
        buf_append(&out, d + moff + msize, (size_t)(fsize - (moff + msize))) != 0) {
        free(new_moov.data);
        free(out.data);
        ch_file_free(raw);
        return -1;
    }
    free(new_moov.data);
    ch_file_free(raw);

    int32_t rc = ch_file_write_atomic(path, out.data, (uint64_t)out.len);
    free(out.data);
    return rc == 0 ? 0 : -1;
}

/* ------------------------------------------------------------------------- */
/* ID3v2.3 reutilizable (MP3, AAC/ADTS, chunk ID3 de AIFF)                   */
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

/* Construye una etiqueta ID3v2.3 completa fusionando `old` (si hay) y
 * sustituyendo/borrando `key`. Escribe en `out`. */
static int id3_merge(const unsigned char* old, size_t old_len, const char* key,
                     const char* value, buf* out) {
    const char* frame = id3_frame_for(key);
    int is_txxx = (frame == NULL);
    char txxx_key[128];
    if (is_txxx) {
        size_t klen = strlen(key);
        if (klen == 0 || klen >= sizeof txxx_key) return -1;
        up_key(key, txxx_key, sizeof txxx_key);
        frame = "TXXX";
    }
    int del = (value == NULL);

    unsigned char* frame_buf = NULL;
    size_t total_frame = 0;
    if (!del) {
        size_t text_len = strlen(value);
        size_t key_len = is_txxx ? strlen(txxx_key) : 0;
        size_t frame_size = 1 + key_len + (is_txxx ? 1 : 0) + text_len;
        total_frame = 10 + frame_size;
        frame_buf = malloc(total_frame);
        if (!frame_buf) return -1;
        memcpy(frame_buf, frame, 4);
        wr_syncsafe(frame_buf + 4, (uint32_t)frame_size);
        frame_buf[8] = 0;
        frame_buf[9] = 0;
        frame_buf[10] = 0x00;
        size_t at = 11;
        if (is_txxx) {
            memcpy(frame_buf + at, txxx_key, key_len);
            at += key_len;
            frame_buf[at++] = 0x00;
        }
        if (text_len > 0) memcpy(frame_buf + at, value, text_len);
    }

    buf frames = {0};
    if (old && old_len >= 10 && memcmp(old, "ID3", 3) == 0) {
        size_t limit = 10 + (size_t)rd_syncsafe(old + 6);
        if (limit > old_len) limit = old_len;
        size_t pos = 10;
        if ((old[5] & 0x40) && pos + 4 <= limit) {
            uint32_t ext = ((uint32_t)old[pos] << 24) | ((uint32_t)old[pos + 1] << 16) |
                           ((uint32_t)old[pos + 2] << 8) | (uint32_t)old[pos + 3];
            pos += 4 + (size_t)ext;
        }
        while (pos + 10 <= limit) {
            if (old[pos] == 0) break;
            uint32_t fsz = rd_syncsafe(old + pos + 4);
            size_t ftotal = 10 + (size_t)fsz;
            if (pos + ftotal > limit) break;
            int drop = 0;
            if (memcmp(old + pos, frame, 4) == 0) {
                drop = 1;
                if (is_txxx && fsz >= 1) {
                    const unsigned char* body = old + pos + 10;
                    const unsigned char enc = body[0];
                    size_t kl = 0;
                    while (kl + 1 < fsz && !(body[1 + kl] == 0 && enc == 0)) kl++;
                    size_t want = strlen(txxx_key);
                    if (kl != want || memcmp(body + 1, txxx_key, want) != 0) drop = 0;
                }
            }
            if (!drop) {
                if (buf_append(&frames, old + pos, ftotal) != 0) goto fail;
            }
            pos += ftotal;
        }
    }
    if (!del && buf_append(&frames, frame_buf, total_frame) != 0) goto fail;
    free(frame_buf);
    frame_buf = NULL;

    unsigned char hdr[7];
    hdr[0] = 0x03;
    hdr[1] = 0x00;
    hdr[2] = 0x00;
    wr_syncsafe(hdr + 3, (uint32_t)frames.len);
    if (buf_append(out, "ID3", 3) != 0) goto fail;
    if (buf_append(out, hdr, 7) != 0) goto fail;
    if (buf_append(out, frames.data, frames.len) != 0) goto fail;
    free(frames.data);
    return 0;
fail:
    free(frame_buf);
    free(frames.data);
    return -1;
}

static int32_t id3_file_set(const char* path, const char* key, const char* value,
                            const char* ext) {
    if (!path || !key) return -1;
    size_t plen = strlen(path), elen = strlen(ext);
    if (plen < elen || strcasecmp(path + plen - elen, ext) != 0) return -1;

    uint64_t fsize = 0;
    char* raw = ch_file_read_all(path, &fsize);
    if (!raw) return -1;
    const unsigned char* d = (const unsigned char*)raw;

    size_t audio_start = 0;
    int has_id3 = (fsize >= 10 && memcmp(d, "ID3", 3) == 0);
    if (has_id3) {
        audio_start = 10 + (size_t)rd_syncsafe(d + 6);
        if (audio_start > (size_t)fsize) audio_start = (size_t)fsize;
    }

    buf tag = {0};
    if (id3_merge(has_id3 ? d : NULL, has_id3 ? audio_start : 0, key, value, &tag) != 0) {
        ch_file_free(raw);
        return -1;
    }

    buf out = {0};
    if (buf_append(&out, tag.data, tag.len) != 0) {
        free(tag.data);
        ch_file_free(raw);
        return -1;
    }
    free(tag.data);
    if (audio_start < (size_t)fsize) {
        if (buf_append(&out, d + audio_start, (size_t)fsize - audio_start) != 0) {
            free(out.data);
            ch_file_free(raw);
            return -1;
        }
    }
    ch_file_free(raw);

    int32_t rc = ch_file_write_atomic(path, out.data, (uint64_t)out.len);
    free(out.data);
    return rc == 0 ? 0 : -1;
}

int32_t ch_tags_mp3_set(const char* path, const char* key, const char* value) {
    return id3_file_set(path, key, value, ".mp3");
}

int32_t ch_tags_aac_set(const char* path, const char* key, const char* value) {
    return id3_file_set(path, key, value, ".aac");
}

/* ------------------------------------------------------------------------- */
/* AIFF / AIFC: chunk 'ID3 ' dentro de FORM                                  */
/* ------------------------------------------------------------------------- */

static int aiff_ext_ok(const char* path) {
    static const char* const exts[] = {".aiff", ".aif", ".aifc"};
    size_t pl = strlen(path);
    for (size_t i = 0; i < sizeof exts / sizeof exts[0]; i++) {
        size_t el = strlen(exts[i]);
        if (pl >= el && strcasecmp(path + pl - el, exts[i]) == 0) return 1;
    }
    return 0;
}

int32_t ch_tags_aiff_set(const char* path, const char* key, const char* value) {
    if (!path || !key) return -1;
    if (!aiff_ext_ok(path)) return -1;

    uint64_t fsize = 0;
    char* raw = ch_file_read_all(path, &fsize);
    if (!raw) return -1;
    const unsigned char* d = (const unsigned char*)raw;
    if (fsize < 12 || memcmp(d, "FORM", 4) != 0 ||
        (memcmp(d + 8, "AIFF", 4) != 0 && memcmp(d + 8, "AIFC", 4) != 0)) {
        ch_file_free(raw);
        return -1;
    }

    uint64_t form_size = rd_u32be(d + 4);
    size_t limit = 8 + (size_t)form_size;
    if (limit > (size_t)fsize) limit = (size_t)fsize;

    const unsigned char* id3 = NULL;
    size_t id3len = 0;
    size_t pos = 12;
    while (pos + 8 <= limit) {
        uint32_t sz = rd_u32be(d + pos + 4);
        size_t ctotal = 8 + (size_t)sz;
        if (pos + ctotal > limit) break;
        if (memcmp(d + pos, "ID3 ", 4) == 0) {
            id3 = d + pos + 8;
            id3len = sz;
        }
        pos += ctotal + (sz & 1);
    }

    buf tag = {0};
    if (id3_merge(id3, id3len, key, value, &tag) != 0) {
        ch_file_free(raw);
        return -1;
    }

    buf out = {0};
    unsigned char form_hdr[8];
    memcpy(form_hdr, "FORM", 4);
    wr_u32be(form_hdr + 4, 0);
    if (buf_append(&out, form_hdr, 8) != 0 ||
        buf_append(&out, d + 8, 4) != 0) {
        free(tag.data);
        free(out.data);
        ch_file_free(raw);
        return -1;
    }

    pos = 12;
    while (pos + 8 <= limit) {
        uint32_t sz = rd_u32be(d + pos + 4);
        size_t ctotal = 8 + (size_t)sz;
        if (pos + ctotal > limit) break;
        if (memcmp(d + pos, "ID3 ", 4) != 0) {
            if (buf_append(&out, d + pos, ctotal) != 0) goto fail;
            if ((sz & 1) && pos + ctotal < limit) {
                if (buf_append(&out, d + pos + ctotal, 1) != 0) goto fail;
            }
        }
        pos += ctotal + (sz & 1);
    }

    {
        unsigned char chunk_hdr[8];
        memcpy(chunk_hdr, "ID3 ", 4);
        wr_u32be(chunk_hdr + 4, (uint32_t)tag.len);
        if (buf_append(&out, chunk_hdr, 8) != 0 ||
            buf_append(&out, tag.data, tag.len) != 0) {
            goto fail;
        }
        if (tag.len & 1) {
            unsigned char z = 0;
            if (buf_append(&out, &z, 1) != 0) goto fail;
        }
    }

    wr_u32be((unsigned char*)out.data + 4, (uint32_t)(out.len - 8));
    free(tag.data);
    ch_file_free(raw);
    {
        int32_t rc = ch_file_write_atomic(path, out.data, (uint64_t)out.len);
        free(out.data);
        return rc == 0 ? 0 : -1;
    }
fail:
    free(tag.data);
    free(out.data);
    ch_file_free(raw);
    return -1;
}
