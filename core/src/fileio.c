#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "fileio.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char* ch_file_read_all(const char* path, uint64_t* size) {
    if (size != NULL) *size = 0;
    if (path == NULL) return NULL;

    FILE* f = fopen(path, "rb");
    if (f == NULL) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    const long len = ftell(f);
    if (len < 0) {
        fclose(f);
        return NULL;
    }
    rewind(f);

    char* data = malloc((size_t)len + 1);
    if (data == NULL) {
        fclose(f);
        return NULL;
    }
    const size_t got = fread(data, 1, (size_t)len, f);
    fclose(f);
    data[got] = '\0';
    if (size != NULL) *size = (uint64_t)got;
    return data;
}

void ch_file_free(char* data) {
    free(data);
}

int32_t ch_file_write_atomic(const char* path, const char* data, uint64_t size) {
    if (path == NULL || data == NULL) return -1;

    const size_t need = strlen(path) + 5;
    char* temp = malloc(need);
    if (temp == NULL) return -1;
    snprintf(temp, need, "%s.tmp", path);

    FILE* f = fopen(temp, "wb");
    if (f == NULL) {
        free(temp);
        return -1;
    }
    const size_t put = fwrite(data, 1, (size_t)size, f);
    if (put != (size_t)size || fclose(f) != 0) {
        remove(temp);
        free(temp);
        return -1;
    }
    if (rename(temp, path) != 0) {
        remove(temp);
        free(temp);
        return -1;
    }
    free(temp);
    return 0;
}
