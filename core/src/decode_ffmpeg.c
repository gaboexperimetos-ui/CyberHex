#define _DEFAULT_SOURCE 1

#include "decode.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/mathematics.h>
#include <libswresample/swresample.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ch_decoder {
    AVFormatContext* fmt;
    AVCodecContext* codec;
    SwrContext* swr;
    AVPacket* packet;
    AVFrame* frame;

    int stream_index;
    int packet_pending;
    int send_eof;
    int eof;

    uint32_t out_rate;
    uint32_t out_channels;

    float* fifo;      /* muestras entrelazadas */
    size_t fifo_cap;  /* muestras */
    size_t fifo_len;
    size_t fifo_read;

    char* title;
    char* artist;
    char* album;
    uint8_t* cover;
    size_t cover_size;

    double duration;
};

static char decoder_error[256];

static void set_error(const char* message) {
    snprintf(decoder_error, sizeof decoder_error, "%s", message);
}

static void set_av_error(int code, const char* prefix) {
    char detail[AV_ERROR_MAX_STRING_SIZE];
    if (av_strerror(code, detail, sizeof detail) < 0) {
        snprintf(detail, sizeof detail, "error %d", code);
    }
    snprintf(decoder_error, sizeof decoder_error, "%s: %s", prefix, detail);
}

static char* dup_string(const char* value) {
    if (value == NULL || value[0] == '\0') {
        return NULL;
    }
    const size_t len = strlen(value);
    char* copy = malloc(len + 1);
    if (copy != NULL) {
        memcpy(copy, value, len + 1);
    }
    return copy;
}

static char* dict_value(AVDictionary* dict, const char* key) {
    if (dict == NULL) {
        return NULL;
    }
    AVDictionaryEntry* entry = av_dict_get(dict, key, NULL, 0);
    if (entry == NULL) {
        return NULL;
    }
    return dup_string(entry->value);
}

static void read_metadata(struct ch_decoder* d) {
    AVStream* stream = d->fmt->streams[d->stream_index];
    d->title = dict_value(d->fmt->metadata, "title");
    if (d->title == NULL) d->title = dict_value(stream->metadata, "title");
    d->artist = dict_value(d->fmt->metadata, "artist");
    if (d->artist == NULL) d->artist = dict_value(stream->metadata, "artist");
    d->album = dict_value(d->fmt->metadata, "album");
    if (d->album == NULL) d->album = dict_value(stream->metadata, "album");

    for (unsigned i = 0; i < d->fmt->nb_streams; i++) {
        AVStream* s = d->fmt->streams[i];
        if ((s->disposition & AV_DISPOSITION_ATTACHED_PIC) != 0 &&
            s->attached_pic.data != NULL && s->attached_pic.size > 0) {
            d->cover = malloc((size_t)s->attached_pic.size);
            if (d->cover != NULL) {
                memcpy(d->cover, s->attached_pic.data, (size_t)s->attached_pic.size);
                d->cover_size = (size_t)s->attached_pic.size;
            }
            break;
        }
    }
}

static double read_duration(struct ch_decoder* d) {
    if (d->fmt->duration != AV_NOPTS_VALUE && d->fmt->duration > 0) {
        return (double)d->fmt->duration / (double)AV_TIME_BASE;
    }
    AVStream* stream = d->fmt->streams[d->stream_index];
    if (stream->duration != AV_NOPTS_VALUE && stream->duration > 0) {
        return (double)stream->duration * av_q2d(stream->time_base);
    }
    return 0.0;
}

static int ensure_fifo(struct ch_decoder* d, size_t extra_samples) {
    if (d->fifo_read > 0 && d->fifo_len + extra_samples > d->fifo_cap) {
        const size_t remaining = d->fifo_len - d->fifo_read;
        if (remaining > 0) {
            memmove(d->fifo, d->fifo + d->fifo_read, remaining * sizeof(float));
        }
        d->fifo_len = remaining;
        d->fifo_read = 0;
    }
    const size_t needed = d->fifo_len + extra_samples;
    if (needed <= d->fifo_cap) {
        return 0;
    }
    size_t cap = d->fifo_cap == 0 ? 16384 : d->fifo_cap;
    while (cap < needed) {
        cap *= 2;
    }
    float* grown = realloc(d->fifo, cap * sizeof(float));
    if (grown == NULL) {
        set_error("sin memoria para el búfer de decodificación");
        return -1;
    }
    d->fifo = grown;
    d->fifo_cap = cap;
    return 0;
}

