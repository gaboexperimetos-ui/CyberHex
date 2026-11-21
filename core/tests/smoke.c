/*
 * Prueba de humo del nucleo CyberHex con audio de verdad.
 *
 * Sintetiza un WAV de 3 s (440 Hz, estereo 48 kHz), lo reproduce con el motor
 * y comprueba niveles, pausa, loop A-B, eventos y los ajustes nuevos.
 *
 * Se compila y ejecuta igual en escritorio y en Android:
 *
 *     zig build smoke                       # PC (necesita salida de audio)
 *     adb push cyberhex_smoke /data/local/tmp/
 *     adb shell /data/local/tmp/cyberhex_smoke /data/local/tmp
 *
 * Codigo de salida: 0 todo bien, 1 fallos funcionales, 2 no hay motor
 * (sin dispositivo de audio o libreria no encontrada).
 */
/* POSIX 2008: da nanosleep en modo estricto y tambien en bionic (Android). */
#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "cyberhex_core.h"

static int failures = 0;

static void msleep(int ms) {
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

static void check(int ok, const char* what) {
    printf("%s  %s\n", ok ? "OK  " : "MAL ", what);
    if (!ok) failures++;
}

/* WAV PCM 16 bits estereo, `seconds` segundos de un tono de `hz`. */
static int write_tone(const char* path, double seconds, double hz) {
    const uint32_t rate = 48000;
    const uint32_t channels = 2;
    const uint32_t frames = (uint32_t)(seconds * rate);
    const uint32_t data_bytes = frames * channels * 2;

    FILE* f = fopen(path, "wb");
    if (!f) return -1;

    uint8_t header[44];
    const uint32_t chunk = 36 + data_bytes;
    memcpy(header + 0, "RIFF", 4);
    memcpy(header + 4, &chunk, 4);
    memcpy(header + 8, "WAVEfmt ", 8);
    const uint32_t fmt_len = 16, fmt = 1;
    const uint16_t bits = 16;
    const uint32_t byte_rate = rate * channels * 2;
    const uint16_t block_align = channels * 2;
    memcpy(header + 16, &fmt_len, 4);
    memcpy(header + 20, &fmt, 2);
    memcpy(header + 22, (uint16_t[]){channels}, 2);
    memcpy(header + 24, &rate, 4);
    memcpy(header + 28, &byte_rate, 4);
    memcpy(header + 32, &block_align, 2);
    memcpy(header + 34, &bits, 2);
    memcpy(header + 36, "data", 4);
    memcpy(header + 40, &data_bytes, 4);
    fwrite(header, 1, sizeof(header), f);

    /* Onda cuadrada: no hace falta libm y da RMS/pico bien definidos. */
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

static int near(double a, double b, double tol) { return (a > b ? a - b : b - a) <= tol; }

int main(int argc, char** argv) {
    const char* dir = argc > 1 ? argv[1] : ".";
    char wav[1024];
    snprintf(wav, sizeof(wav), "%s/cyberhex_smoke.wav", dir);

    printf("CyberHex %s, ABI %d\n", ch_core_version(), ch_engine_abi_version());
    check(ch_engine_abi_version() >= 3, "abi >= 3");
    check(write_tone(wav, 3.0, 440.0) == 0, "wav generado");

    ch_engine* e = ch_engine_create();
    if (!e) {
        printf("sin motor: %s\n", ch_core_last_error());
        return 2;
    }
    if (ch_engine_load(e, wav) != 0) {
        printf("no carga el wav: %s\n", ch_engine_last_error(e));
        ch_engine_destroy(e);
        return 1;
    }
    check(near(ch_engine_duration(e), 3.0, 0.05), "duracion ~3 s");

    ch_engine_play(e);
    msleep(400);

    float lv[4] = {0};
    const int got = ch_engine_levels(e, lv, 4);
    printf("     niveles: rms %.4f/%.4f pico %.4f/%.4f\n", lv[0], lv[1], lv[2], lv[3]);
    check(got == 4, "niveles: 4 valores");
    check(lv[0] > 0.1f && lv[2] > 0.3f, "niveles: rms y pico con señal");
    check(near(lv[0], lv[1], 1e-3), "niveles: canales iguales en un tono mono");

    /* Eventos: al menos un STATE desde el motor. */
    ch_event ev;
    int events = 0, saw_state = 0, saw_track = 0;
    while (ch_engine_poll_event(e, &ev) == 1) {
        events++;
        if (ev.kind == CH_EVENT_STATE) saw_state = 1;
        if (ev.kind == CH_EVENT_TRACK) saw_track = 1;
    }
    printf("     eventos: %d\n", events);
    check(saw_state || saw_track, "eventos: STATE o TRACK emitidos");

    /* Pausa con corte seco: la posicion no puede seguir avanzando. */
    ch_engine_set_pause_fade(e, 0.0f);
    check(near(ch_engine_pause_fade(e), 0.0, 1e-6), "fade de pausa = 0");
    ch_engine_pause(e);
    msleep(150);
    const double p1 = ch_engine_position(e);
    msleep(250);
    const double p2 = ch_engine_position(e);
    printf("     pausa: %.4f -> %.4f\n", p1, p2);
    check(near(p1, p2, 0.02), "pausa: posicion quieta");

    ch_engine_levels(e, lv, 4);
    check(lv[0] < 0.1f, "niveles: bajan al pausar");

    /* Loop A-B: 10 muestras, todas dentro del tramo. */
    ch_engine_set_loop(e, 0.20, 0.50);
    check(near(ch_engine_loop_start(e), 0.20, 0.01) && near(ch_engine_loop_end(e), 0.50, 0.01),
          "loop: A y B devueltos");
    ch_engine_play(e);
    msleep(300);
    int inside = 0, total = 0;
    for (int i = 0; i < 10; i++) {
        const double p = ch_engine_position(e);
        total++;
        if (p >= 0.15 && p <= 0.60) inside++;
        msleep(120);
    }
    printf("     loop: %d/%d dentro (pos %.3f)\n", inside, total, ch_engine_position(e));
    check(inside == total, "loop A-B: no se sale del tramo");
    ch_engine_set_loop(e, 0, 0);
    check(ch_engine_loop_start(e) < 0, "loop: desactivado");

    /* Ajustes nuevos: preamp, ReplayGain por album, balance y modo de canales. */
    check(ch_engine_set_eq_preamp(e, -6) == 0 && near(ch_engine_eq_preamp(e), -6.0, 1e-6),
          "preamp del EQ");
    check(ch_engine_set_replaygain_mode(e, 1) == 0 && ch_engine_replaygain_mode(e) == 1,
          "ReplayGain por album");
    ch_engine_set_replaygain_mode(e, 0);
    check(ch_engine_set_balance(e, -1.0f) == 0 && near(ch_engine_balance(e), -1.0, 1e-6),
          "balance");
    ch_engine_set_balance(e, 3.0f); /* fuera de rango: se acota */
    check(near(ch_engine_balance(e), 1.0, 1e-6), "balance se acota a +1");
    check(ch_engine_set_channel_mode(e, 2) == 0 && ch_engine_channel_mode(e) == 2, "modo mono/cambio");
    check(ch_engine_set_channel_mode(e, 9) != 0, "modo de canales invalido rechazado");
    ch_engine_set_channel_mode(e, 0);
    ch_engine_set_balance(e, 0.0f);

    /* Fase 3: paisaje sonoro, exportador WAV y BPM, por el ABI publico. */
    float sc_level = -1;
    check(ch_engine_soundscape(e, &sc_level) == 0 && near(sc_level, 0.0, 1e-6),
          "paisaje: apagado de fabrica");
    check(ch_engine_set_soundscape(e, 1, 0.6f) == 1, "paisaje: lluvia encendida");
    check(ch_engine_soundscape(e, &sc_level) == 1 && near(sc_level, 0.6, 1e-6),
          "paisaje: preset y nivel");
    ch_engine_play(e);
    msleep(300);
    ch_engine_levels(e, lv, 4);
    check(lv[0] > 0.01f, "paisaje: se oye bajo la musica");
    check(ch_engine_set_soundscape(e, 0, 0.0f) == 0, "paisaje: se apaga");
    ch_engine_pause(e);

    char exp1[1030], exp2[1030];
    snprintf(exp1, sizeof(exp1), "%s/cyberhex_smoke_flat.wav", dir);
    snprintf(exp2, sizeof(exp2), "%s/cyberhex_smoke_dsp.wav", dir);
    check(ch_engine_render_wav(wav, exp1, 0.0, 0.0) == 0, "export: WAV completo");
    ch_engine_set_9d(e, 1, 0.5f, 0.9f);
    ch_engine_set_soundscape(e, 2, 0.8f);
    check(ch_engine_render_wav_ex(e, wav, exp2, 0.0, 1.0) == 0, "export: con DSP y recorte");
    ch_engine_set_9d(e, 0, 0.5f, 0.0f);
    ch_engine_set_soundscape(e, 0, 0.0f);

    FILE* fa = fopen(exp1, "rb");
    FILE* fb = fopen(exp2, "rb");
    long la = 0, lb = 0;
    if (fa && fb) {
        fseek(fa, 0, SEEK_END);
        la = ftell(fa);
        fseek(fb, 0, SEEK_END);
        lb = ftell(fb);
    }
    if (fa) fclose(fa);
    if (fb) fclose(fb);
    printf("     export: %ld y %ld bytes\n", la, lb);
    check(la > 44 + 48000 * 4, "export: 3 s de audio");
    check(lb > 44 && lb < 44 + 48000 * 4 * 2, "export: recorte de 1 s");
    check(ch_engine_detect_bpm(exp1) >= 0.0, "bpm: no revienta con un tono");
    check(ch_engine_render_wav("/no/existe.wav", exp1, 0.0, 0.0) == -2, "export: origen invalido");
    remove(exp1);
    remove(exp2);

    ch_engine_pause(e);
    ch_engine_destroy(e);
    remove(wav);

    printf("\n%s (%d fallos)\n", failures == 0 ? "TODO BIEN" : "HAY FALLOS", failures);
    return failures == 0 ? 0 : 1;
}
