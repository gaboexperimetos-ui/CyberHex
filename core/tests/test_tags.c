#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "tags.h"
#include "fileio.h"

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}

static int write_flac(const char* path) {
    /* Minimal valid FLAC file with STREAMINFO + VORBIS_COMMENT */
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    /* fLaC signature */
    fwrite("fLaC", 1, 4, f);
    /* STREAMINFO block (type 0, last=0, length 34) */
    uint8_t streaminfo[34] = {0};
    streaminfo[0] = 0x80; /* last block = 0, type = 0 */
    streaminfo[1] = 0x00; streaminfo[2] = 0x00; streaminfo[3] = 0x22; /* length 34 */
    streaminfo[4] = 0x00; streaminfo[5] = 0x00; streaminfo[6] = 0x00; streaminfo[7] = 0x10; /* min/max block size 16 */
    streaminfo[8] = 0x00; streaminfo[9] = 0x00; streaminfo[10] = 0x00; streaminfo[11] = 0x00; /* min/max frame size 0 */
    streaminfo[12] = 0x00; streaminfo[13] = 0x41; streaminfo[14] = 0xAC; streaminfo[15] = 0x00; /* sample rate 48000, channels 2, bits 16 */
    streaminfo[16] = 0x00; streaminfo[17] = 0x00; streaminfo[18] = 0x00; streaminfo[19] = 0x00; /* total samples 0 */
    streaminfo[20] = 0x00; streaminfo[21] = 0x00; streaminfo[22] = 0x00; streaminfo[23] = 0x00;
    streaminfo[24] = 0x00; streaminfo[25] = 0x00; streaminfo[26] = 0x00; streaminfo[27] = 0x00;
    streaminfo[28] = 0x00; streaminfo[29] = 0x00; streaminfo[30] = 0x00; streaminfo[31] = 0x00;
    streaminfo[32] = 0x00; streaminfo[32] = 0x00; /* MD5 */
    fwrite(streaminfo, 1, 38, f); /* 4 byte header + 34 data */
    /* VORBIS_COMMENT block (type 4, last=1, minimal) */
    uint8_t vorbis[12] = {0};
    vorbis[0] = 0xC4; /* last=1, type=4 */
    vorbis[1] = 0x00; vorbis[2] = 0x00; vorbis[3] = 0x08; /* length 8 */
    vorbis[4] = 0x08; vorbis[5] = 0x00; vorbis[6] = 0x00; vorbis[7] = 0x00; /* vendor length 8 */
    fwrite("CyberHex", 1, 8, f);
    fwrite(vorbis, 1, 12, f); /* 4 + 8 = 12, but we already wrote vendor */
    /* Actually write proper VORBIS_COMMENT block */
    fseek(f, 4 + 38, SEEK_SET);
    uint8_t vc[4+8+4] = {0xC4, 0x00, 0x00, 0x10, /* last+type=4, len=16 */
        0x08, 0x00, 0x00, 0x00, 'C','y','b','e','r','H','e','x', /* vendor */
        0x00, 0x00, 0x00, 0x00 }; /* 0 comments */
    fwrite(vc, 1, sizeof(vc), f);
    /* Some audio data (zeros) */
    for (int i = 0; i < 1000; i++) fputc(0, f);
    fclose(f);
    return 0;
}

static int write_mp3(const char* path) {
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    /* Minimal MP3 with ID3v2 header */
    fwrite("ID3", 1, 3, f);
    fwrite("\x03\x00\x00", 1, 3, f); /* version 2.3.0 */
    fwrite("\x00", 1, 1, f); /* flags */
    fwrite("\x00\x00\x00\x00", 1, 4, f); /* size 0 */
    /* Some fake audio data */
    for (int i = 0; i < 1000; i++) fputc(0, f);
    fclose(f);
    return 0;
}

