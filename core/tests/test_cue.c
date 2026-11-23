#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "cue.h"

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}

static int write_cue(const char* path, const char* content) {
    FILE* f = fopen(path, "w");
    if (!f) return -1;
    fputs(content, f);
    fclose(f);
    return 0;
}

int main(void) {
    char tmp[256];
    snprintf(tmp, sizeof tmp, "/tmp/cyberhex_cue_XXXXXX");
    int fd = mkstemp(tmp);
    if (fd < 0) { perror("mkstemp"); return 1; }
    close(fd);

    /* Valid CUE */
    const char* cue_ok =
        "PERFORMER \"Test Artist\"\n"
        "TITLE \"Test Album\"\n"
        "FILE \"test.wav\" WAVE\n"
        "  TRACK 01 AUDIO\n"
        "    TITLE \"Track One\"\n"
        "    PERFORMER \"Artist One\"\n"
        "    INDEX 01 00:00:00\n"
        "  TRACK 02 AUDIO\n"
        "    TITLE \"Track Two\"\n"
        "    INDEX 01 03:00:00\n";
    check(write_cue(tmp, cue_ok) == 0, "cue write ok");

    ch_cue* c = ch_cue_read(tmp);
    check(c != NULL, "cue_read ok");
    if (c) {
        check(ch_cue_count(c) == 2, "cue_count == 2");
        check(strcmp(ch_cue_album(c), "Test Album") == 0, "cue_album");
        check(strcmp(ch_cue_album_performer(c), "Test Artist") == 0, "cue_album_performer");
        check(strcmp(ch_cue_title(c, 0), "Track One") == 0, "cue_title[0]");
        check(strcmp(ch_cue_title(c, 1), "Track Two") == 0, "cue_title[1]");
        check(strcmp(ch_cue_performer(c, 0), "Artist One") == 0, "cue_performer[0]");
        check(ch_cue_number(c, 0) == 1, "cue_number[0]");
        check(ch_cue_number(c, 1) == 2, "cue_number[1]");
        check(ch_cue_start(c, 0) == 0.0, "cue_start[0]");
        check(ch_cue_start(c, 1) == 180.0, "cue_start[1]");  // 3:00 = 180s
        check(ch_cue_end(c, 0) == 180.0, "cue_end[0]");
        ch_cue_free(c);
    }

    /* Invalid CUE - no INDEX */
    const char* cue_bad =
        "FILE \"test.wav\" WAVE\n"
        "  TRACK 01 AUDIO\n"
        "    TITLE \"No Index\"\n";
    check(write_cue(tmp, cue_bad) == 0, "cue write bad");
    c = ch_cue_read(tmp);
    check(c == NULL, "cue_read returns NULL for no INDEX");
    if (c) ch_cue_free(c);

    /* NULL path */
    check(ch_cue_read(NULL) == NULL, "cue_read NULL path");
    check(ch_cue_count(NULL) == 0, "cue_count NULL");
    check(strcmp(ch_cue_album(NULL), "") == 0, "cue_album NULL");
    check(ch_cue_start(NULL, 0) < 0, "cue_start NULL");

    /* Free NULL */
    ch_cue_free(NULL);

    unlink(tmp);
    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}