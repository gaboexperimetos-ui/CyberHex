#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

#include "playlist.h"

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}

static int write_m3u(const char* path, const char* content) {
    FILE* f = fopen(path, "w");
    if (!f) return -1;
    fputs(content, f);
    fclose(f);
    return 0;
}

int main(void) {
    char tmp[256];
    snprintf(tmp, sizeof tmp, "/tmp/cyberhex_pl_XXXXXX");
    int fd = mkstemp(tmp);
    if (fd < 0) { perror("mkstemp"); return 1; }
    close(fd);
    unlink(tmp);

    /* Valid M3U */
    const char* m3u =
        "#EXTM3U\n"
        "#EXTINF:180,Test - Title\n"
        "track1.wav\n"
        "track2.mp3\n"
        "sub/track3.flac\n";
    check(write_m3u(tmp, m3u) == 0, "write m3u");

    ch_playlist pl = ch_playlist_read(tmp);
    check(pl.count == 3, "playlist_read count=3");
    check(pl.items != NULL, "playlist_read items");
    if (pl.items) {
        check(strstr(pl.items[0], "track1.wav") != NULL, "item 0");
        check(strstr(pl.items[1], "track2.mp3") != NULL, "item 1");
        check(strstr(pl.items[2], "track3.flac") != NULL, "item 2");
    }
    ch_playlist_free(&pl);

    /* M3U with relative paths */
    char sub[256];
    snprintf(sub, sizeof sub, "%s/sub", tmp);
    mkdir(sub, 0755);
    const char* m3u_rel =
        "#EXTM3U\n"
        "sub/track1.wav\n"
        "track2.wav\n";
    check(write_m3u(tmp, m3u_rel) == 0, "write m3u rel");
    pl = ch_playlist_read(tmp);
    check(pl.count == 2, "playlist_read rel count");
    ch_playlist_free(&pl);
    rmdir(sub);

    /* PLS format */
    const char* pls =
        "[playlist]\n"
        "File1=/absolute/track1.wav\n"
        "Title1=Track One\n"
        "File2=track2.mp3\n"
        "NumberOfEntries=2\n";
    check(write_m3u(tmp, pls) == 0, "write pls");
    pl = ch_playlist_read(tmp);
    check(pl.count == 2, "playlist_read pls count");
    ch_playlist_free(&pl);

    /* Empty/Comment only */
    const char* m3u_empty = "#EXTM3U\n# Comment\n";
    check(write_m3u(tmp, m3u_empty) == 0, "write empty m3u");
    pl = ch_playlist_read(tmp);
    check(pl.count == 0 && pl.items == NULL, "playlist_read empty");
    if (pl.items) ch_playlist_free(&pl);

    /* UTF-8 BOM */
    const char* m3u_bom = "\xEF\xBB\xBF#EXTM3U\ntrack.wav\n";
    check(write_m3u(tmp, m3u_bom) == 0, "write bom m3u");
    pl = ch_playlist_read(tmp);
    check(pl.count == 1, "playlist_read bom");
    ch_playlist_free(&pl);

    /* Write playlist */
    const char* items[] = { "/path/track1.wav", "/path/track2.mp3" };
    check(ch_playlist_write(tmp, items, 2) == 0, "playlist_write");
    pl = ch_playlist_read(tmp);
    check(pl.count == 2, "playlist_write roundtrip");
    ch_playlist_free(&pl);

    /* Invalid args */
    check(ch_playlist_read(NULL).count == -1, "playlist_read NULL");
    check(ch_playlist_write(NULL, items, 2) == -1, "playlist_write NULL path");
    check(ch_playlist_write(tmp, NULL, 2) == -1, "playlist_write NULL items");
    check(ch_playlist_write(tmp, items, -1) == -1, "playlist_write negative count");
    check(ch_playlist_write(tmp, items, 0) == 0, "playlist_write zero count");

    ch_playlist_free(NULL);

    unlink(tmp);
    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}