static int write_wav(const char* path) {
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    uint8_t hdr[44] = {0};
    memcpy(hdr, "RIFF", 4);
    memcpy(hdr + 8, "WAVEfmt ", 8);
    uint32_t fmt_len = 16;
    uint16_t fmt = 1;
    uint16_t ch = 2;
    uint32_t rate = 48000;
    uint16_t bits = 16;
    uint32_t byte_rate = rate * ch * 2;
    uint16_t block_align = ch * 2;
    memcpy(hdr + 16, &fmt_len, 4);
    memcpy(hdr + 20, &fmt, 2);
    memcpy(hdr + 22, &ch, 2);
    memcpy(hdr + 24, &rate, 4);
    memcpy(hdr + 28, &byte_rate, 4);
    memcpy(hdr + 32, &block_align, 2);
    memcpy(hdr + 34, &bits, 2);
    memcpy(hdr + 36, "data", 4);
    uint32_t data_bytes = 48000 * 2 * 2;
    memcpy(hdr + 40, &data_bytes, 4);
    fwrite(hdr, 1, 44, f);
    for (uint32_t i = 0; i < data_bytes / 2; i++) fputc(0, f);
    fclose(f);
    return 0;
}

/* --- utilidades de construccion para MP4/AIFF en las pruebas --- */
typedef struct {
    unsigned char* d;
    size_t n, cap;
} tbuf;

static void tb_put(tbuf* b, const void* p, size_t n) {
    if (b->n + n > b->cap) {
        size_t c = b->cap ? b->cap : 256;
        while (c < b->n + n) c *= 2;
        b->d = (unsigned char*)realloc(b->d, c);
        b->cap = c;
    }
    if (n) memcpy(b->d + b->n, p, n);
    b->n += n;
}

static void tb_zero(tbuf* b, size_t n) {
    for (size_t i = 0; i < n; i++) {
        unsigned char z = 0;
        tb_put(b, &z, 1);
    }
}

static void tb_be32(tbuf* b, uint32_t v) {
    unsigned char t[4] = {(unsigned char)(v >> 24), (unsigned char)(v >> 16),
                          (unsigned char)(v >> 8), (unsigned char)v};
    tb_put(b, t, 4);
}

static void tb_box(tbuf* out, const char* type, const tbuf* body) {
    tb_be32(out, (uint32_t)(body->n + 8));
    tb_put(out, type, 4);
    tb_put(out, body->d, body->n);
}

static uint32_t rd_be32(const unsigned char* p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static long find_bytes(const unsigned char* h, size_t hn, const void* nd, size_t nn) {
    if (nn == 0 || hn < nn) return -1;
    for (size_t i = 0; i + nn <= hn; i++) {
        if (memcmp(h + i, nd, nn) == 0) return (long)i;
    }
    return -1;
}

static unsigned char* read_whole(const char* path, size_t* out_n) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char* b = (unsigned char*)malloc(sz > 0 ? (size_t)sz : 1);
    if (!b) { fclose(f); return NULL; }
    size_t rd = fread(b, 1, (size_t)sz, f);
    fclose(f);
    *out_n = rd;
    return b;
}

static int file_contains(const char* path, const void* nd, size_t nn) {
    size_t n = 0;
    unsigned char* b = read_whole(path, &n);
    if (!b) return 0;
    int ok = find_bytes(b, n, nd, nn) >= 0;
    free(b);
    return ok;
}

static void mp4_hdlr_body(tbuf* out) {
    tb_zero(out, 8);
    tb_put(out, "mdir", 4);
    tb_put(out, "appl", 4);
    tb_zero(out, 9);
}

