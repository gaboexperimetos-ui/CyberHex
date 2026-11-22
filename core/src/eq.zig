const std = @import("std");

pub const BAND_COUNT = 36;
pub const CHANNELS = 2;
pub const SAMPLE_RATE: f32 = 48000;
pub const MAX_GAIN_DB: f32 = 18;

// 20 Hz a 20 kHz, 36 bandas espaciadas logarítmicamente.
pub const FREQS = [BAND_COUNT]f32{
    20.0,   24.4,   29.7,    36.2,    44.0,    53.7,
    65.4,   79.6,   97.0,    118.2,   143.9,   175.3,
    213.6,  260.2,  317.0,   386.1,   470.4,   573.0,
    698.1,  850.4,  1035.9,  1261.9,  1537.2,  1872.7,
    2281.2, 2779.0, 3385.3,  4124.0,  5023.8,  6119.9,
    7455.2, 9081.8, 11063.4, 13477.3, 16417.8, 20000.0,
};

const Q: f32 = 4.0;

/// Preamp minimo admitido (dB).
pub const MIN_PREAMP_DB: f32 = -24;

const Coeffs = struct {
    b0: f32 = 1,
    b1: f32 = 0,
    b2: f32 = 0,
    a1: f32 = 0,
    a2: f32 = 0,
};

const Config = struct {
    coeffs: [BAND_COUNT]Coeffs = @splat(.{}),
    mask: u64 = 0,
    /// Ganancia lineal aplicada antes del banco (preamp anti-clipping).
    preamp: f32 = 1,
};

const State = struct {
    z1: f32 = 0,
    z2: f32 = 0,
};

fn band(freq: f32, gain_db: f32) Coeffs {
    const a = std.math.pow(f32, 10, gain_db / 40);
    const w0 = 2 * std.math.pi * freq / SAMPLE_RATE;
    const cos_w0 = @cos(w0);
    const alpha = @sin(w0) / (2 * Q);

    const b0 = 1 + alpha * a;
    const b1 = -2 * cos_w0;
    const b2 = 1 - alpha * a;
    const a0 = 1 + alpha / a;
    const a1 = -2 * cos_w0;
    const a2 = 1 - alpha / a;

    return .{
        .b0 = b0 / a0,
        .b1 = b1 / a0,
        .b2 = b2 / a0,
        .a1 = a1 / a0,
        .a2 = a2 / a0,
    };
}

