#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "tags.h"
#include "fileio.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Escritura de etiquetas en Ogg Vorbis y Opus.
 *
 * Un fichero Ogg es una sucesion de paginas ("OggS"). El paquete de comentarios
 * (Vorbis: tipo 3 + "vorbis"; Opus: "OpusTags") es el segundo paquete del
 * flujo. Para cambiar un campo hay que reconstruir ese paquete y volver a
 * empaquetar las paginas de la cabecera, recalculando los numeros de pagina y
 * el CRC de cada pagina modificada (polinomio 0x04c11db7, sin reflexionar).
 *
 * Estrategia: se leen los paquetes 0 y 1 sin copiar datos, se sustituye el
 * paquete 1 por uno nuevo con los comentarios existentes mas el cambio, y se
 * reescriben las paginas de cabecera. El resto del fichero se copia tal cual
 * ajustando unicamente el numero de secuencia y el CRC de las paginas tocadas.
 */

/* ------------------------------------------------------------------------- */
/* CRC de Ogg                                                                */
/* ------------------------------------------------------------------------- */

static uint32_t crc_table[256];
static int crc_ready = 0;

static void crc_init(void) {
    if (crc_ready) return;
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t r = i << 24;
        for (int k = 0; k < 8; k++) {
            r = (r & 0x80000000u) ? (r << 1) ^ 0x04c11db7u : (r << 1);
        }
        crc_table[i] = r;
    }
    crc_ready = 1;
}

static uint32_t ogg_crc(const unsigned char* data, size_t len, uint32_t seed) {
    crc_init();
    uint32_t crc = seed;
    for (size_t i = 0; i < len; i++) {
        crc = (crc << 8) ^ crc_table[((crc >> 24) & 0xFF) ^ data[i]];
    }
    return crc;
}

/* ------------------------------------------------------------------------- */
/* Buffer                                                                     */
/* ------------------------------------------------------------------------- */

typedef struct {
    unsigned char* data;
    size_t len;
    size_t cap;
} buf;

