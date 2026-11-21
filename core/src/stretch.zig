const std = @import("std");

const Allocator = std.mem.Allocator;

pub const SAMPLE_RATE: usize = 48000;
const CHANNELS: usize = 2;

const FRAME: usize = 2048;
const HOP: usize = FRAME / 2;
const OVERLAP: usize = FRAME - HOP;
const SEARCH: usize = 256;

const RS_CAP: usize = 16384;
const IN_CAP: usize = 32768;
const OUT_CAP: usize = 65536;

pub const Stretch = struct {
    allocator: Allocator,

    speed: f32 = 1,
    pitch: f32 = 0,

    win: []f32 = &.{},
    ola: []f32 = &.{},

    rs_buf: []f32 = &.{},
    rs_len: usize = 0,
    rs_pos: f64 = 0,
    rs_step: f64 = 1,
    consumed: usize = 0,
    out_frames: usize = 0,
    real_in: usize = 0,
    flushing: bool = false,

    in: []f32 = &.{},
    in_len: usize = 0,

    out: []f32 = &.{},
    out_len: usize = 0,

    started: bool = false,

    pub fn init(allocator: Allocator) !Stretch {
        var self = Stretch{ .allocator = allocator };
        self.win = try allocator.alloc(f32, FRAME);
        errdefer allocator.free(self.win);
        self.ola = try allocator.alloc(f32, FRAME * CHANNELS);
        errdefer allocator.free(self.ola);
        self.rs_buf = try allocator.alloc(f32, RS_CAP * CHANNELS);
        errdefer allocator.free(self.rs_buf);
        self.in = try allocator.alloc(f32, IN_CAP * CHANNELS);
        errdefer allocator.free(self.in);
        self.out = try allocator.alloc(f32, OUT_CAP * CHANNELS);
        var i: usize = 0;
        while (i < FRAME) : (i += 1) {
            self.win[i] = 0.5 - 0.5 * @cos(2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(FRAME)));
        }
        self.reset();
        return self;
    }

    pub fn deinit(self: *Stretch) void {
        self.allocator.free(self.win);
        self.allocator.free(self.ola);
        self.allocator.free(self.rs_buf);
        self.allocator.free(self.in);
        self.allocator.free(self.out);
    }

    pub fn reset(self: *Stretch) void {
        self.rs_len = 0;
        self.rs_pos = 0;
        self.consumed = 0;
        self.out_frames = 0;
        self.real_in = 0;
        self.flushing = false;
        self.in_len = 0;
        self.out_len = 0;
        self.started = false;
        @memset(self.ola, 0);
    }

    pub fn configure(self: *Stretch, speed: f32, pitch_semitones: f32) void {
        self.speed = std.math.clamp(speed, 0.25, 4.0);
        self.pitch = std.math.clamp(pitch_semitones, -12.0, 12.0);
        self.rs_step = std.math.pow(f64, 2.0, @as(f64, self.pitch) / 12.0);
    }

    fn resampleRatio(self: *const Stretch) f64 {
        return self.rs_step;
    }

    fn stretchFactor(self: *const Stretch) f64 {
        // output/input = r / speed
        return self.rs_step / @as(f64, self.speed);
    }

    pub fn available(self: *const Stretch) usize {
        return self.out_len;
    }

    pub fn outFree(self: *const Stretch) usize {
        return OUT_CAP - self.out_len;
    }

    pub fn inFree(self: *const Stretch) usize {
        return IN_CAP - self.in_len;
    }

    pub fn drain(self: *Stretch, dst: []f32) usize {
        const want = @min(dst.len / CHANNELS, self.out_len);
        @memcpy(dst[0 .. want * CHANNELS], self.out[0 .. want * CHANNELS]);
        const rest = self.out_len - want;
        if (rest > 0) {
            std.mem.copyForwards(f32, self.out[0 .. rest * CHANNELS], self.out[want * CHANNELS .. self.out_len * CHANNELS]);
        }
        self.out_len = rest;
        return want;
    }

    fn appendIn(self: *Stretch, src: []const f32) bool {
        const frames = src.len / CHANNELS;
        if (self.in_len + frames > IN_CAP) return false;
        @memcpy(self.in[self.in_len * CHANNELS ..][0 .. frames * CHANNELS], src);
        self.in_len += frames;
        return true;
    }

    fn appendReal(self: *Stretch, src: []const f32) bool {
        if (!self.appendIn(src)) return false;
        self.real_in += src.len / CHANNELS;
        return true;
    }

    fn appendOut(self: *Stretch, src: []const f32) bool {
        const frames = src.len / CHANNELS;
        if (self.out_len + frames > OUT_CAP) return false;
        @memcpy(self.out[self.out_len * CHANNELS ..][0 .. frames * CHANNELS], src);
        self.out_len += frames;
        return true;
    }

    fn pushResampled(self: *Stretch, input: []const f32) void {
        const frames = input.len / CHANNELS;
        var copied: usize = 0;
        while (copied < frames) {
            const room = RS_CAP - self.rs_len;
            if (room == 0) break;
            const chunk = @min(frames - copied, room);
            @memcpy(self.rs_buf[self.rs_len * CHANNELS ..][0 .. chunk * CHANNELS], input[copied * CHANNELS ..][0 .. chunk * CHANNELS]);
            self.rs_len += chunk;
            copied += chunk;

            while (self.rs_pos + 2.0 < @as(f64, @floatFromInt(self.rs_len))) {
                const i: usize = @intFromFloat(@floor(self.rs_pos));
                const frac: f32 = @floatCast(self.rs_pos - @as(f64, @floatFromInt(i)));
                if (i == 0) {
                    self.rs_pos += self.rs_step;
                    continue;
                }
                var tmp = [CHANNELS]f32{ 0, 0 };
                var c: usize = 0;
                while (c < CHANNELS) : (c += 1) {
                    const y0 = self.rs_buf[(i - 1) * CHANNELS + c];
                    const y1 = self.rs_buf[i * CHANNELS + c];
                    const y2 = self.rs_buf[(i + 1) * CHANNELS + c];
                    const y3 = self.rs_buf[(i + 2) * CHANNELS + c];
                    tmp[c] = cubic(y0, y1, y2, y3, frac);
                }
                _ = self.appendReal(&tmp);
                self.rs_pos += self.rs_step;
            }

            const drop_f: f64 = @floor(self.rs_pos) - 1.0;
            if (drop_f >= 1.0) {
                const drop: usize = @intFromFloat(drop_f);
                const keep = self.rs_len - drop;
                std.mem.copyForwards(f32, self.rs_buf[0 .. keep * CHANNELS], self.rs_buf[drop * CHANNELS .. self.rs_len * CHANNELS]);
                self.rs_len = keep;
                self.rs_pos -= @floatFromInt(drop);
            }
        }
    }

    pub fn push(self: *Stretch, input: []const f32) void {
        if (self.rs_step != 1.0) {
            self.pushResampled(input);
        } else {
            _ = self.appendReal(input);
        }
        self.process();
    }

    pub fn flush(self: *Stretch) void {
        self.flushing = true;
        defer self.flushing = false;
        var guard: usize = 0;
        while (self.consumed < self.real_in and guard < 8192) : (guard += 1) {
            const need = FRAME + SEARCH + HOP;
            if (self.in_len < need) {
                const pad = need - self.in_len;
                if (self.in_len + pad > IN_CAP) break;
                @memset(self.in[self.in_len * CHANNELS .. (self.in_len + pad) * CHANNELS], 0);
                self.in_len += pad;
            }
            const before_out = self.out_len;
            const before_cons = self.consumed;
            self.process();
            if (self.consumed == before_cons and self.out_len == before_out) break;
            if (self.out_len + HOP > OUT_CAP) break;
        }
    }

    fn addFrame(self: *Stretch, at: usize) bool {
        if (self.out_len + HOP > OUT_CAP) return false;
        var i: usize = 0;
        while (i < FRAME) : (i += 1) {
            const w = self.win[i];
            var c: usize = 0;
            while (c < CHANNELS) : (c += 1) {
                self.ola[i * CHANNELS + c] += self.in[(at + i) * CHANNELS + c] * w;
            }
        }
        _ = self.appendOut(self.ola[0 .. HOP * CHANNELS]);
        const rest = FRAME - HOP;
        std.mem.copyForwards(f32, self.ola[0 .. rest * CHANNELS], self.ola[HOP * CHANNELS .. FRAME * CHANNELS]);
        @memset(self.ola[rest * CHANNELS .. FRAME * CHANNELS], 0);
        return true;
    }

    fn process(self: *Stretch) void {
        const s = self.stretchFactor();

        if (!self.started) {
            if (self.in_len < FRAME) return;
            if (!self.addFrame(0)) return;
            self.started = true;
            self.out_frames = HOP;
        }

        const max_base = IN_CAP - FRAME - SEARCH;
        while (true) {
            if (self.out_len + HOP > OUT_CAP) return;
            if (self.flushing and self.consumed >= self.real_in) return;

            const target = @as(f64, @floatFromInt(self.out_frames)) / s;
            var base_f = target - @as(f64, @floatFromInt(self.consumed));
            if (base_f < 1) base_f = 1;
            if (base_f > @as(f64, @floatFromInt(max_base))) base_f = @as(f64, @floatFromInt(max_base));
            const base: usize = @intFromFloat(@round(base_f));
            if (self.in_len < base + SEARCH + FRAME) return;

            const lo: usize = @min(SEARCH, base);
            var best_d: isize = 0;
            var best: f32 = -std.math.floatMax(f32);
            var d_i: isize = -@as(isize, @intCast(lo));
            const hi: isize = @intCast(SEARCH);
            while (d_i <= hi) : (d_i += 1) {
                const c: usize = @intCast(@as(isize, @intCast(base)) + d_i);
                var dot: f32 = 0;
                var en: f32 = 0;
                var k: usize = 0;
                while (k < OVERLAP) : (k += 1) {
                    var ch: usize = 0;
                    while (ch < CHANNELS) : (ch += 1) {
                        const a = self.in[(HOP + k) * CHANNELS + ch];
                        const b = self.in[(c + k) * CHANNELS + ch];
                        dot += a * b;
                        en += b * b;
                    }
                }
                const score = if (en > 1e-9) dot / @sqrt(en) else -std.math.floatMax(f32);
                if (score > best) {
                    best = score;
                    best_d = d_i;
                }
            }

            const chosen: usize = @intCast(@as(isize, @intCast(base)) + best_d);
            if (!self.addFrame(chosen)) return;

            const drop = chosen;
            if (drop > 0) {
                const keep = self.in_len - drop;
                std.mem.copyForwards(f32, self.in[0 .. keep * CHANNELS], self.in[drop * CHANNELS .. self.in_len * CHANNELS]);
                self.in_len = keep;
            }
            self.consumed += chosen;
            self.out_frames += HOP;
        }
    }
};

