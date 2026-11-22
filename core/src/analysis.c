#define _DEFAULT_SOURCE 1
#define _POSIX_C_SOURCE 200809L

#include "analysis.h"

#include "decode.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

/* Coeficientes de K-weighting (BS.1770) para `fs`. */
typedef struct {
    double b[3];
    double a[2];
    double x1, x2, y1, y2;
} biquad;

static void biquad_reset(biquad* f) {
    f->x1 = f->x2 = f->y1 = f->y2 = 0.0;
}

static double biquad_step(biquad* f, double x) {
    const double y = f->b[0] * x + f->b[1] * f->x1 + f->b[2] * f->x2 -
                     f->a[0] * f->y1 - f->a[1] * f->y2;
    f->x2 = f->x1;
    f->x1 = x;
    f->y2 = f->y1;
    f->y1 = y;
    return y;
}

static void k_weighting(biquad* shelf, biquad* hp, double fs) {
    /* Etapa 1: shelf de altas frecuencias. */
    {
        const double f0 = 1681.974450955533;
        const double G = 3.999843853973347;
        const double Q = 0.7071752369554196;
        const double K = tan(M_PI * f0 / fs);
        const double Vh = pow(10.0, G / 20.0);
        const double Vb = pow(Vh, 0.4996667741545416);
        const double a0 = 1.0 + K / Q + K * K;
        shelf->b[0] = (Vh + Vb * K / Q + K * K) / a0;
        shelf->b[1] = 2.0 * (K * K - Vh) / a0;
        shelf->b[2] = (Vh - Vb * K / Q + K * K) / a0;
        shelf->a[0] = 2.0 * (K * K - 1.0) / a0;
        shelf->a[1] = (1.0 - K / Q + K * K) / a0;
    }
    /* Etapa 2: paso alto. */
    {
        const double f0 = 38.13547087602444;
        const double Q = 0.5003270373238773;
        const double K = tan(M_PI * f0 / fs);
        const double a0 = 1.0 + K / Q + K * K;
        hp->b[0] = 1.0;
        hp->b[1] = -2.0;
        hp->b[2] = 1.0;
        hp->a[0] = 2.0 * (K * K - 1.0) / a0;
        hp->a[1] = (1.0 - K / Q + K * K) / a0;
    }
    biquad_reset(shelf);
    biquad_reset(hp);
}

/* Area de bloque: 400 ms, solape 75% (paso 100 ms). */
typedef struct {
    double* energy;
    int32_t count;
    int32_t cap;
} blocks;

static int push_block(blocks* b, double energy) {
    if (b->count == b->cap) {
        int32_t next = b->cap ? b->cap * 2 : 1024;
        double* grown = realloc(b->energy, (size_t)next * sizeof(double));
        if (grown == NULL) return -1;
        b->energy = grown;
        b->cap = next;
    }
    b->energy[b->count++] = energy;
    return 0;
}