pub const Equalizer = struct {
    config: Config = .{},
    // Ultima copia consistente leida por el hilo de audio: si el escritor se
    // queda a medias, se reutiliza en lugar de girar dentro del callback.
    last_config: Config = .{},
    seq: u32 = 0,
    generation: u32 = 0,
    last_generation: u32 = 0,
    // Ganancias vigentes (para saber que bandas cambiaron de verdad).
    gains: [BAND_COUNT]f32 = @splat(0),
    // Preamp en dB (0..-24): baja la señal antes del banco para que un refuerzo
    // no haga recortar al limitador.
    preamp_db: f32 = 0,
    // Bandas cuyo estado hay que reiniciar; se acumula entre cambios.
    pending_reset: u64 = 0,
    state: [CHANNELS][BAND_COUNT]State = std.mem.zeroes([CHANNELS][BAND_COUNT]State),

    /// Preamp en dB, de 0 a [MIN_PREAMP_DB] (nunca amplifica).
    pub fn setPreamp(self: *Equalizer, db: f32) void {
        self.preamp_db = std.math.clamp(db, MIN_PREAMP_DB, 0);
        self.setGains(&self.gains);
    }

    pub fn setGains(self: *Equalizer, gains_db: []const f32) void {
        var next: Config = .{ .preamp = std.math.pow(f32, 10, self.preamp_db / 20) };
        var gains: [BAND_COUNT]f32 = @splat(0);
        var reset_mask: u64 = 0;
        for (0..BAND_COUNT) |i| {
            const g = if (i < gains_db.len)
                std.math.clamp(gains_db[i], -MAX_GAIN_DB, MAX_GAIN_DB)
            else
                0;
            next.coeffs[i] = band(FREQS[i], g);
            gains[i] = g;
            if (g != 0) {
                next.mask |= (@as(u64, 1) << @intCast(i));
            }
            if (g != self.gains[i]) {
                reset_mask |= (@as(u64, 1) << @intCast(i));
            }
        }
        self.gains = gains;
        if (reset_mask != 0) {
            _ = @atomicRmw(u64, &self.pending_reset, .Or, reset_mask, .monotonic);
        }

        const s = @atomicLoad(u32, &self.seq, .acquire);
        @atomicStore(u32, &self.seq, s +% 1, .release);
        self.config = next;
        @atomicStore(u32, &self.seq, s +% 2, .release);
        _ = @atomicRmw(u32, &self.generation, .Add, 1, .monotonic);
    }

    /// Reinicia solo las bandas cuya ganancia cambio: reiniciar las 36 en cada
    /// movimiento del slider metia un transitorio audible en todo el espectro.
    fn resetMask(self: *Equalizer, mask: u64) void {
        for (0..CHANNELS) |ch| {
            for (0..BAND_COUNT) |b| {
                if (mask & (@as(u64, 1) << @intCast(b)) != 0) {
                    self.state[ch][b] = .{};
                }
            }
        }
    }

    fn snapshot(self: *Equalizer) Config {
        var attempt: usize = 0;
        while (attempt < 8) : (attempt += 1) {
            const s1 = @atomicLoad(u32, &self.seq, .acquire);
            if (s1 & 1 == 0) {
                const set = self.config;
                const s2 = @atomicLoad(u32, &self.seq, .acquire);
                if (s1 == s2) {
                    self.last_config = set;
                    return set;
                }
            }
        }
        return self.last_config;
    }

    pub fn process(self: *Equalizer, buf: []f32, frames: usize) void {
        const gen = @atomicLoad(u32, &self.generation, .acquire);
        if (gen != self.last_generation) {
            const mask = @atomicRmw(u64, &self.pending_reset, .Xchg, 0, .acq_rel);
            self.resetMask(mask);
            self.last_generation = gen;
        }

        const set = self.snapshot();
        if (set.mask == 0 and set.preamp == 1) {
            return;
        }

        var f: usize = 0;
        while (f < frames) : (f += 1) {
            for (0..CHANNELS) |ch| {
                const idx = f * CHANNELS + ch;
                var x = buf[idx] * set.preamp;
                for (0..BAND_COUNT) |b| {
                    if (set.mask & (@as(u64, 1) << @intCast(b)) == 0) continue;
                    const c = &set.coeffs[b];
                    const st = &self.state[ch][b];
                    const y = c.b0 * x + st.z1;
                    st.z1 = c.b1 * x - c.a1 * y + st.z2;
                    st.z2 = c.b2 * x - c.a2 * y;
                    x = y;
                }
                buf[idx] = x;
            }
        }
    }
};

test "0 dB es identidad" {
    var e: Equalizer = .{};
    var gains: [BAND_COUNT]f32 = @splat(0);
    e.setGains(&gains);

    var buf = [_]f32{ 0.1, -0.2, 0.3, -0.4, 0.5, -0.6, 0.0, 1.0 };
    const original = buf;
    e.process(&buf, buf.len / CHANNELS);

    for (buf, original) |got, want| {
        try std.testing.expectApproxEqAbs(want, got, 1e-6);
    }
}

test "el preamp atenua sin tocar el tono" {
    var e: Equalizer = .{};
    var gains: [BAND_COUNT]f32 = @splat(0);
    e.setPreamp(-6);
    e.setGains(&gains);

    var buf = [_]f32{ 0.5, -0.5, 0.25, -0.25 };
    const original = buf;
    e.process(&buf, buf.len / CHANNELS);

    const expected = std.math.pow(f32, 10, @as(f32, -6.0) / 20);
    for (buf, original) |got, want| {
        try std.testing.expectApproxEqAbs(want * expected, got, 1e-6);
    }
    try std.testing.expectApproxEqAbs(-6, e.preamp_db, 1e-6);
    // Se acota: no puede amplificar por encima de 0 dB.
    e.setPreamp(6);
    try std.testing.expectApproxEqAbs(0, e.preamp_db, 1e-6);
}

