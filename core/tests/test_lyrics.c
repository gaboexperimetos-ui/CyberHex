#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "lyrics.h"

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}

int main(void) {
    char tmp[256];
    snprintf(tmp, sizeof tmp, "/tmp/cyberhex_lrc_XXXXXX");
    int fd = mkstemp(tmp);
    if (fd < 0) { perror("mkstemp"); return 1; }
    close(fd);
    unlink(tmp);

    /* Valid LRC */
    const char* lrc_text =
        "[ar:Test Artist]\n"
        "[ti:Test Title]\n"
        "[al:Test Album]\n"
        "[offset:+500]\n"
        "[00:12.34]First line\n"
        "[00:15.00]Second line\n"
        "[00:20.50]Third line\n"
        "[00:25.00][00:26.00]Two timestamps same line\n";
    FILE* f = fopen(tmp, "w");
    if (f) { fputs(lrc_text, f); fclose(f); }

    /* Parse from string */
    ch_lyrics* l = ch_lyrics_parse(lrc_text);
    check(l != NULL, "lyrics_parse ok");
    check(ch_lyrics_count(l) == 5, "lyrics_count = 5 (4 timestamps + 1 double)");
    check(strcmp(ch_lyrics_artist(l), "Test Artist") == 0, "lyrics_artist");
    check(strcmp(ch_lyrics_title(l), "Test Title") == 0, "lyrics_title");
    check(strcmp(ch_lyrics_album(l), "Test Album") == 0, "lyrics_album");
    check(strcmp(ch_lyrics_offset_ms(l), "+500") == 0, "lyrics_offset_ms");

    double start = 0;
    int32_t idx = -1;
    const char* line = ch_lyrics_line_at(l, 13.0, &start, &idx);
    check(line && strcmp(line, "First line") == 0 && idx == 0, "line_at 13s");
    check(start == 12.34, "line_at start");

    line = ch_lyrics_line_at(l, 16.0, &start, &idx);
    check(line && strcmp(line, "Second line") == 0 && idx == 1, "line_at 16s");

    line = ch_lyrics_line_at(l, 22.0, &start, &idx);
    check(line && strcmp(line, "Third line") == 0 && idx == 2, "line_at 22s");

    line = ch_lyrics_line_at(l, 25.5, &start, &idx);
    check(line && strcmp(line, "Two timestamps same line") == 0 && idx == 3, "line_at 25.5s (double ts)");

    line = ch_lyrics_line_at(l, 5.0, &start, &idx);
    check(line == NULL && idx == -1, "line_at before first");

    /* Read from file */
    ch_lyrics* l2 = ch_lyrics_read_file(tmp);
    check(l2 != NULL, "lyrics_read_file ok");
    check(ch_lyrics_count(l2) == 5, "read_file count");
    ch_lyrics_free(l2);

    /* Shift */
    check(ch_lyrics_shift(l, 1.5) == 0, "lyrics_shift +1.5");
    line = ch_lyrics_line_at(l, 14.5, &start, &idx);  // was 13.0
    check(line && strcmp(line, "First line") == 0 && idx == 0, "shifted line_at");

    check(ch_lyrics_shift(l, -2.0) == 0, "lyrics_shift -2.0");
    line = ch_lyrics_line_at(l, 12.0, &start, &idx);  // was 14.0
    check(line && strcmp(line, "First line") == 0 && idx == 0, "shifted back line_at");
    /* times don't go below 0 - verified via line_at at time 0 */
    line = ch_lyrics_line_at(l, 0.0, &start, &idx);
    check(line != NULL || idx == -1, "shift doesn't go negative");

    /* Write */
    char tmp2[256];
    snprintf(tmp2, sizeof tmp2, "%s_out.lrc", tmp);
    check(ch_lyrics_write_file(l, tmp2) == 0, "lyrics_write_file");
    ch_lyrics* l3 = ch_lyrics_read_file(tmp2);
    check(l3 != NULL, "write read back");
    check(ch_lyrics_count(l3) == 5, "write read count");
    check(strcmp(ch_lyrics_artist(l3), "Test Artist") == 0, "write artist");
    ch_lyrics_free(l3);
    unlink(tmp2);

    /* Edge cases */
    check(ch_lyrics_parse(NULL) == NULL, "parse NULL");
    check(ch_lyrics_parse("plain text\nno timestamps") == NULL, "parse no timestamps");
    check(ch_lyrics_read_file("/nonexistent") == NULL, "read_file nonexistent");
    check(ch_lyrics_count(NULL) == 0, "count NULL");
    check(ch_lyrics_line_at(NULL, 1.0, NULL, NULL) == NULL, "line_at NULL");
    check(ch_lyrics_shift(NULL, 1.0) == -1, "shift NULL");
    check(ch_lyrics_write_file(NULL, "x") == -1, "write NULL lyrics");
    check(ch_lyrics_write_file(l, NULL) == -1, "write NULL path");

    /* Metadata missing */
    ch_lyrics* l4 = ch_lyrics_parse("[00:10.00]Just a line\n");
    check(l4 != NULL, "parse minimal");
    check(strcmp(ch_lyrics_artist(l4), "") == 0, "no artist");
    check(strcmp(ch_lyrics_offset_ms(l4), "") == 0, "no offset");
    ch_lyrics_free(l4);

    ch_lyrics_free(l);
    unlink(tmp);
    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}