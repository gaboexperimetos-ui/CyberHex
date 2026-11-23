#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "markers.h"

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}

int main(void) {
    ch_markers* m = ch_markers_create();
    check(m != NULL, "markers_create");

    /* Add markers */
    int rc = ch_markers_add(m, "track1.mp3", 10.5, "Intro");
    check(rc == 0, "markers_add 1");
    rc = ch_markers_add(m, "track1.mp3", 45.0, "Verse");
    check(rc == 1, "markers_add 2");
    rc = ch_markers_add(m, "track2.mp3", 0.0, "Start");
    check(rc == 2, "markers_add 3");

    /* Count */
    check(ch_markers_count(m, "track1.mp3") == 2, "markers_count track1");
    check(ch_markers_count(m, "track2.mp3") == 1, "markers_count track2");
    check(ch_markers_count(m, "track3.mp3") == 0, "markers_count unknown");
    check(ch_markers_count(NULL, "x") == 0, "markers_count NULL");

    /* Position/Name */
    check(ch_markers_position(m, "track1.mp3", 0) == 10.5, "markers_position[0]");
    check(ch_markers_position(m, "track1.mp3", 1) == 45.0, "markers_position[1]");
    check(ch_markers_position(m, "track1.mp3", 2) < 0, "markers_position oob");
    check(strcmp(ch_markers_name(m, "track1.mp3", 0), "Intro") == 0, "markers_name[0]");
    check(strcmp(ch_markers_name(m, "track1.mp3", 1), "Verse") == 0, "markers_name[1]");
    check(strcmp(ch_markers_name(m, "track1.mp3", 2), "") == 0, "markers_name oob");

    /* Remove */
    rc = ch_markers_remove(m, "track1.mp3", 0);
    check(rc == 0, "markers_remove ok");
    check(ch_markers_count(m, "track1.mp3") == 1, "markers_count after remove");
    check(ch_markers_position(m, "track1.mp3", 0) == 45.0, "markers_position shifted");
    rc = ch_markers_remove(m, "track1.mp3", 5);
    check(rc == -1, "markers_remove oob");

    /* Clear */
    rc = ch_markers_clear(m, "track2.mp3");
    check(rc == 1, "markers_clear count");
    check(ch_markers_count(m, "track2.mp3") == 0, "markers_count after clear");
    rc = ch_markers_clear(m, "nonexistent");
    check(rc == 0, "markers_clear nonexistent returns 0");

    /* Save/Load */
    char tmp[256];
    snprintf(tmp, sizeof tmp, "/tmp/cyberhex_markers_XXXXXX");
    int fd = mkstemp(tmp);
    if (fd < 0) { perror("mkstemp"); return 1; }
    close(fd);

    rc = ch_markers_save(m, tmp);
    check(rc == 0, "markers_save");

    ch_markers* m2 = ch_markers_create();
    rc = ch_markers_load(m2, tmp);
    check(rc == 0, "markers_load");
    check(ch_markers_count(m2, "track1.mp3") == 1, "loaded count track1");
    check(ch_markers_position(m2, "track1.mp3", 0) == 45.0, "loaded position");
    check(strcmp(ch_markers_name(m2, "track1.mp3", 0), "Verse") == 0, "loaded name");

    /* Load nonexistent returns 0 (empty store) */
    ch_markers* m3 = ch_markers_create();
    rc = ch_markers_load(m3, "/nonexistent/path");
    check(rc == 0, "markers_load nonexistent returns 0");
    check(ch_markers_count(m3, "x") == 0, "loaded empty");

    /* Invalid args */
    check(ch_markers_add(NULL, "x", 1, "x") == -1, "markers_add NULL store");
    check(ch_markers_add(m, NULL, 1, "x") == -1, "markers_add NULL track");
    check(ch_markers_add(m, "x", -1, "x") == -1, "markers_add negative pos");
    check(ch_markers_remove(NULL, "x", 0) == -1, "markers_remove NULL");
    check(ch_markers_clear(NULL, "x") == 0, "markers_clear NULL");
    check(ch_markers_save(NULL, "x") == -1, "markers_save NULL");
    check(ch_markers_save(m, NULL) == -1, "markers_save NULL path");
    check(ch_markers_load(NULL, "x") == -1, "markers_load NULL store");
    check(ch_markers_load(m, NULL) == -1, "markers_load NULL path");

    unlink(tmp);
    ch_markers_destroy(m);
    ch_markers_destroy(m2);
    ch_markers_destroy(m3);

    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}