static int buf_reserve(buf* b, size_t extra) {
    if (b->len + extra <= b->cap) return 0;
    size_t next = b->cap ? b->cap : 1024;
    while (next < b->len + extra) next *= 2;
    unsigned char* grown = realloc(b->data, next);
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

static int buf_u8(buf* b, unsigned v) {
    unsigned char c = (unsigned char)v;
    return buf_append(b, &c, 1);
}

static int buf_u32le(buf* b, uint32_t v) {
    unsigned char t[4] = { (unsigned char)(v & 0xFF), (unsigned char)((v >> 8) & 0xFF),
                           (unsigned char)((v >> 16) & 0xFF), (unsigned char)((v >> 24) & 0xFF) };
    return buf_append(b, t, 4);
}

static uint32_t rd_u32le(const unsigned char* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/* ------------------------------------------------------------------------- */
/* Paginas Ogg                                                               */
/* ------------------------------------------------------------------------- */

typedef struct {
    size_t start;      /* principio de la cabecera "OggS" */
    size_t body;       /* principio del cuerpo */
    size_t body_len;   /* longitud del cuerpo */
    size_t end;        /* final de la pagina */
    unsigned char header_type;
    uint64_t granule;
    uint32_t serial;
    uint32_t seq;
    unsigned char nsegs;
} ogg_page;

static int parse_page(const unsigned char* d, size_t size, size_t pos, ogg_page* pg) {
    if (pos + 27 > size) return -1;
    if (memcmp(d + pos, "OggS", 4) != 0) return -1;
    pg->start = pos;
    pg->header_type = d[pos + 5];
    pg->granule = 0;
    for (int i = 0; i < 8; i++) pg->granule |= (uint64_t)d[pos + 6 + i] << (8 * i);
    pg->serial = rd_u32le(d + pos + 14);
    pg->seq = rd_u32le(d + pos + 18);
    pg->nsegs = d[pos + 26];
    size_t table = pos + 27;
    if (table + pg->nsegs > size) return -1;
    size_t blen = 0;
    for (int i = 0; i < pg->nsegs; i++) blen += d[table + i];
    pg->body = table + pg->nsegs;
    pg->body_len = blen;
    pg->end = pg->body + blen;
    if (pg->end > size) return -1;
    return 0;
}

/* Escribe una pagina con "OggS", cabecera y CRC recalculado. */
static int write_page(buf* out, unsigned char header_type, uint64_t granule,
                      uint32_t serial, uint32_t seq,
                      const unsigned char* segments, unsigned char nsegs,
                      const unsigned char* body, size_t body_len) {
    size_t at = out->len;
    if (buf_append(out, "OggS", 4) != 0) return -1;
    if (buf_u8(out, 0) != 0) return -1;              /* version */
    if (buf_u8(out, header_type) != 0) return -1;
    for (int i = 0; i < 8; i++) {
        if (buf_u8(out, (unsigned)((granule >> (8 * i)) & 0xFF)) != 0) return -1;
    }
    {
        unsigned char t[4];
        for (int i = 0; i < 4; i++) t[i] = (unsigned char)((serial >> (8 * i)) & 0xFF);
        if (buf_append(out, t, 4) != 0) return -1;
        for (int i = 0; i < 4; i++) t[i] = (unsigned char)((seq >> (8 * i)) & 0xFF);
        if (buf_append(out, t, 4) != 0) return -1;
    }
    if (buf_append(out, "\0\0\0\0", 4) != 0) return -1; /* CRC pendiente */
    if (buf_u8(out, nsegs) != 0) return -1;
    if (nsegs && buf_append(out, segments, nsegs) != 0) return -1;
    if (body_len && buf_append(out, body, body_len) != 0) return -1;

    /* El CRC de Ogg se almacena en little-endian (todos los campos de la
     * cabecera de pagina lo son). */
    uint32_t crc = ogg_crc(out->data + at, out->len - at, 0);
    out->data[at + 22] = (unsigned char)(crc & 0xFF);
    out->data[at + 23] = (unsigned char)((crc >> 8) & 0xFF);
    out->data[at + 24] = (unsigned char)((crc >> 16) & 0xFF);
    out->data[at + 25] = (unsigned char)((crc >> 24) & 0xFF);
    return 0;
}

/* ------------------------------------------------------------------------- */
/* Comentarios                                                               */
/* ------------------------------------------------------------------------- */

/* Una entrada "KEY=value" ya codificada (longitud + bytes). */
typedef struct {
    uint32_t len;
    unsigned char* data;
} comment;

typedef struct {
    comment* items;
    size_t count;
    size_t cap;
    const unsigned char* vendor;
    uint32_t vendor_len;
} comment_set;

static void comments_free(comment_set* cs) {
    for (size_t i = 0; i < cs->count; i++) free(cs->items[i].data);
    free(cs->items);
    cs->items = NULL;
    cs->count = cs->cap = 0;
}

static int comments_add(comment_set* cs, const unsigned char* data, uint32_t len) {
    if (cs->count == cs->cap) {
        size_t nc = cs->cap ? cs->cap * 2 : 8;
        comment* tmp = realloc(cs->items, nc * sizeof(comment));
        if (!tmp) return -1;
        cs->items = tmp;
        cs->cap = nc;
    }
    unsigned char* copy = malloc(len ? len : 1);
    if (!copy) return -1;
    if (len) memcpy(copy, data, len);
    cs->items[cs->count].len = len;
    cs->items[cs->count].data = copy;
    cs->count++;
    return 0;
}

/* Quita de `cs` las entradas cuya clave coincide con `key`. */
static void comments_drop_key(comment_set* cs, const char* key) {
    size_t klen = strlen(key);
    size_t w = 0;
    for (size_t i = 0; i < cs->count; i++) {
        comment* c = &cs->items[i];
        size_t eq = 0;
        while (eq < c->len && c->data[eq] != '=') eq++;
        int match = (eq == klen);
        if (match) {
            for (size_t j = 0; j < klen; j++) {
                unsigned char a = c->data[j];
                unsigned char b = (unsigned char)key[j];
                if (a >= 'A' && a <= 'Z') a = (unsigned char)(a + 32);
                if (b >= 'A' && b <= 'Z') b = (unsigned char)(b + 32);
                if (a != b) { match = 0; break; }
            }
        }
        if (match) {
            free(c->data);
        } else if (w != i) {
            cs->items[w++] = *c;
        } else {
            w++;
        }
    }
    cs->count = w;
}

/* Serializa `cs` como cuerpo de comentario (sin el tipo ni el magic). */
static int serialize_comments(buf* out, const comment_set* cs) {
    if (buf_u32le(out, cs->vendor_len) != 0) return -1;
    if (cs->vendor_len && buf_append(out, cs->vendor, cs->vendor_len) != 0) return -1;
    if (buf_u32le(out, (uint32_t)cs->count) != 0) return -1;
    for (size_t i = 0; i < cs->count; i++) {
        if (buf_u32le(out, cs->items[i].len) != 0) return -1;
        if (cs->items[i].len && buf_append(out, cs->items[i].data, cs->items[i].len) != 0) return -1;
    }
    return 0;
}

/* Parsea un cuerpo de comentarios ya sin el magic (vorbis) o "OpusTags". */
static void parse_comments(const unsigned char* body, size_t len, comment_set* cs) {
    memset(cs, 0, sizeof *cs);
    if (len < 4) return;
    uint32_t vlen = rd_u32le(body);
    if (4 + (size_t)vlen + 4 > len) return;
    cs->vendor = body + 4;
    cs->vendor_len = vlen;
    size_t p = 4 + vlen;
    uint32_t n = rd_u32le(body + p);
    p += 4;
    for (uint32_t i = 0; i < n; i++) {
        if (p + 4 > len) break;
        uint32_t l = rd_u32le(body + p);
        p += 4;
        if (p + l > len) break;
        if (comments_add(cs, body + p, l) != 0) break;
        p += l;
    }
}

/* ------------------------------------------------------------------------- */
/* Empaquetado                                                               */
/* ------------------------------------------------------------------------- */

/*
 * Empaqueta `packets` en paginas Ogg y las anade a `out`.
 *
 * Un paquete se codifica como segmentos de 255 bytes mas uno final con el
 * resto; si la longitud es multiplo de 255 se anade un segmento de valor 0
 * para marcar el final. Las paginas agrupan hasta 255 segmentos y no pueden
 * cortar un paquete salvo que se llenen: en ese caso la pagina siguiente
 * marca "continuado" (0x01).
 */
static int emit_packets(buf* out, const unsigned char* const* packets,
                        const uint32_t* lengths, size_t npackets,
                        uint32_t serial, uint32_t seq_start,
                        unsigned char header_type_first, uint64_t granule_first,
                        uint32_t* seq_out) {
    /* Lista plana de segmentos con su puntero y longitud. */
    size_t total = 0;
    for (size_t i = 0; i < npackets; i++) total += lengths[i] / 255 + 1;

    const unsigned char** sp = malloc(total * sizeof(*sp));
    uint32_t* sl = malloc(total * sizeof(*sl));
    if (!sp || !sl) { free(sp); free(sl); return -1; }

    size_t n = 0;
    for (size_t i = 0; i < npackets; i++) {
        const unsigned char* p = packets[i];
        uint32_t left = lengths[i];
        while (left >= 255) {
            sp[n] = p; sl[n] = 255; n++;
            p += 255;
            left -= 255;
        }
        sp[n] = p;
        sl[n] = left; /* 0 si era multiplo de 255: cierra el paquete */
        n++;
    }

    uint32_t seq = seq_start;
    size_t i = 0;
    int first_page = 1;
    int rc = 0;
    while (i < n) {
        unsigned char segs[255];
        size_t ns = 0;
        buf body = {0};
        size_t page_start = i;
        int continued = !first_page && (i > 0) && (sl[i - 1] == 255);

        while (i < n && ns < 255) {
            segs[ns] = (unsigned char)sl[i];
            if (buf_append(&body, sp[i], sl[i]) != 0) { free(body.data); rc = -1; goto done; }
            ns++;
            i++;
            /* Un segmento de valor < 255 cierra paquete: fin de pagina. */
            if (sl[i - 1] < 255) break;
        }
        (void)page_start;

        unsigned char ht = (unsigned char)(first_page ? header_type_first : (continued ? 0x01 : 0x00));
        if (write_page(out, ht, first_page ? granule_first : 0, serial, seq, segs,
                       (unsigned char)ns, body.data, body.len) != 0) {
            free(body.data);
            rc = -1;
            goto done;
        }
        free(body.data);
        seq++;
        first_page = 0;
    }

done:
    free(sp);
    free(sl);
    if (seq_out) *seq_out = seq;
    return rc;
}

/* ------------------------------------------------------------------------- */
/* API publica                                                               */
/* ------------------------------------------------------------------------- */

/*
 * Reescribe el paquete de comentarios de un Ogg.
 * `is_opus` != 0 indica Opus ("OpusTags"), 0 Vorbis (tipo 3 + "vorbis").
 */
static int32_t ogg_set(const char* path, const char* key, const char* value, int is_opus) {
    if (!path || !key) return -1;
    uint64_t fsize = 0;
    char* raw = ch_file_read_all(path, &fsize);
    if (!raw) return -1;
    const unsigned char* d = (const unsigned char*)raw;
    if (fsize < 27 || memcmp(d, "OggS", 4) != 0) {
        ch_file_free(raw);
        return -1;
    }

    /*
     * Localizar los paquetes 0 y 1.
     *
     * Un paquete puede cruzar varias paginas, asi que se recorren los segmentos
     * en orden y se van acumulando: un segmento de 255 continua el paquete y
     * uno menor lo cierra. Se anota donde termina el paquete 1 (pagina y
     * segmento) para saber que bytes de esa pagina siguen siendo del paquete 2.
     */
    ogg_page pg;
    size_t pos = 0;
    const unsigned char *pkt0 = NULL, *pkt1 = NULL;
    uint32_t pkt0_len = 0, pkt1_len = 0;
    unsigned char page0_ht = 0;
    uint64_t page0_granule = 0;
    uint32_t page0_serial = 0;
    size_t after = 0;                  /* final de la pagina donde acaba pkt1 */
    const unsigned char* tail = NULL;  /* arranque del paquete 2 en esa pagina */
    size_t tail_len = 0;
    int packets = 0;
    int have = 0;

    while (pos + 27 <= fsize && have < 2) {
        if (parse_page(d, fsize, pos, &pg) != 0) break;
        if (pos == 0) {
            page0_ht = pg.header_type;
            page0_granule = pg.granule;
            page0_serial = pg.serial;
        }
        const unsigned char* seg = d + pg.start + 27;
        const unsigned char* body = d + pg.body;
        size_t off = 0;
        for (int i = 0; i < pg.nsegs && have < 2; i++) {
            unsigned sl = seg[i];
            if (packets == 0) {
                if (pkt0 == NULL) pkt0 = body + off;
                pkt0_len += sl;
                if (sl < 255) packets = 1;
            } else if (packets == 1) {
                if (pkt1 == NULL) pkt1 = body + off;
                pkt1_len += sl;
                if (sl < 255) {
                    packets = 2;
                    after = pg.end;
                    tail = body + off + sl;
                    tail_len = (size_t)(pg.body + pg.body_len) - (size_t)(tail - d);
                    have = 2;
                }
            }
            off += sl;
        }
        pos = pg.end;
    }

have_packets:
    if (packets < 2 || pkt0_len == 0 || pkt1_len == 0) {
        ch_file_free(raw);
        return -2;
    }

    /* Comprobacion de formato y cuerpo de comentarios. */
    buf newpkt = {0};
    comment_set cs;
    memset(&cs, 0, sizeof cs);
    const unsigned char* cbody = pkt1;
    uint32_t cbody_len = pkt1_len;
    if (is_opus) {
        if (pkt1_len < 8 || memcmp(pkt1, "OpusTags", 8) != 0) {
            ch_file_free(raw);
            return -2;
        }
        cbody = pkt1 + 8;
        cbody_len = pkt1_len - 8;
        if (buf_append(&newpkt, "OpusTags", 8) != 0) goto oom;
    } else {
        if (pkt1_len < 7 || pkt1[0] != 3 || memcmp(pkt1 + 1, "vorbis", 6) != 0) {
            ch_file_free(raw);
            return -2;
        }
        cbody = pkt1 + 7;
        cbody_len = pkt1_len - 7;
        if (buf_u8(&newpkt, 3) != 0) goto oom;
        if (buf_append(&newpkt, "vorbis", 6) != 0) goto oom;
    }

    parse_comments(cbody, cbody_len, &cs);
    comments_drop_key(&cs, key);
    if (serialize_comments(&newpkt, &cs) != 0) goto oom;
    comments_free(&cs);
    {
        char line[8192];
        int n = snprintf(line, sizeof line, "%s=%s", key, value ? value : "");
        if (n < 0 || (size_t)n >= sizeof line) goto oom;

        /* serialize_comments dejo count = N. Hay que sumarle 1 y escribir el
         * campo antes de anadir la entrada nueva: el contador va justo detras
         * del vendor, y el bit de framing (solo Vorbis) al final del paquete. */
        size_t count_at = (is_opus ? 8 : 7) + 4 + cs.vendor_len;
        uint32_t ncount = rd_u32le(newpkt.data + count_at) + 1;
        newpkt.data[count_at] = (unsigned char)(ncount & 0xFF);
        newpkt.data[count_at + 1] = (unsigned char)((ncount >> 8) & 0xFF);
        newpkt.data[count_at + 2] = (unsigned char)((ncount >> 16) & 0xFF);
        newpkt.data[count_at + 3] = (unsigned char)((ncount >> 24) & 0xFF);
        if (buf_u32le(&newpkt, (uint32_t)n) != 0) goto oom;
        if (buf_append(&newpkt, line, (size_t)n) != 0) goto oom;
        if (!is_opus && buf_u8(&newpkt, 1) != 0) goto oom;
    }

    /* Reconstruir: paquete 0 + paquete 1 nuevo + resto del fichero. */
    {
        buf out = {0};
        const unsigned char* packets_arr[2];
        uint32_t lens[2];
        uint32_t seq = 0;
        packets_arr[0] = pkt0;
        lens[0] = pkt0_len;
        packets_arr[1] = newpkt.data;
        lens[1] = (uint32_t)newpkt.len;
        if (emit_packets(&out, packets_arr, lens, 2, page0_serial, 0,
                         page0_ht, page0_granule, &seq) != 0) {
            free(out.data);
            free(newpkt.data);
            ch_file_free(raw);
            return -1;
        }
        free(newpkt.data);

        /* Cola del paquete 2 que estaba en la ultima pagina leida: se emite
         * como pagina aparte para no perder los bytes que le siguen. */
        if (tail_len > 0) {
            unsigned char segs[255];
            unsigned char ns = 0;
            size_t full = tail_len / 255;
            size_t rem = tail_len % 255;
            for (size_t i = 0; i < full && ns < 255; i++) segs[ns++] = 255;
            if (rem && ns < 255) segs[ns++] = (unsigned char)rem;
            /* El paquete de comentarios cerro con un segmento < 255, asi que la
             * cola arranca un paquete nuevo: la pagina no lleva "continuado".
             * Si ese paquete sigue en la pagina siguiente, su flag 0x01 ya lo
             * indica y se copia tal cual. */
            unsigned char tail_ht = (unsigned char)(pg.header_type & 0x04);
            if (write_page(&out, tail_ht, 0, page0_serial, seq, segs, ns, tail, tail_len) != 0) {
                free(out.data);
                ch_file_free(raw);
                return -1;
            }
            seq++;
        }

        /* Copiar el resto de las paginas tal cual, con nueva secuencia y CRC. */
        size_t p2 = after;
        while (p2 + 27 <= fsize) {
            ogg_page q;
            if (parse_page(d, fsize, p2, &q) != 0) break;
            if (buf_append(&out, d + q.start, q.end - q.start) != 0) {
                free(out.data);
                ch_file_free(raw);
                return -1;
            }
            /* Parchear numero de pagina y CRC de la pagina recien copiada. */
            size_t at = out.len - (q.end - q.start);
            out.data[at + 18] = (unsigned char)(seq & 0xFF);
            out.data[at + 19] = (unsigned char)((seq >> 8) & 0xFF);
            out.data[at + 20] = (unsigned char)((seq >> 16) & 0xFF);
            out.data[at + 21] = (unsigned char)((seq >> 24) & 0xFF);
            /* El CRC se calcula con su propio campo a cero. */
            out.data[at + 22] = 0;
            out.data[at + 23] = 0;
            out.data[at + 24] = 0;
            out.data[at + 25] = 0;
            uint32_t crc = ogg_crc(out.data + at, out.len - at, 0);
            out.data[at + 22] = (unsigned char)(crc & 0xFF);
            out.data[at + 23] = (unsigned char)((crc >> 8) & 0xFF);
            out.data[at + 24] = (unsigned char)((crc >> 16) & 0xFF);
            out.data[at + 25] = (unsigned char)((crc >> 24) & 0xFF);
            seq++;
            p2 = q.end;
        }

        ch_file_free(raw);
        int32_t rc = ch_file_write_atomic(path, (const char*)out.data, out.len);
        free(out.data);
        return rc == 0 ? 0 : -1;
    }

oom:
    free(newpkt.data);
    comments_free(&cs);
    ch_file_free(raw);
    return -1;
}

int32_t ch_tags_ogg_set(const char* path, const char* key, const char* value) {
    if (!path) return -1;
    size_t n = strlen(path);
    if (n < 5) return -1;
    return ogg_set(path, key, value, 0);
}

int32_t ch_tags_opus_set(const char* path, const char* key, const char* value) {
    if (!path) return -1;
    size_t n = strlen(path);
    if (n < 5) return -1;
    return ogg_set(path, key, value, 1);
}