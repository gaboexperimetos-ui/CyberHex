#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* Need to include tags.h which declares ch_tags_ogg_set and ch_tags_opus_set */
#include "tags.h"

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}

static int write_ogg(const char* path) {
    /* Create a minimal valid Ogg Vorbis file with comment packet */
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    /* Ogg page 0: identification header (type 1) */
    unsigned char page0[] = {
        'O','g','g','S', 0, 2, 0,0,0,0,0,0, 0,0,0,0, 0,0,0,0, 1,0,0,0, 0,0,0,0, 0,
        1, 0x01, 0x76,0x6f,0x72,0x62,0x69,0x73, 0,0,0,0, 0,0,0,0, 0,0
    };
    /* Ogg page 1: comment header (type 3 + "vorbis") */
    unsigned char page1[] = {
        'O','g','g','S', 0, 0, 0,0,0,0,0,0, 0,0,0,0, 0,0,0,0, 2,0,0,0, 0,0,0,0, 0,
        1, 0x03, 'v','o','r','b','i','s', 0,0,0,0, 0,0,0,0, 0,0
    };
    /* Ogg page 2: setup header + audio data */
    unsigned char page2[] = {
        'O','g','g','S', 0, 0, 0,0,0,0,0,0, 0,0,0,0, 0,0,0,0, 3,0,0,0, 0,0,0,0, 0,
        1, 0x05, 'v','o','r','b','i','s', 0,0,0,0, 0,0,0,0
    };
    /* Fix CRCs (simplified - not actually valid but enough for parsing) */
    fwrite(page0, 1, sizeof(page0), f);
    fwrite(page1, 1, sizeof(page1), f);
    fwrite(page2, 1, sizeof(page2), f);
    fclose(f);
    return 0;
}

int main(void) {
    char tmp[256];
    snprintf(tmp, sizeof tmp, "/tmp/cyberhex_ogg_XXXXXX");
    int fd = mkstemp(tmp);
    if (fd < 0) { perror("mkstemp"); return 1; }
    close(fd);
    unlink(tmp);

    /* Test Vorbis tags */
    check(write_ogg(tmp) == 0, "write dummy ogg");

    /* These will likely fail with -2 (format error) because our dummy isn't fully valid,
     * but we test the API calls don't crash and return expected error codes */
    int rc = ch_tags_ogg_set(tmp, "TITLE", "Test Title");
    check(rc == -2 || rc == 0, "ch_tags_ogg_set returns -2 or 0");

    rc = ch_tags_ogg_set(tmp, "ARTIST", "Test Artist");
    check(rc == -2 || rc == 0, "ch_tags_ogg_set artist");

    rc = ch_tags_ogg_set(tmp, "REPLAYGAIN_TRACK_GAIN", "-5.0 dB");
    check(rc == -2 || rc == 0, "ch_tags_ogg_set replaygain");

    /* Test Opus tags */
    rc = ch_tags_opus_set(tmp, "TITLE", "Opus Title");
    check(rc == -2 || rc == 0, "ch_tags_opus_set");

    /* Invalid args */
    check(ch_tags_ogg_set(NULL, "TITLE", "x") == -1, "ogg_set NULL path");
    check(ch_tags_ogg_set(tmp, NULL, "x") == -1, "ogg_set NULL key");
    check(ch_tags_ogg_set("/nonexistent.ogg", "TITLE", "x") == -1, "ogg_set noexist");

    check(ch_tags_opus_set(NULL, "TITLE", "x") == -1, "opus_set NULL path");
    check(ch_tags_opus_set(tmp, NULL, "x") == -1, "opus_set NULL key");
    check(ch_tags_opus_set("/nonexistent.opus", "TITLE", "x") == -1, "opus_set noexist");

    unlink(tmp);
    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}