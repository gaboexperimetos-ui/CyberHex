const std = @import("std");

pub const BAND_COUNT = 36;
pub const CHANNELS = 2;
pub const SAMPLE_RATE: f32 = 48000;
pub const MAX_GAIN_DB: f32 = 18;

// 20 Hz a 20 kHz, 36 bandas espaciadas logarítmicamente.
pub const FREQS = [BAND_COUNT]f32{
    20.0,    24.4,    29.7,    36.2,    44.0,    53.7,
    65.4,    79.6,    97.0,    118.2,   143.9,   175.3,
    213.6,   260.2,   317.0,   386.1,   470.4,   573.0,
    698.1,   850.4,   1035.9,  1261.9,  1537.2,  1872.7,
    2281.2,  2779.0,  3385.3,  4124.0,  5023.8,  6119.9,
    7455.2,  9081.8,  11063.4, 13477.3, 16417.8, 20000.0,
};

const Q: f32 = 4.0;

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
    seq: u32 = 0,
    generation: u32 = 0,
    last_generation: u32 = 0,
    state: [CHANNELS][BAND_COUNT]State = std.mem.zeroes([CHANNELS][BAND_COUNT]State),

    pub fn setGains(self: *Equalizer, gains_db: []const f32) void {
        var next: Config = .{};
        for (0..BAND_COUNT) |i| {
            const g = if (i < gains_db.len)
                std.math.clamp(gains_db[i], -MAX_GAIN_DB, MAX_GAIN_DB)
            else
                0;
            next.coeffs[i] = band(FREQS[i], g);
            if (g != 0) {
                next.mask |= (@as(u64, 1) << @intCast(i));
            }
        }

        const s = @atomicLoad(u32, &self.seq, .acquire);
        @atomicStore(u32, &self.seq, s +% 1, .release);
        self.config = next;
        @atomicStore(u32, &self.seq, s +% 2, .release);
        _ = @atomicRmw(u32, &self.generation, .Add, 1, .monotonic);
    }

    fn resetState(self: *Equalizer) void {
        self.state = std.mem.zeroes([CHANNELS][BAND_COUNT]State);
    }

    fn snapshot(self: *const Equalizer) Config {
        while (true) {
            const s1 = @atomicLoad(u32, &self.seq, .acquire);
            if (s1 & 1 != 0) continue;
            const set = self.config;
            const s2 = @atomicLoad(u32, &self.seq, .acquire);
            if (s1 == s2) return set;
        }
    }

    pub fn process(self: *Equalizer, buf: []f32, frames: usize) void {
        const gen = @atomicLoad(u32, &self.generation, .acquire);
        if (gen != self.last_generation) {
            self.resetState();
            self.last_generation = gen;
        }

        const set = self.snapshot();
        if (set.mask == 0) {
            return;
        }

        var f: usize = 0;
        while (f < frames) : (f += 1) {
            for (0..CHANNELS) |ch| {
                const idx = f * CHANNELS + ch;
                var x = buf[idx];
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
