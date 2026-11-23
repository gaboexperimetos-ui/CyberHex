//! Paisajes sonoros sintetizados en el callback de audio.
//!
//! Tres generadores baratos y deterministas: lluvia suave, ruido marrón y
//! vinilo cálido. No reservan memoria, no toman candados (el preset y el nivel
//! viven en atomics) y se mezclan **sumando** encima de la música, justo antes
//! del limitador, para que el limitador también los dome a ellos.
//!
//! Todo el ruido sale de un xorshift32 por canal: decorrelado entre izquierda y
//! derecha (si no, el paisaje se oiría centrado como un pitido) y reproducible
//! bit a bit con la misma semilla, que es lo que necesitan los tests.

const std = @import("std");

pub const SAMPLE_RATE: f32 = 48000;

/// Ganancia maxima del paisaje a nivel 1 (que no tape la musica).
pub const MAX_GAIN: f32 = 0.28;

pub const PRESET_OFF: u32 = 0;
pub const PRESET_RAIN: u32 = 1;
pub const PRESET_BROWN: u32 = 2;
pub const PRESET_VINYL: u32 = 3;

inline fn fbits(value: f32) u32 {
    return @bitCast(value);
}

inline fn toFloat(bits: u32) f32 {
    return @bitCast(bits);
}

inline fn onePole(hz: f32) f32 {
    return 1.0 - @exp(-2.0 * std.math.pi * hz / SAMPLE_RATE);
}

fn clampf(value: f32, lo: f32, hi: f32) f32 {
    if (!(value > lo)) return lo;
    if (value > hi) return hi;
    return value;
}

/// Ruido blanco en [-1, 1).
inline fn white(state: *u32) f32 {
    var x = state.*;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    state.* = if (x == 0) 0x9E3779B9 else x;
    return @as(f32, @floatFromInt(x >> 8)) * (1.0 / 8388608.0) - 1.0;
}