fn cubic(y0: f32, y1: f32, y2: f32, y3: f32, t: f32) f32 {
    const a = -0.5 * y0 + 1.5 * y1 - 1.5 * y2 + 0.5 * y3;
    const b = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3;
    const c = -0.5 * y0 + 0.5 * y2;
    return ((a * t + b) * t + c) * t + y1;
}

fn trimSilence(samples: []const f32) []const f32 {
    const n = samples.len / CHANNELS;
    var a: usize = 0;
    while (a < n and @abs(samples[a * CHANNELS]) < 0.02) a += 1;
    var b: usize = n;
    while (b > a and @abs(samples[(b - 1) * CHANNELS]) < 0.02) b -= 1;
    if (b <= a) return samples[0..0];
    return samples[a * CHANNELS .. b * CHANNELS];
}

fn zeroCrossings(samples: []const f32) usize {
    var count: usize = 0;
    var i: usize = CHANNELS;
    while (i < samples.len) : (i += CHANNELS) {
        if ((samples[i - CHANNELS] < 0 and samples[i] >= 0) or (samples[i - CHANNELS] >= 0 and samples[i] < 0)) count += 1;
    }
    return count;
}

fn makeTone(buf: []f32, freq: f64, frames: usize) void {
    var i: usize = 0;
    while (i < frames) : (i += 1) {
        const v: f32 = @floatCast(@sin(2.0 * std.math.pi * freq * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(SAMPLE_RATE))));
        buf[i * CHANNELS] = v;
        buf[i * CHANNELS + 1] = v;
    }
}