static int write_mp4(const char* path) {
    tbuf ftyp = {0};
    {
        tbuf b = {0};
        tb_put(&b, "M4A ", 4);
        tb_be32(&b, 0);
        tb_put(&b, "M4A ", 4);
        tb_put(&b, "isom", 4);
        tb_box(&ftyp, "ftyp", &b);
        free(b.d);
    }
    tbuf moov = {0};
    {
        tbuf body = {0};
        {
            tbuf mvhd = {0};
            tb_zero(&mvhd, 100);
            tb_box(&body, "mvhd", &mvhd);
            free(mvhd.d);
        }
        {
            tbuf trak = {0};
            {
                tbuf x = {0};
                tb_zero(&x, 84);
                tb_box(&trak, "tkhd", &x);
                free(x.d);
            }
            {
                tbuf mdia = {0};
                {
                    tbuf x = {0};
                    tb_zero(&x, 24);
                    tb_box(&mdia, "mdhd", &x);
                    free(x.d);
                }
                {
                    tbuf x = {0};
                    mp4_hdlr_body(&x);
                    tb_box(&mdia, "hdlr", &x);
                    free(x.d);
                }
                {
                    tbuf minf = {0};
                    {
                        tbuf x = {0};
                        tb_zero(&x, 8);
                        tb_box(&minf, "smhd", &x);
                        free(x.d);
                    }
                    {
                        tbuf dinf = {0};
                        tbuf dref = {0};
                        tb_be32(&dref, 0);
                        tb_be32(&dref, 1);
                        {
                            tbuf url = {0};
                            tb_be32(&url, 1);
                            tb_box(&dref, "url ", &url);
                            free(url.d);
                        }
                        tb_box(&dinf, "dref", &dref);
                        free(dref.d);
                        tb_box(&minf, "dinf", &dinf);
                        free(dinf.d);
                    }
                    {
                        tbuf stbl = {0};
                        {
                            tbuf x = {0};
                            tb_be32(&x, 0);
                            tb_be32(&x, 0);
                            tb_box(&stbl, "stsd", &x);
                            free(x.d);
                        }
                        {
                            tbuf x = {0};
                            tb_be32(&x, 0);
                            tb_be32(&x, 0);
                            tb_box(&stbl, "stts", &x);
                            free(x.d);
                        }
                        {
                            tbuf x = {0};
                            tb_be32(&x, 0);
                            tb_be32(&x, 0);
                            tb_box(&stbl, "stsc", &x);
                            free(x.d);
                        }
                        {
                            tbuf x = {0};
                            tb_be32(&x, 0);
                            tb_be32(&x, 0);
                            tb_be32(&x, 1);
                            tb_be32(&x, 64);
                            tb_box(&stbl, "stsz", &x);
                            free(x.d);
                        }
                        {
                            tbuf x = {0};
                            tb_be32(&x, 0);
                            tb_be32(&x, 1);
                            tb_be32(&x, 0); /* offset: se rellena luego */
                            tb_box(&stbl, "stco", &x);
                            free(x.d);
                        }
                        tb_box(&minf, "stbl", &stbl);
                        free(stbl.d);
                    }
                    tb_box(&mdia, "minf", &minf);
                    free(minf.d);
                }
                tb_box(&trak, "mdia", &mdia);
                free(mdia.d);
            }
            tb_box(&body, "trak", &trak);
            free(trak.d);
        }
        {
            tbuf udta = {0};
            tbuf meta = {0};
            tb_zero(&meta, 4); /* full box */
            {
                tbuf x = {0};
                mp4_hdlr_body(&x);
                tb_box(&meta, "hdlr", &x);
                free(x.d);
            }
            {
                tbuf ilst = {0};
                tb_box(&meta, "ilst", &ilst); /* vacio */
            }
            tb_box(&udta, "meta", &meta);
            free(meta.d);
            tb_box(&body, "udta", &udta);
            free(udta.d);
        }
        tb_box(&moov, "moov", &body);
        free(body.d);
    }

    tbuf file = {0};
    tb_put(&file, ftyp.d, ftyp.n);
    free(ftyp.d);
    tb_put(&file, moov.d, moov.n);
    free(moov.d);

    uint32_t payload_off = (uint32_t)(file.n + 8);
    long s = find_bytes(file.d, file.n, "stco", 4);
    if (s >= 0) {
        unsigned char v[4] = {(unsigned char)(payload_off >> 24),
                              (unsigned char)(payload_off >> 16),
                              (unsigned char)(payload_off >> 8),
                              (unsigned char)payload_off};
        memcpy(file.d + s + 12, v, 4);
    }

    {
        tbuf data = {0};
        tb_zero(&data, 64);
        tbuf mdat = {0};
        tb_box(&mdat, "mdat", &data);
        free(data.d);
        tb_put(&file, mdat.d, mdat.n);
        free(mdat.d);
    }

    FILE* f = fopen(path, "wb");
    if (!f) { free(file.d); return -1; }
    fwrite(file.d, 1, file.n, f);
    fclose(f);
    free(file.d);
    return 0;
}

