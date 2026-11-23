#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "fileio.h"

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}

int main(void) {
    char tmp[256];
    snprintf(tmp, sizeof tmp, "/tmp/cyberhex_fio_XXXXXX");
    int fd = mkstemp(tmp);
    if (fd < 0) { perror("mkstemp"); return 1; }
    close(fd);
    unlink(tmp);

    /* read_all / free */
    const char* text = "Hello, World!\nUTF-8: \xE2\x9C\x93\n";
    uint64_t size = 0;
    char* data = ch_file_read_all(tmp, &size);
    check(data == NULL, "read_all nonexistent returns NULL");
    check(size == 0, "read_all size 0 for nonexistent");

    /* Write then read */
    int rc = ch_file_write_atomic(tmp, text, strlen(text));
    check(rc == 0, "write_atomic ok");

    data = ch_file_read_all(tmp, &size);
    check(data != NULL, "read_all ok");
    check(size == strlen(text), "read_all size matches");
    check(strcmp(data, text) == 0, "read_all content matches");
    ch_file_free(data);

    /* Atomic write - verify temp file cleanup on failure */
    /* (hard to test without mocking, but check basic overwrite) */
    const char* text2 = "New content";
    rc = ch_file_write_atomic(tmp, text2, strlen(text2));
    check(rc == 0, "write_atomic overwrite");
    data = ch_file_read_all(tmp, &size);
    check(data && strcmp(data, text2) == 0, "overwrite content");
    ch_file_free(data);

    /* Binary data with NUL */
    const char bin[] = { 'a', 'b', '\0', 'c', 'd' };
    rc = ch_file_write_atomic(tmp, bin, sizeof(bin));
    check(rc == 0, "write_atomic binary");
    data = ch_file_read_all(tmp, &size);
    check(data && size == sizeof(bin) && memcmp(data, bin, sizeof(bin)) == 0, "read_all binary");
    ch_file_free(data);

    /* Invalid args */
    check(ch_file_read_all(NULL, &size) == NULL, "read_all NULL path");
    check(ch_file_write_atomic(NULL, "x", 1) == -1, "write_atomic NULL path");
    check(ch_file_write_atomic(tmp, NULL, 1) == -1, "write_atomic NULL data");

    /* free NULL is safe */
    ch_file_free(NULL);

    unlink(tmp);
    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}