static int ensure_swr(struct ch_decoder* d, const AVFrame* frame) {
    if (d->swr != NULL) {
        return 0;
    }
    const AVChannelLayout* in_layout = &frame->ch_layout;
    if (in_layout->nb_channels == 0) {
        in_layout = &d->codec->ch_layout;
    }
    AVChannelLayout out_layout;
    av_channel_layout_default(&out_layout, (int)d->out_channels);
    int ret = swr_alloc_set_opts2(
        &d->swr,
        &out_layout, AV_SAMPLE_FMT_FLT, (int)d->out_rate,
        in_layout, (enum AVSampleFormat)frame->format, frame->sample_rate,
        0, NULL);
    av_channel_layout_uninit(&out_layout);
    if (ret < 0 || d->swr == NULL) {
        set_av_error(ret, "no se pudo configurar la conversión de audio");
        return -1;
    }
    ret = swr_init(d->swr);
    if (ret < 0) {
        set_av_error(ret, "no se pudo inicializar la conversión de audio");
        return -1;
    }
    return 0;
}

static int append_frame(struct ch_decoder* d) {
    if (ensure_swr(d, d->frame) != 0) {
        return -1;
    }
    const int out_samples = swr_get_out_samples(d->swr, d->frame->nb_samples);
    if (out_samples <= 0) {
        return 0;
    }
    const size_t extra = (size_t)out_samples * d->out_channels;
    if (ensure_fifo(d, extra) != 0) {
        return -1;
    }
    uint8_t* out_data[1] = { (uint8_t*)(d->fifo + d->fifo_len) };
    const int got = swr_convert(
        d->swr, out_data, out_samples,
        (const uint8_t* const*)d->frame->extended_data, d->frame->nb_samples);
    if (got < 0) {
        set_av_error(got, "error al convertir audio");
        return -1;
    }
    d->fifo_len += (size_t)got * d->out_channels;
    return 0;
}

static void flush_resampler(struct ch_decoder* d) {
    if (d->swr == NULL) {
        return;
    }
    for (;;) {
        const int limit = 4096;
        const size_t extra = (size_t)limit * d->out_channels;
        if (ensure_fifo(d, extra) != 0) {
            return;
        }
        uint8_t* out_data[1] = { (uint8_t*)(d->fifo + d->fifo_len) };
        const int got = swr_convert(d->swr, out_data, limit, NULL, 0);
        if (got <= 0) {
            return;
        }
        d->fifo_len += (size_t)got * d->out_channels;
    }
}

static int decode_next_frame(struct ch_decoder* d) {
    for (;;) {
        int ret = avcodec_receive_frame(d->codec, d->frame);
        if (ret == 0) {
            return append_frame(d);
        }
        if (ret == AVERROR_EOF) {
            flush_resampler(d);
            d->eof = 1;
            return 1;
        }
        if (ret != AVERROR(EAGAIN)) {
            set_av_error(ret, "error al decodificar el audio");
            d->eof = 1;
            return 1;
        }
        if (d->send_eof) {
            flush_resampler(d);
            d->eof = 1;
            return 1;
        }
        if (d->packet_pending) {
            ret = avcodec_send_packet(d->codec, d->packet);
            av_packet_unref(d->packet);
            d->packet_pending = 0;
            if (ret < 0 && ret != AVERROR(EAGAIN)) {
                set_av_error(ret, "error al enviar datos al decodificador");
                d->eof = 1;
                return 1;
            }
            continue;
        }
        ret = av_read_frame(d->fmt, d->packet);
        if (ret < 0) {
            avcodec_send_packet(d->codec, NULL);
            d->send_eof = 1;
            continue;
        }
        if (d->packet->stream_index != d->stream_index) {
            av_packet_unref(d->packet);
            continue;
        }
        d->packet_pending = 1;
    }
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
    d->stream_index = -1;

    int ret = avformat_open_input(&d->fmt, path, NULL, NULL);
    if (ret < 0) {
        set_av_error(ret, "no se pudo abrir el archivo");
        free(d);
        return NULL;
    }
    ret = avformat_find_stream_info(d->fmt, NULL);
    if (ret < 0) {
        set_av_error(ret, "no se pudo leer la información del archivo");
        ch_decode_close(d);
        return NULL;
    }

    const AVCodec* codec = NULL;
    ret = av_find_best_stream(d->fmt, AVMEDIA_TYPE_AUDIO, -1, -1, &codec, 0);
    if (ret < 0 || codec == NULL) {
        set_error("el archivo no contiene audio compatible");
        ch_decode_close(d);
        return NULL;
    }
    d->stream_index = ret;

    d->codec = avcodec_alloc_context3(codec);
    if (d->codec == NULL) {
        set_error("sin memoria para el códec");
        ch_decode_close(d);
        return NULL;
    }
    ret = avcodec_parameters_to_context(d->codec, d->fmt->streams[d->stream_index]->codecpar);
    if (ret < 0) {
        set_av_error(ret, "no se pudo preparar el códec");
        ch_decode_close(d);
        return NULL;
    }
    d->codec->pkt_timebase = d->fmt->streams[d->stream_index]->time_base;
    ret = avcodec_open2(d->codec, codec, NULL);
    if (ret < 0) {
        set_av_error(ret, "no se pudo abrir el códec");
        ch_decode_close(d);
        return NULL;
    }

    d->packet = av_packet_alloc();
    d->frame = av_frame_alloc();
    if (d->packet == NULL || d->frame == NULL) {
        set_error("sin memoria para el decodificador");
        ch_decode_close(d);
        return NULL;
    }

    read_metadata(d);
    d->duration = read_duration(d);
    return d;
}

