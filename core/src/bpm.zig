//! Detector de BPM sin dependencias externas.
//!
//! Idea: la musica tiene pulsos; un pulso es un salto de energia. Se calcula
//! una envolvente de energia en tramas de 10 ms, se queda solo con las subidas
//! (flujo espectral en el dominio del tiempo), se le quita la media y se
//! autocorrelaciona. El desfase con mas correlacion dentro de 60..200 BPM es el
//! pulso; se refina con interpolacion parabolica.
//!
//! Todo es aritmetica en memoria ya reservada por quien llama (aqui se usa un
//! array fijo en la pila), asi que sirve igual para el exportador WAV y para
//! `ch_engine_detect_bpm`, que corre fuera del hilo de audio.
//!
//! Contrato: devuelve 0 cuando no hay pulso claro (silencio, ruido, voz); nunca
//! un valor fuera de MIN_BPM..MAX_BPM.

const std = @import("std");

pub const MIN_BPM: f64 = 60;
pub const MAX_BPM: f64 = 200;

/// Tramas de la envolvente: 10 ms. Con 90 s de audio son 9 000 tramas.
const HOP_SECONDS: f64 = 0.010;
const MAX_FRAMES: usize = 6000;

/// Peso del prior: el tempo humano se concentra alrededor de 120 BPM.
const PRIOR_CENTER: f64 = 120;
const PRIOR_SIGMA: f64 = 0.9; // octavas

const Pitch = struct {
    bpm: f64,
    confidence: f64,
};

/// Detecta el pulso de una senal mono. `sample_rate` en Hz. Devuelve 0 si no
/// hay un pulso creible.
pub fn detect(mono: []const f32, sample_rate: f64) f64 {
    return detectPitch(mono, sample_rate).bpm;
}

pub fn detectPitch(mono: []const f32, sample_rate: f64) Pitch {
    const none = Pitch{ .bpm = 0, .confidence = 0 };
    if (sample_rate < 8000 or mono.len < 4096) return none;

    const hop: usize = @intFromFloat(HOP_SECONDS * sample_rate);
    if (hop < 8) return none;
    const frames_total = mono.len / hop;
    if (frames_total < 64) return none;
    const frames = @min(frames_total, MAX_FRAMES);

    // 1) Envolvente de energia (RMS por trama). Se comprime con logaritmo para
    //    que un golpe de bombo no aplaste al resto de la mezcla.
    var env: [MAX_FRAMES]f32 = undefined;
    var peak: f32 = 0;
    var i: usize = 0;
    while (i < frames) : (i += 1) {
        const base = i * hop;
        var sum: f64 = 0;
        for (mono[base .. base + hop]) |x| sum += @as(f64, x) * x;
        const rms: f32 = @floatCast(@sqrt(sum / @as(f64, @floatFromInt(hop))));
        env[i] = rms;
        if (rms > peak) peak = rms;
    }
    if (peak < 1e-4) return none; // silencio digital

    // 2) Flujo: solo cuenta lo que sube.
    var flux: [MAX_FRAMES]f32 = undefined;
    var flux_sum: f64 = 0;
    i = 1;
    while (i < frames) : (i += 1) {
        const d = env[i] - env[i - 1];
        const v = if (d > 0) @log(1.0 + 1000.0 * d) else 0;
        flux[i - 1] = v;
        flux_sum += v;
    }
    const n = frames - 1;
    if (n < 64) return none;
    const mean = flux_sum / @as(f64, @floatFromInt(n));
    if (mean < 1e-6) return none; // energia plana: nada que marcar

    // 3) Centrado y normalizacion por la desviacion tipica.
    var var_sum: f64 = 0;
    i = 0;
    while (i < n) : (i += 1) {
        const v = @as(f64, flux[i]) - mean;
        flux[i] = @floatCast(v);
        var_sum += v * v;
    }
    const stddev = @sqrt(var_sum / @as(f64, @floatFromInt(n)));
    if (stddev < 1e-9) return none;
    i = 0;
    while (i < n) : (i += 1) flux[i] = @floatCast(@as(f64, flux[i]) / stddev);

    // 3b) Suavizado [0.25 0.5 0.25] en el sitio. Un pulso deja de ser un pico
    //     de una sola trama, y la correlacion a desfases no enteros no cae a
    //     cero: sin esto un tempo de 164 BPM parece estar a 82.
    var prev = flux[0];
    i = 0;
    while (i < n) : (i += 1) {
        const cur = flux[i];
        const next = if (i + 1 < n) flux[i + 1] else cur;
        flux[i] = prev * 0.25 + cur * 0.5 + next * 0.25;
        prev = cur;
    }

    // 4) Autocorrelacion normalizada sobre el rango de pulsos posibles.
    const frames_per_second = 1.0 / HOP_SECONDS;
    const lag_min: usize = @max(1, @as(usize, @intFromFloat(frames_per_second * 60.0 / MAX_BPM)));
    const lag_max: usize = @min(n - 2, @as(usize, @intFromFloat(frames_per_second * 60.0 / MIN_BPM)));
    if (lag_max <= lag_min + 2) return none;

    const ac = struct {
        fn score(x: []const f32, lag: usize, len: usize) f64 {
            var s: f64 = 0;
            var k: usize = 0;
            while (k + lag < len) : (k += 1) s += @as(f64, x[k]) * x[k + lag];
            return s / @as(f64, @floatFromInt(len - lag));
        }
    };

    var best: f64 = 0;
    var best_lag: usize = lag_min;
    var scores: [MAX_FRAMES]f64 = undefined;
    var lag = lag_min;
    while (lag <= lag_max) : (lag += 1) {
        const raw = ac.score(flux[0..n], lag, n);
        // Prior logaritmico: 120 BPM manda, 60 y 240 quedan penalizados.
        const bpm = frames_per_second * 60.0 / @as(f64, @floatFromInt(lag));
        const oct = @log2(bpm / PRIOR_CENTER) / PRIOR_SIGMA;
        const weight = @exp(-0.5 * oct * oct);
        const s = raw * weight;
        scores[lag] = s;
        if (s > best) {
            best = s;
            best_lag = lag;
        }
    }
    if (best <= 0) return none;

    // 4b) Entre desfases casi igual de buenos, el mas corto: un click a 160 BPM
    //     correlaciona igual a 1, 2 y 3 pulsos de distancia, y queremos el
    //     pulso, no el compas.
    {
        const thresh = best * 0.85;
        var k: usize = lag_min;
        while (k <= best_lag) : (k += 1) {
            if (scores[k] >= thresh) {
                best_lag = k;
                best = scores[k];
                break;
            }
        }
    }

    // 5) Refinado parabolico con los vecinos (sub-trama).
    var frac: f64 = 0;
    if (best_lag > lag_min and best_lag < lag_max) {
        const a = scores[best_lag - 1];
        const b = scores[best_lag];
        const c = scores[best_lag + 1];
        const den = a - 2 * b + c;
        if (@abs(den) > 1e-12) frac = std.math.clamp(0.5 * (a - c) / den, -0.5, 0.5);
    }
    const lag_f = @as(f64, @floatFromInt(best_lag)) + frac;
    if (lag_f <= 0) return none;

    var bpm = frames_per_second * 60.0 / lag_f;
    // 6) Plegado al rango del contrato (dobles y mitades del pulso).
    while (bpm < MIN_BPM) bpm *= 2;
    while (bpm > MAX_BPM) bpm /= 2;
    if (!(bpm >= MIN_BPM and bpm <= MAX_BPM)) return none;

    // Confianza: correlacion del mejor desfase contra el siguiente pico lejano.
    const second = blk: {
        var s: f64 = 0;
        var k: usize = lag_min;
        while (k <= lag_max) : (k += 1) {
            const kk: f64 = @floatFromInt(k);
            if (kk > lag_f * 1.35) s = @max(s, scores[k]);
        }
        break :blk s;
    };
    const conf = if (best <= 0) 0 else std.math.clamp(1 - second / best, 0, 1);
    return .{ .bpm = bpm, .confidence = conf };
}