fn run(speed: f32, pitch: f32, in_frames: usize, in_buf: []const f32) ![]f32 {
    const alloc = std.testing.allocator;
    var st = try Stretch.init(alloc);
    defer st.deinit();
    st.configure(speed, pitch);

    var out_list = std.ArrayListUnmanaged(f32).empty;
    errdefer out_list.deinit(alloc);
    const tmp = try alloc.alloc(f32, 4096 * CHANNELS);
    defer alloc.free(tmp);

    var fed: usize = 0;
    while (fed < in_frames) {
        const chunk = @min(4096, in_frames - fed);
        st.push(in_buf[fed * CHANNELS ..][0 .. chunk * CHANNELS]);
        fed += chunk;
        while (st.available() > 0) {
            const n = st.drain(tmp);
            try out_list.appendSlice(alloc, tmp[0 .. n * CHANNELS]);
        }
    }
    st.flush();
    while (st.available() > 0) {
        const n = st.drain(tmp);
        try out_list.appendSlice(alloc, tmp[0 .. n * CHANNELS]);
    }
    return out_list.toOwnedSlice(alloc);
}

test "speed 2 conserva el tono y reduce la duracion" {
    const in_frames: usize = SAMPLE_RATE;
    const buf = try std.testing.allocator.alloc(f32, in_frames * CHANNELS);
    defer std.testing.allocator.free(buf);
    makeTone(buf, 440, in_frames);

    const out = try run(2.0, 0, in_frames, buf);
    defer std.testing.allocator.free(out);
    const out_frames = out.len / CHANNELS;
    const secs = @as(f64, @floatFromInt(out_frames)) / @as(f64, @floatFromInt(SAMPLE_RATE));
    const active = trimSilence(out);
    const active_secs = @as(f64, @floatFromInt(active.len / CHANNELS)) / @as(f64, @floatFromInt(SAMPLE_RATE));
    const freq = @as(f64, @floatFromInt(zeroCrossings(active))) / (2.0 * active_secs);
    try std.testing.expect(@abs(secs - 0.5) < 0.06);
    try std.testing.expect(@abs(freq - 440.0) < 25.0);
}