uint64_t ch_decode_read(ch_decoder* d, float* out, uint64_t frames) {
    if (d == NULL || out == NULL || frames == 0) {
        return 0;
    }
    const size_t want = (size_t)frames;
    size_t filled = 0;
    while (filled < want) {
        const size_t available = (d->fifo_len - d->fifo_read) / d->out_channels;
        if (available > 0) {
            const size_t take = available < (want - filled) ? available : (want - filled);
            memcpy(
                out + filled * d->out_channels,
                d->fifo + d->fifo_read,
                take * d->out_channels * sizeof(float));
            d->fifo_read += take * d->out_channels;
            filled += take;
            if (d->fifo_read == d->fifo_len) {
                d->fifo_read = 0;
                d->fifo_len = 0;
            }
            continue;
        }
        if (d->eof) {
            break;
        }
        if (decode_next_frame(d) != 0) {
            continue;
        }
    }
    return (uint64_t)filled;
}

int32_t ch_decode_seek_frame(ch_decoder* d, uint64_t frame) {
    if (d == NULL) {
        return -1;
    }
    AVStream* stream = d->fmt->streams[d->stream_index];
    const AVRational out_tb = { 1, (int)d->out_rate };
    const int64_t ts = av_rescale_q((int64_t)frame, out_tb, stream->time_base);
    int ret = av_seek_frame(d->fmt, d->stream_index, ts, AVSEEK_FLAG_BACKWARD);
    if (ret < 0) {
        set_av_error(ret, "no se pudo hacer seek");
        return -1;
    }
    avcodec_flush_buffers(d->codec);
    if (d->packet_pending) {
        av_packet_unref(d->packet);
        d->packet_pending = 0;
    }
    swr_free(&d->swr);
    d->fifo_len = 0;
    d->fifo_read = 0;
    d->eof = 0;
    d->send_eof = 0;
    return 0;
}

double ch_decode_duration(ch_decoder* d) {
    return d == NULL ? 0.0 : d->duration;
}

const char* ch_decode_title(ch_decoder* d) {
    return (d == NULL || d->title == NULL) ? "" : d->title;
}

const char* ch_decode_artist(ch_decoder* d) {
    return (d == NULL || d->artist == NULL) ? "" : d->artist;
}

const char* ch_decode_album(ch_decoder* d) {
    return (d == NULL || d->album == NULL) ? "" : d->album;
}

const uint8_t* ch_decode_cover(ch_decoder* d, uint64_t* size) {
    if (size != NULL) {
        *size = (d == NULL) ? 0 : (uint64_t)d->cover_size;
    }
    return (d == NULL) ? NULL : d->cover;
}

void ch_decode_close(ch_decoder* d) {
    if (d == NULL) {
        return;
    }
    swr_free(&d->swr);
    av_frame_free(&d->frame);
    av_packet_free(&d->packet);
    avcodec_free_context(&d->codec);
    avformat_close_input(&d->fmt);
    free(d->fifo);
    free(d->title);
    free(d->artist);
    free(d->album);
    free(d->cover);
    free(d);
}

const char* ch_decode_last_error(void) {
    return decoder_error;
}
