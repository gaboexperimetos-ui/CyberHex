#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

#include "analysis.h"

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "FAIL", what);
    if (!ok) failures++;
}

static int near_d(double a, double b, double tol) {
    return (a > b ? a - b : b - a) <= tol;
}

static int write_wav(const char* path, double seconds, double hz) {
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    const uint32_t rate = 48000;
    const uint32_t ch = 2;
    const uint32_t frames = (uint32_t)(seconds * rate);
    const uint32_t data_bytes = frames * ch * 2;
    uint8_t hdr[44] = {0};
    memcpy(hdr, "RIFF", 4);
    uint32_t chunk = 36 + data_bytes;
    memcpy(hdr + 4, &chunk, 4);
    memcpy(hdr + 8, "WAVEfmt ", 8);
    uint32_t fmt_len = 16;
    uint16_t fmt = 1;
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
    memcpy(hdr + 40, &data_bytes, 4);
    fwrite(hdr, 1, 44, f);
    const uint32_t period = (uint32_t)((double)rate / hz);
    for (uint32_t i = 0; i < frames; i++) {
        const int16_t v = (i % period) < (period / 2) ? (int16_t)(0.5 * 32767.0)
                                                      : (int16_t)(-0.5 * 32767.0);
        const int16_t pair[2] = {v, v};
        fwrite(pair, sizeof(int16_t), 2, f);
    }
    fclose(f);
    return 0;
}

int main(void) {
    char tmp[256];
    snprintf(tmp, sizeof tmp, "/tmp/cyberhex_analysis_XXXXXX");
    int fd = mkstemp(tmp);
    if (fd < 0) { perror("mkstemp"); return 1; }
    close(fd);
    unlink(tmp);

    /* Generate test WAV */
    char wav[256];
    snprintf(wav, sizeof wav, "%s.wav", tmp);
    check(write_wav(wav, 2.0, 440.0) == 0, "wav generado");

    /* Loudness scan */
    ch_loudness_result lr = {0};
    int rc = ch_loudness_scan(wav, &lr);
    check(rc == 0, "loudness_scan ok");
    check(near_d(lr.integrated_lufs, -3.0, 1.0), "loudness ~ -3 LUFS (square wave)");
    check(lr.duration_s > 1.9 && lr.duration_s < 2.1, "duration ~2s");
    check(lr.sample_peak_dbfs <= 0.0 && lr.sample_peak_dbfs > -10.0, "peak dBFS razonable (K-weighted peak)");

    /* Waveform peaks */
    const uint32_t buckets = 100;
    float* peaks = calloc(buckets, sizeof(float));
    check(peaks != NULL, "malloc peaks");
    rc = ch_waveform_peaks(wav, buckets, peaks);
    check(rc == 0, "waveform_peaks ok");
    int non_zero = 0;
    for (uint32_t i = 0; i < buckets; i++) if (peaks[i] > 0) non_zero++;
    check(non_zero > 0, "waveform peaks tiene valores > 0");
    free(peaks);

    /* BPM detect */
    double bpm = 0;
    rc = ch_bpm_detect(wav, &bpm);
    check(rc == 0 || rc == -3, "bpm_detect (puede fallar en tono puro)");
    if (rc == 0) {
        printf("     bpm detectado: %.1f\n", bpm);
        check(bpm > 50 && bpm < 250, "bpm en rango razonable");
    }

    /* DR measure */
    double dr = 0;
    uint32_t blocks = 0;
    rc = ch_dr_measure(wav, &dr, &blocks);
    check(rc == 0, "dr_measure ok");
    check(dr >= 0.0 && dr <= 20.0, "DR en rango 0-20");
    check(blocks > 0, "blocks > 0");

    /* Key detect */
    char key[32] = {0};
    double conf = 0;
    rc = ch_key_detect(wav, key, sizeof key, &conf);
    check(rc == 0 || rc == -3, "key_detect (puede fallar en tono puro)");
    if (rc == 0) {
        printf("     key: %s (conf %.3f)\n", key, conf);
        check(strlen(key) > 0, "key no vacio");
    }

    /* Silence segments */
    double segs[20];
    int nseg = ch_silence_segments(wav, -40.0, 0.1, segs, 10);
    check(nseg >= 0, "silence_segments ok");
    printf("     segmentos silencio: %d\n", nseg);

    /* Invalid args */
    check(ch_loudness_scan(NULL, &lr) == -1, "loudness_scan NULL path");
    check(ch_loudness_scan(wav, NULL) == -1, "loudness_scan NULL out");
    check(ch_waveform_peaks(NULL, 10, peaks) == -1, "waveform_peaks NULL path");
    check(ch_waveform_peaks(wav, 0, peaks) == -1, "waveform_peaks buckets=0");
    check(ch_waveform_peaks(wav, 10, NULL) == -1, "waveform_peaks NULL out");
    check(ch_bpm_detect(NULL, &bpm) == -1, "bpm_detect NULL path");
    check(ch_bpm_detect(wav, NULL) == -1, "bpm_detect NULL out");
    check(ch_dr_measure(NULL, &dr, &blocks) == -1, "dr_measure NULL path");
    check(ch_dr_measure(wav, NULL, &blocks) == -1, "dr_measure NULL out");
    check(ch_key_detect(NULL, key, sizeof key, &conf) == -1, "key_detect NULL path");
    check(ch_key_detect(wav, NULL, sizeof key, &conf) == -1, "key_detect NULL out");
    check(ch_key_detect(wav, key, 0, &conf) == -1, "key_detect size=0");
    check(ch_silence_segments(NULL, -40, 0.1, segs, 10) == -1, "silence_segments NULL path");
    check(ch_silence_segments(wav, -40, 0.1, NULL, 10) == -1, "silence_segments NULL out");
    check(ch_silence_segments(wav, -40, 0.1, segs, 0) == -1, "silence_segments max=0");

    unlink(wav);
    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}