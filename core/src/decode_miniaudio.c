#define _DEFAULT_SOURCE 1

#include "decode.h"
#include "miniaudio.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ch_decoder {
    ma_decoder decoder;
    uint32_t out_rate;
    uint32_t out_channels;
    double duration;
    char title[1];
    char artist[1];
    char album[1];
};

static char decoder_error[256];

static void set_error(const char* message) {
    snprintf(decoder_error, sizeof decoder_error, "%s", message);
}

ch_decoder* ch_decode_open(const char* path, uint32_t out_rate, uint32_t out_channels) {
    decoder_error[0] = '\0';
    if (path == NULL || out_rate == 0 || out_channels == 0) {
        set_error("parámetros de decodificación inválidos");
        return NULL;
    }
    struct ch_decoder* d = calloc(1, sizeof *d);
    if (d == NULL) {
        set_error("sin memoria para el decodificador");
        return NULL;
    }
    d->out_rate = out_rate;
    d->out_channels = out_channels;
    d->title[0] = '\0';
    d->artist[0] = '\0';
    d->album[0] = '\0';

    ma_decoder_config config = ma_decoder_config_init(ma_format_f32, out_channels, out_rate);
    if (ma_decoder_init_file(path, &config, &d->decoder) != MA_SUCCESS) {
        set_error("formato no soportado o archivo ilegible");
        free(d);
        return NULL;
    }

    ma_uint64 length = 0;
    if (ma_decoder_get_length_in_pcm_frames(&d->decoder, &length) == MA_SUCCESS && out_rate > 0) {
        d->duration = (double)length / (double)out_rate;
    }
    return d;
}

uint64_t ch_decode_read(ch_decoder* d, float* out, uint64_t frames) {
    if (d == NULL || out == NULL || frames == 0) {
        return 0;
    }
    ma_uint64 read = 0;
    ma_result result = ma_decoder_read_pcm_frames(&d->decoder, out, frames, &read);
    if (result != MA_SUCCESS && result != MA_AT_END) {
        return 0;
    }
    return read;
}

int32_t ch_decode_seek_frame(ch_decoder* d, uint64_t frame) {
    if (d == NULL) {
        return -1;
    }
    return ma_decoder_seek_to_pcm_frame(&d->decoder, frame) == MA_SUCCESS ? 0 : -1;
}

double ch_decode_duration(ch_decoder* d) {
    return d == NULL ? 0.0 : d->duration;
}

const char* ch_decode_title(ch_decoder* d) {
    (void)d;
    return "";
}

const char* ch_decode_artist(ch_decoder* d) {
    (void)d;
    return "";
}

const char* ch_decode_album(ch_decoder* d) {
    (void)d;
    return "";
}

const uint8_t* ch_decode_cover(ch_decoder* d, uint64_t* size) {
    (void)d;
    if (size != NULL) {
        *size = 0;
    }
    return NULL;
}

void ch_decode_close(ch_decoder* d) {
    if (d == NULL) {
        return;
    }
    ma_decoder_uninit(&d->decoder);
    free(d);
}

const char* ch_decode_last_error(void) {
    return decoder_error;
}