/* El primer offset de stco debe apuntar al inicio del payload de mdat. */
static int mp4_offsets_ok(const char* path) {
    size_t n = 0;
    unsigned char* d = read_whole(path, &n);
    if (!d) return 0;
    long s = find_bytes(d, n, "stco", 4);
    long m = find_bytes(d, n, "mdat", 4);
    int ok = 0;
    if (s >= 0 && m >= 0) {
        uint32_t entry = rd_be32(d + s + 12);
        uint32_t payload = (uint32_t)(m + 4); /* 'mdat' esta a +4 del box */
        ok = (entry == payload);
    }
    free(d);
    return ok;
}

static int write_aiff(const char* path) {
    tbuf file = {0};
    tb_put(&file, "FORM", 4);
    tb_be32(&file, 0);
    tb_put(&file, "AIFF", 4);
    {
        tbuf comm = {0};
        tb_zero(&comm, 18);
        tb_box(&file, "COMM", &comm);
        free(comm.d);
    }
    {
        tbuf ssnd = {0};
        tb_zero(&ssnd, 8 + 32);
        tb_box(&file, "SSND", &ssnd);
        free(ssnd.d);
    }
    uint32_t form_size = (uint32_t)(file.n - 8);
    unsigned char sz[4] = {(unsigned char)(form_size >> 24), (unsigned char)(form_size >> 16),
                           (unsigned char)(form_size >> 8), (unsigned char)form_size};
    memcpy(file.d + 4, sz, 4);

    FILE* f = fopen(path, "wb");
    if (!f) { free(file.d); return -1; }
    fwrite(file.d, 1, file.n, f);
    fclose(f);
    free(file.d);
    return 0;
}

static int aiff_form_size_ok(const char* path) {
    size_t n = 0;
    unsigned char* d = read_whole(path, &n);
    if (!d) return 0;
    int ok = 0;
    if (n >= 12 && memcmp(d, "FORM", 4) == 0) {
        uint32_t declared = rd_be32(d + 4);
        ok = (declared == (uint32_t)(n - 8));
    }
    free(d);
    return ok;
}

static int write_aac(const char* path) {
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    for (int i = 0; i < 200; i++) fputc(0, f);
    fclose(f);
    return 0;
}

