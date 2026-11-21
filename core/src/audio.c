#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "audio.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ch_audio {
    ma_device device;
    ch_render_fn render;
    void* user;
};

struct ch_decoder {
    ma_decoder decoder;
};

static char audio_error[256];

static ma_context g_context;
static int g_context_ready = 0;
static ma_device_info g_devices[32];
static ma_uint32 g_device_count = 0;

static void set_error(const char* message) {
    snprintf(audio_error, sizeof audio_error, "%s", message);
}

static int ensure_context(void) {
    if (g_context_ready) {
        return 0;
    }
    if (ma_context_init(NULL, 0, NULL, &g_context) != MA_SUCCESS) {
        set_error("no se pudo inicializar el contexto de audio");
        return -1;
    }
    ma_device_info* playback = NULL;
    ma_uint32 count = 0;
    if (ma_context_get_devices(&g_context, &playback, &count, NULL, NULL) != MA_SUCCESS) {
        set_error("no se pudieron enumerar los dispositivos de audio");
        g_context_ready = 1;
        g_device_count = 0;
        return 0;
    }
    g_device_count = count < 32 ? count : 32;
    for (ma_uint32 i = 0; i < g_device_count; i++) {
        g_devices[i] = playback[i];
    }
    g_context_ready = 1;
    return 0;
}

int32_t ch_audio_device_count(void) {
    ensure_context();
    return (int32_t)g_device_count;
}

const char* ch_audio_device_name(int32_t index) {
    ensure_context();
    if (index < 0 || (ma_uint32)index >= g_device_count) {
        return "";
    }
    return g_devices[index].name;
}

int32_t ch_audio_default_device(void) {
    ensure_context();
    return g_device_count > 0 ? 0 : -1;
}

const char* ch_audio_last_error(void) {
    return audio_error;
}

static void on_data(ma_device* device, void* output, const void* input, ma_uint32 frame_count) {
    (void)input;
    struct ch_audio* audio = (struct ch_audio*)device->pUserData;
    if (output == NULL) {
        return;
    }
    if (audio == NULL || audio->render == NULL) {
        memset(output, 0, (size_t)frame_count * ma_get_bytes_per_frame(device->playback.format, device->playback.channels));
        return;
    }
    audio->render(audio->user, (float*)output, frame_count);
}

void* ch_audio_create(ch_render_fn render, void* user, uint32_t sample_rate, uint32_t channels, int32_t device_index) {
    if (channels == 0 || sample_rate == 0) {
        set_error("configuración de audio inválida");
        return NULL;
    }
    struct ch_audio* audio = calloc(1, sizeof *audio);
    if (audio == NULL) {
        set_error("sin memoria para el dispositivo de audio");
        return NULL;
    }
    audio->render = render;
    audio->user = user;

    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = channels;
    config.sampleRate = sample_rate;
    config.dataCallback = on_data;
    config.pUserData = audio;

    ma_context* context = NULL;
    if (ensure_context() == 0 && g_device_count > 0) {
        context = &g_context;
        if (device_index >= 0 && (ma_uint32)device_index < g_device_count) {
            config.playback.pDeviceID = &g_devices[device_index].id;
        }
    } else if (device_index > 0) {
        set_error("dispositivo de audio no disponible");
        free(audio);
        return NULL;
    }

    if (ma_device_init(context, &config, &audio->device) != MA_SUCCESS) {
        set_error("no se pudo abrir el dispositivo de audio");
        free(audio);
        return NULL;
    }
    return audio;
}

void ch_audio_destroy(void* handle) {
    if (handle == NULL) {
        return;
    }
    struct ch_audio* audio = (struct ch_audio*)handle;
    ma_device_uninit(&audio->device);
    free(audio);
}

int32_t ch_audio_start(void* handle) {
    if (handle == NULL) {
        return -1;
    }
    struct ch_audio* audio = (struct ch_audio*)handle;
    return ma_device_start(&audio->device) == MA_SUCCESS ? 0 : -1;
}

int32_t ch_audio_stop(void* handle) {
    if (handle == NULL) {
        return -1;
    }
    struct ch_audio* audio = (struct ch_audio*)handle;
    return ma_device_stop(&audio->device) == MA_SUCCESS ? 0 : -1;
}

ch_decoder* ch_decoder_open(const char* path, uint32_t sample_rate, uint32_t channels) {
    if (path == NULL) {
        set_error("ruta nula");
        return NULL;
    }
    ch_decoder* decoder = calloc(1, sizeof *decoder);
    if (decoder == NULL) {
        set_error("sin memoria para el decodificador");
        return NULL;
    }
    ma_decoder_config config = ma_decoder_config_init(ma_format_f32, channels, sample_rate);
    if (ma_decoder_init_file(path, &config, &decoder->decoder) != MA_SUCCESS) {
        set_error("formato no soportado o archivo ilegible");
        free(decoder);
        return NULL;
    }
    return decoder;
}

uint64_t ch_decoder_read(ch_decoder* decoder, float* out, uint64_t frames) {
    if (decoder == NULL || out == NULL || frames == 0) {
        return 0;
    }
    ma_uint64 read = 0;
    ma_result result = ma_decoder_read_pcm_frames(&decoder->decoder, out, frames, &read);
    if (result != MA_SUCCESS && result != MA_AT_END) {
        return 0;
    }
    return read;
}

void ch_decoder_close(ch_decoder* decoder) {
    if (decoder == NULL) {
        return;
    }
    ma_decoder_uninit(&decoder->decoder);
    free(decoder);
}