test "pitch +12 dobla la frecuencia y conserva la duracion" {
    const in_frames: usize = SAMPLE_RATE;
    const buf = try std.testing.allocator.alloc(f32, in_frames * CHANNELS);
    defer std.testing.allocator.free(buf);
    makeTone(buf, 440, in_frames);

    const out = try run(1.0, 12.0, in_frames, buf);
    defer std.testing.allocator.free(out);
    const out_frames = out.len / CHANNELS;
    const secs = @as(f64, @floatFromInt(out_frames)) / @as(f64, @floatFromInt(SAMPLE_RATE));
    const active = trimSilence(out);
    const active_secs = @as(f64, @floatFromInt(active.len / CHANNELS)) / @as(f64, @floatFromInt(SAMPLE_RATE));
    const freq = @as(f64, @floatFromInt(zeroCrossings(active))) / (2.0 * active_secs);
    try std.testing.expect(@abs(secs - 1.0) < 0.08);
    try std.testing.expect(@abs(freq - 880.0) < 40.0);
}

test "pitch -12 y speed 0.5 combinan" {
    const in_frames: usize = SAMPLE_RATE;
    const buf = try std.testing.allocator.alloc(f32, in_frames * CHANNELS);
    defer std.testing.allocator.free(buf);
    makeTone(buf, 440, in_frames);

    const out = try run(0.5, -12.0, in_frames, buf);
    defer std.testing.allocator.free(out);
    const out_frames = out.len / CHANNELS;
    const secs = @as(f64, @floatFromInt(out_frames)) / @as(f64, @floatFromInt(SAMPLE_RATE));
    const active = trimSilence(out);
    const active_secs = @as(f64, @floatFromInt(active.len / CHANNELS)) / @as(f64, @floatFromInt(SAMPLE_RATE));
    const freq = @as(f64, @floatFromInt(zeroCrossings(active))) / (2.0 * active_secs);
    try std.testing.expect(@abs(secs - 2.0) < 0.12);
    try std.testing.expect(@abs(freq - 220.0) < 20.0);
}
