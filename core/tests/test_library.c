#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

#include "library.h"
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

int main(void) {
    /* Create temp dir structure */
    char tmpdir[256];
    snprintf(tmpdir, sizeof tmpdir, "/tmp/cyberhex_lib_XXXXXX");
    char* dir = mkdtemp(tmpdir);
    if (!dir) { perror("mkdtemp"); return 1; }

    char subdir[256];
    snprintf(subdir, sizeof subdir, "%s/sub", dir);
    mkdir(subdir, 0755);

    /* Create test audio files */
    char f1[256], f2[256], f3[256], f4[256];
    snprintf(f1, sizeof f1, "%s/track1.wav", dir);
    snprintf(f2, sizeof f2, "%s/track2.flac", dir);
    snprintf(f3, sizeof f3, "%s/track3.mp3", subdir);
    snprintf(f4, sizeof f4, "%s/notaudio.txt", dir);
    check(write_wav(f1) == 0, "write track1.wav");
    check(write_wav(f2) == 0, "write track2.flac (fake)");
    check(write_mp3(f3) == 0, "write track3.mp3 (fake)");
    FILE* f = fopen(f4, "w");
    if (f) { fputs("text", f); fclose(f); }

    ch_library* lib = c_lib_create();
    check(lib != NULL, "lib_create");

    /* Scan with defaults */
    int added = c_lib_scan(lib, dir, NULL, 0);
    check(added >= 2, "lib_scan added >=2");
    check(c_lib_count(lib) >= 2, "lib_count >=2");

    /* Check paths */
    int found = 0;
    for (int32_t i = 0; i < c_lib_count(lib); i++) {
        const char* p = c_lib_path(lib, i);
        if (p && (strstr(p, "track1.wav") || strstr(p, "track2.flac") || strstr(p, "track3.mp3")))
            found++;
    }
    check(found >= 2, "found expected files");

    /* Search */
    int32_t count = 0;
    int32_t* idxs = c_lib_search(lib, "track1", &count);
    check(idxs != NULL && count >= 1, "lib_search 'track1'");
    if (idxs) ch_file_free((char*)idxs);

    idxs = c_lib_search(lib, "nonexistent", &count);
    check(idxs == NULL && count == 0, "lib_search nonexistent");

    idxs = c_lib_search(lib, "", &count);
    check(idxs == NULL, "lib_search empty needle");

    idxs = c_lib_search(NULL, "x", &count);
    check(idxs == NULL, "lib_search NULL lib");

    /* Remove */
    int removed = c_lib_remove(lib, f1);
    check(removed == 1, "lib_remove track1");
    check(c_lib_count(lib) == (int32_t)(added - 1), "lib_count after remove");

    removed = c_lib_remove(lib, "/nonexistent");
    check(removed == 0, "lib_remove nonexistent");

    /* Re-scan should re-add removed if file exists */
    added = c_lib_scan(lib, dir, NULL, 0);
    check(added >= 0, "lib_scan second");

    /* Custom extensions */
    ch_library* lib2 = c_lib_create();
    const char* exts[] = { "wav", "txt" };
    added = c_lib_scan(lib2, dir, exts, 2);
    check(added >= 2, "lib_scan custom exts wav+txt");

    /* Invalid args */
    check(c_lib_scan(NULL, dir, NULL, 0) == -1, "lib_scan NULL lib");
    check(c_lib_scan(lib, NULL, NULL, 0) == -1, "lib_scan NULL root");
    check(c_lib_scan(lib, "/nonexistent", NULL, 0) == -1, "lib_scan bad root");
    check(c_lib_count(NULL) == 0, "lib_count NULL");
    check(c_lib_path(NULL, 0) == NULL, "lib_path NULL lib");
    check(c_lib_path(lib, -1) == NULL, "lib_path negative");
    check(c_lib_removed(NULL) == 0, "lib_removed NULL");

    /* Cleanup */
    c_lib_destroy(lib);
    c_lib_destroy(lib2);

    unlink(f1); unlink(f2); unlink(f3); unlink(f4);
    rmdir(subdir);
    rmdir(dir);

    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}