#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "audio.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ch_audio {
    ma_device device;
    ma_device_config config;
    ma_context* context;
    ch_render_fn render;
    void* user;
    int32_t s16;
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

/* ------------------------------------------------------------------------- */
/* Dither TPDF de la salida S16 (#30)                                        */
/* ------------------------------------------------------------------------- */

/* PRNG xorshift32 por canal: dos llamadas por muestra y ningun candado (solo
   lo toca el hilo de audio). Estado por canal para que el ruido no se
   correlacione entre izquierda y derecha. */
static uint32_t dither_state[8] = {0x9E3779B9u, 0x85EBCA6Bu, 0xC2B2AE35u, 0x27D4EB2Fu,
                                   0x165667B1u, 0xD3A2646Cu, 0xFD7046C5u, 0xB55A4F09u};

static inline uint32_t dither_next(uint32_t* state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x ? x : 0x9E3779B9u;
    return x;
}

/* Uniforme en [0, 1) sin perder precision: 24 bits del PRNG. */
static inline float dither_uniform(uint32_t* state) {
    return (float)(dither_next(state) >> 8) * (1.0f / 16777216.0f);
}

int16_t ch_audio_quantize_s16(float sample, uint32_t* state) {
    uint32_t local = 0x9E3779B9u;
    uint32_t* prng = state ? state : &local;
    /* TPDF = diferencia de dos uniformes: ruido triangular de +-1 LSB, que es
       el que descorrelaciona el error de cuantizacion sin modular el sonido. */
    const float dither = dither_uniform(prng) - dither_uniform(prng);
    float scaled = sample * 32767.0f + dither;
    if (scaled > 32767.0f) scaled = 32767.0f;
    if (scaled < -32768.0f) scaled = -32768.0f;
    long rounded = lrintf(scaled);
    if (rounded > 32767) rounded = 32767;
    if (rounded < -32768) rounded = -32768;
    return (int16_t)rounded;
}

/* Buffer de render en f32 para el camino s16: estatico y por hilo de audio,
   asi no se reserva memoria dentro del callback. */
#define DITHER_CHUNK_FRAMES 4096
static float render_scratch[DITHER_CHUNK_FRAMES * 8];

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
    if (device->playback.format != ma_format_s16) {
        audio->render(audio->user, (float*)output, frame_count);
        return;
    }

    /* Salida entera: se renderiza en f32 por trozos y se cuantiza con dither. */
    const ma_uint32 channels = device->playback.channels;
    const ma_uint32 chunk_capacity = DITHER_CHUNK_FRAMES;
    int16_t* out = (int16_t*)output;
    ma_uint32 done = 0;
    while (done < frame_count) {
        ma_uint32 chunk = frame_count - done;
        if (chunk > chunk_capacity) {
            chunk = chunk_capacity;
        }
        audio->render(audio->user, render_scratch, chunk);
        for (ma_uint32 i = 0; i < chunk; i++) {
            for (ma_uint32 c = 0; c < channels; c++) {
                const float sample = render_scratch[i * channels + c];
                out[(done + i) * channels + c] =
                    ch_audio_quantize_s16(sample, &dither_state[c % 8]);
            }
        }
        done += chunk;
    }
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

    audio->config = config;
    audio->context = context;
    if (ma_device_init(context, &config, &audio->device) != MA_SUCCESS) {
        set_error("no se pudo abrir el dispositivo de audio");
        free(audio);
        return NULL;
    }
    return audio;
}

int32_t ch_audio_set_s16(void* handle, int32_t enabled) {
    if (handle == NULL) {
        return -1;
    }
    struct ch_audio* audio = (struct ch_audio*)handle;
    if (audio->s16 == (enabled != 0)) {
        return 0;
    }
    audio->s16 = enabled != 0;
    const int was_running = ma_device_is_started(&audio->device);

    /* Reabrir el dispositivo con el formato pedido: miniaudio no deja cambiar
       el formato en caliente. Se conserva el resto de la configuracion. */
    ma_device_uninit(&audio->device);
    audio->config.playback.format = audio->s16 ? ma_format_s16 : ma_format_f32;
    if (ma_device_init(audio->context, &audio->config, &audio->device) != MA_SUCCESS) {
        set_error("no se pudo reabrir el dispositivo en el formato pedido");
        audio->s16 = !audio->s16;
        audio->config.playback.format = audio->s16 ? ma_format_s16 : ma_format_f32;
        ma_device_init(audio->context, &audio->config, &audio->device);
        return -1;
    }
    if (was_running) {
        ma_device_start(&audio->device);
    }
    return 0;
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