test "un refuerzo cambia la señal" {
    var e: Equalizer = .{};
    var gains: [BAND_COUNT]f32 = @splat(0);
    gains[18] = 6;
    e.setGains(&gains);

    var buf: [2048]f32 = undefined;
    for (0..buf.len) |i| {
        buf[i] = if (i % 2 == 0) 0.25 else -0.25;
    }
    const before = buf;
    e.process(&buf, buf.len / CHANNELS);

    var changed: usize = 0;
    for (buf, before) |got, want| {
        if (@abs(got - want) > 1e-6) changed += 1;
    }
    try std.testing.expect(changed > 0);
}

test "solo se reinicia el estado de la banda que cambia" {
    var e: Equalizer = .{};
    var gains: [BAND_COUNT]f32 = @splat(0);

    gains[3] = 6;
    e.setGains(&gains);
    try std.testing.expectEqual(@as(u64, 1) << 3, e.pending_reset);

    // Misma ganancia: no hay nada que reiniciar.
    e.setGains(&gains);
    try std.testing.expectEqual(@as(u64, 1) << 3, e.pending_reset);

    gains[7] = -3;
    e.setGains(&gains);
    try std.testing.expectEqual((@as(u64, 1) << 3) | (@as(u64, 1) << 7), e.pending_reset);

    var buf = [_]f32{ 0.1, 0.1, 0.1, 0.1 };
    e.process(&buf, 2);
    try std.testing.expectEqual(@as(u64, 0), e.pending_reset);
}

// ---------------------------------------------------------------------------
// Presets de EQ
// ---------------------------------------------------------------------------

/// Punto de control de un preset: ganancia en dB a una frecuencia.
pub const PresetPoint = struct { freq: f32, gain_db: f32 };

pub const Preset = struct {
    name: []const u8,
    /// Puntos de control (frecuencia, ganancia). Se interpolan en log-frecuencia.
    points: []const PresetPoint,
};

/// Presets incluidos en el nucleo, del 0 al `PRESET_COUNT - 1`.
pub const PRESETS = [_]Preset{
    .{ .name = "Flat", .points = &[_]PresetPoint{} },
    .{ .name = "Bass Boost", .points = &[_]PresetPoint{ .{ .freq = 60, .gain_db = 6 }, .{ .freq = 150, .gain_db = 4 }, .{ .freq = 400, .gain_db = 0 } } },
    .{ .name = "Bass Reducer", .points = &[_]PresetPoint{ .{ .freq = 60, .gain_db = -6 }, .{ .freq = 150, .gain_db = -4 }, .{ .freq = 400, .gain_db = 0 } } },
    .{ .name = "Treble Boost", .points = &[_]PresetPoint{ .{ .freq = 4000, .gain_db = 0 }, .{ .freq = 8000, .gain_db = 4 }, .{ .freq = 14000, .gain_db = 6 } } },
    .{ .name = "Treble Reducer", .points = &[_]PresetPoint{ .{ .freq = 4000, .gain_db = 0 }, .{ .freq = 8000, .gain_db = -4 }, .{ .freq = 14000, .gain_db = -6 } } },
    .{ .name = "Vocal", .points = &[_]PresetPoint{ .{ .freq = 100, .gain_db = -3 }, .{ .freq = 300, .gain_db = -2 }, .{ .freq = 2500, .gain_db = 4 }, .{ .freq = 6000, .gain_db = 2 }, .{ .freq = 12000, .gain_db = -2 } } },
    .{ .name = "Rock", .points = &[_]PresetPoint{ .{ .freq = 60, .gain_db = 5 }, .{ .freq = 200, .gain_db = 2 }, .{ .freq = 800, .gain_db = -2 }, .{ .freq = 3000, .gain_db = 2 }, .{ .freq = 10000, .gain_db = 4 } } },
    .{ .name = "Pop", .points = &[_]PresetPoint{ .{ .freq = 80, .gain_db = 3 }, .{ .freq = 300, .gain_db = -2 }, .{ .freq = 1000, .gain_db = 1 }, .{ .freq = 5000, .gain_db = 3 }, .{ .freq = 12000, .gain_db = 2 } } },
    .{ .name = "Jazz", .points = &[_]PresetPoint{ .{ .freq = 60, .gain_db = 3 }, .{ .freq = 250, .gain_db = 2 }, .{ .freq = 1200, .gain_db = -1 }, .{ .freq = 4000, .gain_db = 2 }, .{ .freq = 10000, .gain_db = 3 } } },
    .{ .name = "Classical", .points = &[_]PresetPoint{ .{ .freq = 60, .gain_db = 2 }, .{ .freq = 400, .gain_db = -1 }, .{ .freq = 1000, .gain_db = -2 }, .{ .freq = 4000, .gain_db = 1 }, .{ .freq = 12000, .gain_db = 3 } } },
    .{ .name = "Electronic", .points = &[_]PresetPoint{ .{ .freq = 50, .gain_db = 6 }, .{ .freq = 200, .gain_db = 2 }, .{ .freq = 800, .gain_db = -3 }, .{ .freq = 5000, .gain_db = 3 }, .{ .freq = 12000, .gain_db = 4 } } },
    .{ .name = "Hip-Hop", .points = &[_]PresetPoint{ .{ .freq = 50, .gain_db = 7 }, .{ .freq = 150, .gain_db = 4 }, .{ .freq = 600, .gain_db = -2 }, .{ .freq = 3000, .gain_db = 1 }, .{ .freq = 10000, .gain_db = 3 } } },
    .{ .name = "Acoustic", .points = &[_]PresetPoint{ .{ .freq = 100, .gain_db = 2 }, .{ .freq = 300, .gain_db = 1 }, .{ .freq = 2000, .gain_db = 3 }, .{ .freq = 6000, .gain_db = 1 }, .{ .freq = 12000, .gain_db = 2 } } },
    .{ .name = "Late Night", .points = &[_]PresetPoint{ .{ .freq = 60, .gain_db = 2 }, .{ .freq = 400, .gain_db = -2 }, .{ .freq = 2000, .gain_db = 1 }, .{ .freq = 8000, .gain_db = -3 } } },
    .{ .name = "Loudness", .points = &[_]PresetPoint{ .{ .freq = 40, .gain_db = 8 }, .{ .freq = 120, .gain_db = 3 }, .{ .freq = 1000, .gain_db = 0 }, .{ .freq = 8000, .gain_db = 2 }, .{ .freq = 14000, .gain_db = 5 } } },
};

