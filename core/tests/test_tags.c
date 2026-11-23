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

    unlink(flac_path);
    unlink(mp3_path);

    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}