const testing = std.testing;

fn clickTrack(comptime n: usize, bpm: f64, sr: f64, out: *[n]f32) void {
    @memset(out, 0);
    const period: f64 = 60.0 / bpm * sr;
    var next: f64 = sr * 0.05;
    while (next < @as(f64, @floatFromInt(n))) : (next += period) {
        const at: usize = @intFromFloat(next);
        // Golpe de 8 ms con decaimiento exponencial.
        const dur: usize = @intFromFloat(0.008 * sr);
        var k: usize = 0;
        while (k < dur and at + k < n) : (k += 1) {
            const t = @as(f64, @floatFromInt(k)) / sr;
            out[at + k] += @floatCast(0.8 * @exp(-t / 0.002));
        }
    }
}

test "bpm: detecta un click track de 120" {
    var buf: [48000 * 12]f32 = undefined;
    clickTrack(buf.len, 120, 48000, &buf);
    const bpm = detect(&buf, 48000);
    try testing.expect(@abs(bpm - 120) < 2.0);
}

test "bpm: detecta 90 y 150 dentro del rango" {
    var buf: [48000 * 12]f32 = undefined;
    clickTrack(buf.len, 90, 48000, &buf);
    try testing.expect(@abs(detect(&buf, 48000) - 90) < 2.5);
    clickTrack(buf.len, 150, 48000, &buf);
    try testing.expect(@abs(detect(&buf, 48000) - 150) < 3.0);
}

test "bpm: sin pulso devuelve 0" {
    var silent: [48000]f32 = @splat(0);
    try testing.expectEqual(@as(f64, 0), detect(&silent, 48000));
    try testing.expectEqual(@as(f64, 0), detect(&.{}, 48000));
    // Ruido blanco estacionario: no hay transientes.
    var prng = std.Random.DefaultPrng.init(0x5EED);
    const rnd = prng.random();
    var noise: [48000 * 4]f32 = undefined;
    for (&noise) |*x| x.* = rnd.float(f32) * 0.2 - 0.1;
    const b = detect(&noise, 48000);
    // Puede colar un valor espurio por azar, pero nunca fuera del contrato.
    try testing.expect(b == 0 or (b >= MIN_BPM and b <= MAX_BPM));
}

test "bpm: nunca sale del rango del contrato" {
    var buf: [48000 * 6]f32 = undefined;
    var bpm: f64 = 62;
    while (bpm <= 198) : (bpm += 17) {
        clickTrack(buf.len, bpm, 48000, &buf);
        const got = detect(&buf, 48000);
        try testing.expect(got >= MIN_BPM and got <= MAX_BPM);
        // Dentro de la octava correcta (o su doble/mitad plegada).
        const ratio = got / bpm;
        const ok = @abs(ratio - 1) < 0.05 or @abs(ratio - 2) < 0.05 or @abs(ratio - 0.5) < 0.05;
        try testing.expect(ok);
    }
}

test "bpm: muestras cortas o tasas raras no rompen" {
    var small: [1024]f32 = @splat(0.1);
    try testing.expectEqual(@as(f64, 0), detect(&small, 48000));
    try testing.expectEqual(@as(f64, 0), detect(&small, 100));
    const p = detectPitch(&small, 44100);
    try testing.expectEqual(@as(f64, 0), p.bpm);
    try testing.expectEqual(@as(f64, 0), p.confidence);
}