int main(void) {
    char tmp[256];
    snprintf(tmp, sizeof tmp, "/tmp/cyberhex_test_XXXXXX");
    int fd = mkstemp(tmp);
    if (fd < 0) { perror("mkstemp"); return 1; }
    close(fd);
    unlink(tmp);

    /* Test FLAC tag write/read */
    char flac_path[256];
    snprintf(flac_path, sizeof flac_path, "%s.flac", tmp);
    check(write_flac(flac_path) == 0, "flac generado");

    check(ch_tags_set(flac_path, "TITLE", "Test Title") == 0, "tags_set TITLE");
    check(ch_tags_set(flac_path, "ARTIST", "Test Artist") == 0, "tags_set ARTIST");

    /* Test MP3 tag write/read */
    char mp3_path[256];
    snprintf(mp3_path, sizeof mp3_path, "%s.mp3", tmp);
    check(write_mp3(mp3_path) == 0, "mp3 generado");

    check(ch_tags_mp3_set(mp3_path, "TITLE", "MP3 Title") == 0, "tags_mp3_set TITLE");
    check(ch_tags_mp3_set(mp3_path, "ALBUM", "MP3 Album") == 0, "tags_mp3_set ALBUM");
    check(ch_tags_mp3_set(mp3_path, "REPLAYGAIN_TRACK_GAIN", "-5.0 dB") == 0, "tags_mp3_set TXXX");

    /* Invalid paths */
    check(ch_tags_set(NULL, "TITLE", "x") == -1, "tags_set NULL path");
    check(ch_tags_set("/nonexistent.flac", "TITLE", "x") == -1, "tags_set noexist");
    check(ch_tags_set(flac_path, NULL, "x") == -1, "tags_set NULL key");
    check(ch_tags_set("test.txt", "TITLE", "x") == -1, "tags_set not flac");

    check(ch_tags_mp3_set(NULL, "TITLE", "x") == -1, "tags_mp3_set NULL path");
    check(ch_tags_mp3_set("/nonexistent.mp3", "TITLE", "x") == -1, "tags_mp3_set noexist");
    check(ch_tags_mp3_set(mp3_path, NULL, "x") == -1, "tags_mp3_set NULL key");
    check(ch_tags_mp3_set("test.txt", "TITLE", "x") == -1, "tags_mp3_set not mp3");

    /* MP4 / M4A: escribe, verifica offsets y borra */
    char m4a_path[256];
    snprintf(m4a_path, sizeof m4a_path, "%s.m4a", tmp);
    check(write_mp4(m4a_path) == 0, "m4a generado");
    check(mp4_offsets_ok(m4a_path), "m4a stco inicial coherente");
    check(ch_tags_mp4_set(m4a_path, "TITLE", "M4A Title") == 0, "tags_mp4_set TITLE");
    check(ch_tags_mp4_set(m4a_path, "ARTIST", "M4A Artist") == 0, "tags_mp4_set ARTIST");
    check(ch_tags_mp4_set(m4a_path, "TRACK", "3/12") == 0, "tags_mp4_set TRACK");
    check(file_contains(m4a_path, "M4A Title", 9), "m4a guarda el titulo");
    check(file_contains(m4a_path, "M4A Artist", 10), "m4a guarda el artista");
    check(mp4_offsets_ok(m4a_path), "m4a corrige stco al crecer moov");
    check(ch_tags_mp4_set(m4a_path, "TITLE", NULL) == 0, "tags_mp4_set borra TITLE");
    check(!file_contains(m4a_path, "M4A Title", 9), "m4a borra el titulo");
    check(file_contains(m4a_path, "M4A Artist", 10), "m4a conserva otros campos");
    check(mp4_offsets_ok(m4a_path), "m4a corrige stco al encoger moov");
    check(ch_tags_mp4_set(NULL, "TITLE", "x") == -1, "tags_mp4_set NULL path");
    check(ch_tags_mp4_set(m4a_path, NULL, "x") == -1, "tags_mp4_set NULL key");
    check(ch_tags_mp4_set("/nonexistent.m4a", "TITLE", "x") == -1, "tags_mp4_set noexist");
    check(ch_tags_mp4_set("test.txt", "TITLE", "x") == -1, "tags_mp4_set not m4a");

    /* AIFF: chunk ID3 dentro de FORM */
    char aiff_path[256];
    snprintf(aiff_path, sizeof aiff_path, "%s.aiff", tmp);
    check(write_aiff(aiff_path) == 0, "aiff generado");
    check(ch_tags_aiff_set(aiff_path, "TITLE", "AIFF Title") == 0, "tags_aiff_set TITLE");
    check(ch_tags_aiff_set(aiff_path, "ARTIST", "AIFF Artist") == 0, "tags_aiff_set ARTIST");
    check(file_contains(aiff_path, "ID3 ", 4), "aiff crea chunk ID3");
    check(file_contains(aiff_path, "TIT2", 4), "aiff usa marcos ID3");
    check(file_contains(aiff_path, "AIFF Title", 10), "aiff guarda el titulo");
    check(file_contains(aiff_path, "AIFF Artist", 11), "aiff guarda el artista");
    check(aiff_form_size_ok(aiff_path), "aiff ajusta el tamano de FORM");
    check(ch_tags_aiff_set(NULL, "TITLE", "x") == -1, "tags_aiff_set NULL path");
    check(ch_tags_aiff_set(aiff_path, NULL, "x") == -1, "tags_aiff_set NULL key");
    check(ch_tags_aiff_set("/nonexistent.aiff", "TITLE", "x") == -1, "tags_aiff_set noexist");
    check(ch_tags_aiff_set("test.txt", "TITLE", "x") == -1, "tags_aiff_set not aiff");

    /* AAC crudo: ID3v2 al principio */
    char aac_path[256];
    snprintf(aac_path, sizeof aac_path, "%s.aac", tmp);
    check(write_aac(aac_path) == 0, "aac generado");
    check(ch_tags_aac_set(aac_path, "TITLE", "AAC Title") == 0, "tags_aac_set TITLE");
    check(file_contains(aac_path, "ID3", 3), "aac antepone ID3");
    check(file_contains(aac_path, "AAC Title", 9), "aac guarda el titulo");
    check(ch_tags_aac_set(NULL, "TITLE", "x") == -1, "tags_aac_set NULL path");

    unlink(m4a_path);
    unlink(aiff_path);
    unlink(aac_path);
    unlink(flac_path);
    unlink(mp3_path);

    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}