static int32_t scan_loudness(const char* path, ch_loudness_result* out) {
    const uint32_t rate = 48000;
    const uint32_t channels = 2;
    ch_decoder* d = ch_decode_open(path, rate, channels);
    if (d == NULL) return -1;

    biquad shelf = {0};
    biquad hp = {0};
    k_weighting(&shelf, &hp, rate);

    /* Buffer temporal para procesar en bloques. */
    const size_t frames_per_block = rate / 100; /* 10 ms */
    const size_t frames_window = rate * 4 / 10; /* 400 ms */

    float* raw = malloc(frames_per_block * channels * sizeof(float));
    double* ring = calloc(frames_window, sizeof(double));
    blocks b = {0};
    int failed = (raw == NULL || ring == NULL);

    size_t pos = 0;      /* frames escritos en el anillo */
    size_t filled = 0;   /* frames totales leidos */
    size_t last_block = 0;
    const size_t hop = frames_window / 4; /* 100 ms */
    double peak = 0.0;

    while (!failed) {
        const uint64_t got = ch_decode_read(d, raw, frames_per_block);
        if (got == 0) break;
        for (size_t i = 0; i < got; i++) {
            const double l = biquad_step(&shelf, raw[i * channels]);
            const double r = biquad_step(&shelf, raw[i * channels + 1]);
            const double yl = biquad_step(&hp, l);
            const double yr = biquad_step(&hp, r);
            ring[pos % frames_window] = yl * yl + yr * yr;
            pos++;
            filled++;

            const double al = fabs((double)raw[i * channels]);
            const double ar = fabs((double)raw[i * channels + 1]);
            const double m = al > ar ? al : ar;
            if (m > peak) peak = m;
        }
        /* Un bloque cada 100 ms una vez llena la ventana de 400 ms. */
        if (filled >= frames_window && filled - last_block >= hop) {
            const size_t start = pos - frames_window;
            double sum = 0.0;
            for (size_t i = 0; i < frames_window; i++) {
                sum += ring[(start + i) % frames_window];
            }
            if (push_block(&b, sum / (double)frames_window) != 0) {
                failed = 1;
                break;
            }
            last_block = filled;
        }
    }

    ch_decode_close(d);
    free(raw);
    free(ring);

    if (failed) {
        free(b.energy);
        return -1;
    }

    /* Gate absoluto -70 LUFS: energy > 10^((-70+0.691)/10). */
    const double abs_threshold = pow(10.0, (-70.0 + 0.691) / 10.0);
    double* kept = malloc((size_t)(b.count > 0 ? b.count : 1) * sizeof(double));
    if (kept == NULL) {
        free(b.energy);
        return -1;
    }
    int32_t n = 0;
    for (int32_t i = 0; i < b.count; i++) {
        if (b.energy[i] > abs_threshold) kept[n++] = b.energy[i];
    }

    double lufs = -70.0;
    if (n > 0) {
        double sum = 0.0;
        for (int32_t i = 0; i < n; i++) sum += kept[i];
        const double mean = sum / n;
        const double ungated = -0.691 + 10.0 * log10(mean);

        /* Puerta relativa -10 LU. */
        const double rel_threshold = pow(10.0, (ungated - 10.0 + 0.691) / 10.0);
        double kept2 = 0.0;
        int32_t n2 = 0;
        for (int32_t i = 0; i < n; i++) {
            if (kept[i] >= rel_threshold) {
                kept2 += kept[i];
                n2++;
            }
        }
        lufs = n2 > 0 ? -0.691 + 10.0 * log10(kept2 / n2) : ungated;
    }
    free(kept);
    free(b.energy);

    out->integrated_lufs = lufs;
    out->sample_peak_dbfs = peak > 0.0 ? 20.0 * log10(peak) : -120.0;
    out->duration_s = (double)filled / (double)rate;
    return 0;
}

int32_t ch_loudness_scan(const char* path, ch_loudness_result* out) {
    if (path == NULL || out == NULL) return -1;
    return scan_loudness(path, out);
}

int32_t ch_waveform_peaks(const char* path, uint32_t buckets, float* out_max) {
    if (path == NULL || out_max == NULL || buckets == 0) return -1;
    const uint32_t rate = 8000;
    ch_decoder* d = ch_decode_open(path, rate, 1);
    if (d == NULL) return -1;

    for (uint32_t i = 0; i < buckets; i++) out_max[i] = 0.0f;
    const double total = ch_decode_duration(d);
    const double bucket_seconds = total > 0 ? total / (double)buckets : 0.0;

    float buf[1024];
    uint64_t total_frames = 0;
    uint32_t index = 0;
    double bucket_end = bucket_seconds;

    for (;;) {
        const uint64_t got = ch_decode_read(d, buf, 1024);
        if (got == 0) break;
        for (uint64_t i = 0; i < got; i++) {
            const double t = (double)(total_frames + i) / (double)rate;
            if (bucket_seconds > 0 && t >= bucket_end && index + 1 < buckets) {
                index++;
                bucket_end += bucket_seconds;
            }
            const float v = fabsf(buf[i]);
            if (v > out_max[index]) out_max[index] = v;
        }
        total_frames += got;
    }
    ch_decode_close(d);
    return 0;
}
/* ------------------------------------------------------------------------- */
/* Deteccion de BPM                                                          */
/* ------------------------------------------------------------------------- */

