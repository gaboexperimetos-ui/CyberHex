#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

#include "dirlist.h"
#include "fileio.h"

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
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
    char tmpdir[256];
    snprintf(tmpdir, sizeof tmpdir, "/tmp/cyberhex_dl_XXXXXX");
    char* dir = mkdtemp(tmpdir);
    if (!dir) { perror("mkdtemp"); return 1; }

    char f1[256], f2[256], f3[256], f4[256];
    snprintf(f1, sizeof f1, "%s/track1.wav", dir);
    snprintf(f2, sizeof f2, "%s/track2.flac", dir);
    snprintf(f3, sizeof f3, "%s/track3.mp3", dir);
    snprintf(f4, sizeof f4, "%s/readme.txt", dir);
    check(write_wav(f1) == 0, "write track1.wav");
    check(write_wav(f2) == 0, "write track2.flac (fake)");
    check(write_wav(f3) == 0, "write track3.mp3 (fake)");
    FILE* f = fopen(f4, "w");
    if (f) { fputs("text", f); fclose(f); }

    const char* exts[] = { ".wav", ".flac", ".mp3", NULL };

    int32_t count = 0;
    char* list = ch_dir_list_audio(dir, exts, &count);
    check(list != NULL, "dir_list_audio ok");
    check(count == 3, "dir_list_audio count=3");

    /* Verify all three are in the list */
    int found = 0;
    char* p = list;
    while (*p) {
        char* nl = strchr(p, '\n');
        if (!nl) nl = p + strlen(p);
        if (strstr(p, "track1.wav") || strstr(p, "track2.flac") || strstr(p, "track3.mp3"))
            found++;
        if (!nl) break;
        p = nl + 1;
    }
    check(found == 3, "found all 3 tracks");

    ch_file_free(list);

    /* Subdir not included (non-recursive) */
    char sub[256];
    snprintf(sub, sizeof sub, "%s/sub", dir);
    mkdir(sub, 0755);
    char f5[256];
    snprintf(f5, sizeof f5, "%s/track4.wav", sub);
    write_wav(f5);

    list = ch_dir_list_audio(dir, exts, &count);
    check(list != NULL, "dir_list_audio with subdir");
    check(count == 3, "dir_list_audio still 3 (non-recursive)");
    ch_file_free(list);

    rmdir(sub);

    /* Different extensions */
    const char* exts2[] = { ".txt", NULL };
    list = ch_dir_list_audio(dir, exts2, &count);
    check(list != NULL, "dir_list_audio txt");
    check(count == 1, "dir_list_audio txt count=1");
    check(strstr(list, "readme.txt") != NULL, "found txt");
    ch_file_free(list);

    /* Invalid args */
    check(ch_dir_list_audio(NULL, exts, &count) == NULL, "dir_list_audio NULL dir");
    check(ch_dir_list_audio(dir, NULL, &count) == NULL, "dir_list_audio NULL exts");
    check(ch_dir_list_audio("/nonexistent", exts, &count) == NULL, "dir_list_audio bad dir");

    /* Cleanup */
    unlink(f1); unlink(f2); unlink(f3); unlink(f4); unlink(f5);
    rmdir(dir);

    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}