pub const Soundscape = struct {
    preset: std.atomic.Value(u32) = .init(PRESET_OFF),
    level_bits: std.atomic.Value(u32) = .init(fbits(0)),

    seed_l: u32 = 0x2545F491,
    seed_r: u32 = 0x9E3779B9,

    // Estado de los filtros (uno por canal).
    low_l: f32 = 0,
    low_r: f32 = 0,
    band_l: f32 = 0,
    band_r: f32 = 0,
    hp_l: f32 = 0,
    hp_r: f32 = 0,

    // Chasquidos del vinilo.
    crack_l: f32 = 0,
    crack_r: f32 = 0,

    // LFO lento de las rafagas de lluvia.
    lfo: f32 = 0,

    pub fn set(self: *Soundscape, new_preset: u32, new_level: f32) void {
        const p: u32 = switch (new_preset) {
            PRESET_RAIN, PRESET_BROWN, PRESET_VINYL => new_preset,
            else => PRESET_OFF,
        };
        self.preset.store(p, .monotonic);
        self.level_bits.store(fbits(clampf(new_level, 0, 1)), .monotonic);
        if (p == PRESET_OFF) self.reset();
    }

    pub fn presetValue(self: *const Soundscape) u32 {
        return self.preset.load(.monotonic);
    }

    pub fn level(self: *const Soundscape) f32 {
        return toFloat(self.level_bits.load(.monotonic));
    }

    /// ¿Hay algo que mezclar? Con esto apagado la cadena no cuesta nada.
    pub fn isIdle(self: *const Soundscape) bool {
        return self.presetValue() == PRESET_OFF or self.level() <= 0;
    }

    pub fn reset(self: *Soundscape) void {
        self.seed_l = 0x2545F491;
        self.seed_r = 0x9E3779B9;
        self.low_l = 0;
        self.low_r = 0;
        self.band_l = 0;
        self.band_r = 0;
        self.hp_l = 0;
        self.hp_r = 0;
        self.crack_l = 0;
        self.crack_r = 0;
        self.lfo = 0;
    }

    /// Lluvia: ruido filtrado entre 400 Hz y 6 kHz, con rafagas lentas.
    fn rain(self: *Soundscape) [2]f32 {
        const noise_l = white(&self.seed_l);
        const noise_r = white(&self.seed_r);
        // Banda: paso alto de 400 Hz (quitando el retumbo) y paso bajo de 6 kHz.
        self.low_l += (noise_l - self.low_l) * onePole(400);
        self.low_r += (noise_r - self.low_r) * onePole(400);
        const hi_l = noise_l - self.low_l;
        const hi_r = noise_r - self.low_r;
        const a6k = onePole(6000);
        self.band_l += (hi_l - self.band_l) * a6k;
        self.band_r += (hi_r - self.band_r) * a6k;

        // RaFagas: 0.07 Hz, entre 0.55 y 1.0 de nivel.
        self.lfo += 0.07 / SAMPLE_RATE;
        if (self.lfo >= 1.0) self.lfo -= 1.0;
        const gust = 0.775 + 0.225 * @sin(self.lfo * 2.0 * std.math.pi);
        return .{ self.band_l * gust * 0.9, self.band_r * gust * 0.9 };
    }

    /// Ruido marron: integral con fuga del ruido blanco (-6 dB/octava).
    fn brown(self: *Soundscape) [2]f32 {
        const leak = 0.012; // ~90 Hz: retumbo puro, sin DC que se escape
        self.low_l += (white(&self.seed_l) - self.low_l) * leak;
        self.low_r += (white(&self.seed_r) - self.low_r) * leak;
        // Compensado para que a nivel 1 tenga un RMS parecido al de la lluvia
        // (~0.06) sin acercarse al recorte.
        return .{ self.low_l * 4.8, self.low_r * 4.8 };
    }

    /// Vinilo: ruido rosa suave, retumbo y chasquidos esporadicos.
    fn vinyl(self: *Soundscape) [2]f32 {
        const noise_l = white(&self.seed_l);
        const noise_r = white(&self.seed_r);
        // "Rosa" barato: blanco + su propia integral, mezclados.
        self.low_l += (noise_l - self.low_l) * onePole(900);
        self.low_r += (noise_r - self.low_r) * onePole(900);
        const hiss_l = (noise_l * 0.35 + self.low_l * 0.65) * 0.25;
        const hiss_r = (noise_r * 0.35 + self.low_r * 0.65) * 0.25;

        // Chasquido: uno cada ~8000 muestras por canal, decae en ~0.4 ms.
        if ((self.seed_l % 8000) == 1) self.crack_l = white(&self.seed_l) * 0.9;
        if ((self.seed_r % 8000) == 3) self.crack_r = white(&self.seed_r) * 0.9;
        self.crack_l *= 0.995;
        self.crack_r *= 0.995;

        return .{ hiss_l + self.crack_l, hiss_r + self.crack_r };
    }

    /// Devuelve el paisaje (sin sumar) ya escalado por el nivel.
    pub fn process(self: *Soundscape) [2]f32 {
        const p = self.preset.load(.monotonic);
        const lvl = clampf(self.level(), 0, 1);
        if (p == PRESET_OFF or lvl <= 0) return .{ 0, 0 };

        const raw = switch (p) {
            PRESET_RAIN => self.rain(),
            PRESET_BROWN => self.brown(),
            PRESET_VINYL => self.vinyl(),
            else => return .{ 0, 0 },
        };
        const gain = MAX_GAIN * lvl;
        return .{ raw[0] * gain, raw[1] * gain };
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn rms(samples: []const f32) f64 {
    var sum: f64 = 0;
    for (samples) |x| sum += @as(f64, x) * x;
    return @sqrt(sum / @as(f64, @floatFromInt(samples.len)));
}

/// Media de la diferencia entre muestras consecutivas: mide "cuanto brillo".
fn meanDelta(samples: []const f32) f64 {
    var sum: f64 = 0;
    var i: usize = 1;
    while (i < samples.len) : (i += 1) {
        sum += @abs(@as(f64, samples[i]) - samples[i - 1]);
    }
    return sum / @as(f64, @floatFromInt(samples.len - 1));
}

fn capture(preset: u32, level: f32, buf_l: []f32, buf_r: []f32) void {
    var scape: Soundscape = .{};
    scape.set(preset, level);
    for (buf_l, buf_r) |*l, *r| {
        const out = scape.process();
        l.* = out[0];
        r.* = out[1];
    }
}

test "paisaje: apagado o a nivel 0 no genera nada" {
    var scape: Soundscape = .{};
    try std.testing.expect(scape.isIdle());
    const off = scape.process();
    try std.testing.expectEqual(@as(f32, 0), off[0]);
    try std.testing.expectEqual(@as(f32, 0), off[1]);

    scape.set(PRESET_RAIN, 0);
    try std.testing.expect(scape.isIdle());

    // Un preset desconocido se trata como apagado y deja de sonar.
    scape.set(99, 1);
    try std.testing.expectEqual(PRESET_OFF, scape.presetValue());
}

test "paisaje: lluvia, marron y vinilo suenan y no son iguales" {
    const n = 24000;
    var rain_l: [n]f32 = undefined;
    var rain_r: [n]f32 = undefined;
    var brown_l: [n]f32 = undefined;
    var brown_r: [n]f32 = undefined;
    var vinyl_l: [n]f32 = undefined;
    var vinyl_r: [n]f32 = undefined;

    capture(PRESET_RAIN, 1, &rain_l, &rain_r);
    capture(PRESET_BROWN, 1, &brown_l, &brown_r);
    capture(PRESET_VINYL, 1, &vinyl_l, &vinyl_r);

    try std.testing.expect(rms(&rain_l) > 0.01);
    try std.testing.expect(rms(&brown_l) > 0.01);
    try std.testing.expect(rms(&vinyl_l) > 0.01);

    // La lluvia es mucho mas "brillante" (cambia mas entre muestras) que el
    // ruido marron, que es retumbo puro.
    try std.testing.expect(meanDelta(&rain_l) > meanDelta(&brown_l) * 4.0);

    // El vinilo tiene chasquidos: pico muy por encima del valor eficaz.
    var peak: f32 = 0;
    for (vinyl_l) |x| peak = @max(peak, @abs(x));
    try std.testing.expect(peak > @as(f32, @floatCast(rms(&vinyl_l))) * 3.0);

    // Estereo de verdad: los dos canales no son la misma señal.
    var diff: f64 = 0;
    for (rain_l, rain_r) |l, r| diff += @abs(@as(f64, l) - r);
    try std.testing.expect(diff > 1.0);
}

test "paisaje: el nivel escala la salida" {
    const n = 8000;
    var half_l: [n]f32 = undefined;
    var full_l: [n]f32 = undefined;
    var half_r: [n]f32 = undefined;
    var full_r: [n]f32 = undefined;
    capture(PRESET_BROWN, 0.5, &half_l, &half_r);
    capture(PRESET_BROWN, 1.0, &full_l, &full_r);
    const ratio = rms(&half_l) / rms(&full_l);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), ratio, 0.05);
}

test "paisaje: determinista y reiniciable" {
    var a: Soundscape = .{};
    a.set(PRESET_RAIN, 1);
    var first: [64]f32 = undefined;
    for (&first) |*slot| slot.* = a.process()[0];

    a.reset();
    for (first) |expected| {
        const again = a.process()[0];
        try std.testing.expectEqual(expected, again);
    }
}

test "paisaje: nivel y preset se recortan a lo permitido" {
    var scape: Soundscape = .{};
    scape.set(PRESET_VINYL, 5);
    try std.testing.expectEqual(@as(f32, 1.0), scape.level());
    scape.set(PRESET_VINYL, -2);
    try std.testing.expectEqual(@as(f32, 0.0), scape.level());
    try std.testing.expectEqual(PRESET_VINYL, scape.presetValue());
}