pub const PRESET_COUNT: usize = PRESETS.len;

/// Rellena `out` con las ganancias del preset `index` (36 bandas).
/// Devuelve false si el indice no existe.
pub fn presetGains(index: usize, out: *[BAND_COUNT]f32) bool {
    if (index >= PRESET_COUNT) return false;
    const p = PRESETS[index];
    var i: usize = 0;
    while (i < BAND_COUNT) : (i += 1) {
        out[i] = gainAt(p.points, FREQS[i]);
    }
    return true;
}

/// Interpolacion lineal en log2(frecuencia) entre los puntos del preset.
fn gainAt(points: []const PresetPoint, freq: f32) f32 {
    if (points.len == 0) return 0;
    if (freq <= points[0].freq) return points[0].gain_db;
    const last = points[points.len - 1];
    if (freq >= last.freq) return last.gain_db;
    var k: usize = 0;
    while (k + 2 < points.len and freq > points[k + 1].freq) : (k += 1) {}
    const a = points[k];
    const b = points[k + 1];
    const fa = std.math.log2(a.freq);
    const fb = std.math.log2(b.freq);
    const t = (std.math.log2(freq) - fa) / (fb - fa);
    return a.gain_db + (b.gain_db - a.gain_db) * t;
}

test "preset flat deja las 36 bandas a cero" {
    var gains: [BAND_COUNT]f32 = @splat(7);
    try std.testing.expect(presetGains(0, &gains));
    for (gains) |g| try std.testing.expectApproxEqAbs(0, g, 1e-6);
}

test "los presets quedan dentro del rango del EQ" {
    var gains: [BAND_COUNT]f32 = undefined;
    for (0..PRESET_COUNT) |i| {
        try std.testing.expect(presetGains(i, &gains));
        for (gains) |g| {
            try std.testing.expect(g >= -MAX_GAIN_DB and g <= MAX_GAIN_DB);
        }
    }
}

test "el preset de graves sube 60 Hz y no toca 20 kHz" {
    var gains: [BAND_COUNT]f32 = undefined;
    try std.testing.expect(presetGains(1, &gains)); // Bass Boost
    const low = gains[0]; // 20 Hz, por debajo del primer punto
    try std.testing.expect(low > 5.9);
    try std.testing.expectApproxEqAbs(0, gains[BAND_COUNT - 1], 1e-6);
}