int32_t ch_bpm_detect(const char* path, double* out_bpm) {
    if (path == NULL || out_bpm == NULL) return -1;
    const uint32_t rate = 11025;
    const uint32_t hop = 256;
    ch_decoder* d = ch_decode_open(path, rate, 1);
    if (d == NULL) return -1;

    double* env = NULL;
    size_t nenv = 0, cap = 0;
    float buf[hop];
    for (;;) {
        const uint64_t got = ch_decode_read(d, buf, hop);
        if (got == 0) break;
        double sum = 0.0;
        for (uint64_t i = 0; i < got; i++) sum += (double)buf[i] * (double)buf[i];
        const double rms = sqrt(sum / (double)got) + 1e-9;
        if (nenv == cap) {
            const size_t nc = cap ? cap * 2 : 4096;
            double* tmp = realloc(env, nc * sizeof(double));
            if (!tmp) { free(env); ch_decode_close(d); return -2; }
            env = tmp;
            cap = nc;
        }
        env[nenv++] = log(rms);
        if (got < hop) break;
    }
    ch_decode_close(d);
    if (nenv < 64) { free(env); return -3; }

    /* Envolvente de novedad: solo incrementos de energia. */
    for (size_t i = nenv - 1; i > 0; i--) {
        double diff = env[i] - env[i - 1];
        env[i] = diff > 0.0 ? diff : 0.0;
    }
    env[0] = 0.0;

    const double hops_per_sec = (double)rate / (double)hop;
    const double min_bpm = 60.0, max_bpm = 200.0;
    size_t lag_lo = (size_t)(hops_per_sec * 60.0 / max_bpm);
    size_t lag_hi = (size_t)(hops_per_sec * 60.0 / min_bpm) + 1;
    if (lag_lo < 2) lag_lo = 2;
    if (lag_hi >= nenv) lag_hi = nenv - 1;
    if (lag_hi <= lag_lo) { free(env); return -3; }

    double best = -1.0;
    size_t best_lag = lag_lo;
    for (size_t lag = lag_lo; lag <= lag_hi; lag++) {
        double acc = 0.0;
        for (size_t i = 0; i + lag < nenv; i++) acc += env[i] * env[i + lag];
        acc /= (double)(nenv - lag);
        /* Prior suave hacia 120 BPM para evitar el doble/medio tempo. */
        const double bpm = 60.0 * hops_per_sec / (double)lag;
        const double w = exp(-0.5 * pow(log2(bpm / 120.0) / 0.7, 2.0));
        acc *= 0.5 + 0.5 * w;
        if (acc > best) { best = acc; best_lag = lag; }
    }

    /* Interpolacion parabolica con los vecinos. */
    double frac = 0.0;
    if (best_lag > lag_lo && best_lag < lag_hi) {
        double y0 = 0, y1 = 0, y2 = 0;
        for (size_t lag = best_lag - 1; lag <= best_lag + 1; lag++) {
            double acc = 0.0;
            for (size_t i = 0; i + lag < nenv; i++) acc += env[i] * env[i + lag];
            acc /= (double)(nenv - lag);
            if (lag == best_lag - 1) y0 = acc;
            else if (lag == best_lag) y1 = acc;
            else y2 = acc;
        }
        const double denom = (y0 - 2.0 * y1 + y2);
        if (fabs(denom) > 1e-12) frac = 0.5 * (y0 - y2) / denom;
        if (frac < -0.5) frac = -0.5;
        if (frac > 0.5) frac = 0.5;
    }
    free(env);

    double bpm = 60.0 * hops_per_sec / ((double)best_lag + frac);
    while (bpm < 70.0) bpm *= 2.0;
    while (bpm > 180.0) bpm *= 0.5;
    *out_bpm = bpm;
    return 0;
}

/* ------------------------------------------------------------------------- */
/* Medidor DR (rango dinamico)                                               */
/* ------------------------------------------------------------------------- */

int32_t ch_dr_measure(const char* path, double* out_dr, uint32_t* out_blocks) {
    if (path == NULL || out_dr == NULL) return -1;
    const uint32_t rate = 44100;
    const uint64_t win = (uint64_t)rate * 3; /* bloques de 3 s */
    ch_decoder* d = ch_decode_open(path, rate, 1);
    if (d == NULL) return -1;

    double sum_dr = 0.0;
    uint32_t used = 0;
    uint64_t in_win = 0;
    double peak = 0.0, sumsq = 0.0;
    uint64_t count = 0;
    float buf[4096];

    for (;;) {
        const uint64_t got = ch_decode_read(d, buf, 4096);
        if (got == 0) break;
        for (uint64_t i = 0; i < got; i++) {
            const double s = (double)buf[i];
            const double a = fabs(s);
            if (a > peak) peak = a;
            sumsq += s * s;
            count++;
            if (++in_win >= win) {
                if (count > 0 && peak > 0.0 && sumsq > 0.0) {
                    const double rms = sqrt(sumsq / (double)count);
                    const double db = 20.0 * log10(peak) - 20.0 * log10(rms);
                    if (rms > 1e-4 && db > 0.0) { sum_dr += db; used++; }
                }
                in_win = 0;
                peak = 0.0;
                sumsq = 0.0;
                count = 0;
            }
        }
    }
    /* Resto final (si dura al menos 1 s). */
    if (in_win > rate / 2 && count > 0 && peak > 0.0 && sumsq > 0.0) {
        const double rms = sqrt(sumsq / (double)count);
        const double db = 20.0 * log10(peak) - 20.0 * log10(rms);
        if (rms > 1e-4 && db > 0.0) { sum_dr += db; used++; }
    }
    ch_decode_close(d);
    if (used == 0) return -3;
    *out_dr = sum_dr / (double)used;
    if (out_blocks) *out_blocks = used;
    return 0;
}
