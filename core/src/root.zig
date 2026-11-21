const std = @import("std");
const eq = @import("eq.zig");

pub const SAMPLE_RATE: u32 = 48000;
pub const CHANNELS: u32 = 2;

const Allocator = std.mem.Allocator;
const RenderFn = *const fn (?*anyopaque, [*]f32, u32) callconv(.c) void;

const RING_FRAMES: usize = SAMPLE_RATE * 4; // 4 segundos de margen
const SCRATCH_FRAMES: usize = 4096;
const NO_SEEK: usize = std.math.maxInt(usize);

const ch_decoder = opaque {};

extern fn ch_audio_create(render: RenderFn, user: ?*anyopaque, sample_rate: u32, channels: u32) ?*anyopaque;
extern fn ch_audio_destroy(audio: ?*anyopaque) void;
extern fn ch_audio_start(audio: ?*anyopaque) i32;
extern fn ch_audio_stop(audio: ?*anyopaque) i32;
extern fn ch_audio_last_error() [*c]const u8;

extern fn ch_decode_open(path: [*c]const u8, out_rate: u32, out_channels: u32) ?*ch_decoder;
extern fn ch_decode_read(decoder: *ch_decoder, out: [*]f32, frames: u64) u64;
extern fn ch_decode_seek_frame(decoder: *ch_decoder, frame: u64) i32;
extern fn ch_decode_duration(decoder: *ch_decoder) f64;
extern fn ch_decode_title(decoder: *ch_decoder) [*c]const u8;
extern fn ch_decode_artist(decoder: *ch_decoder) [*c]const u8;
extern fn ch_decode_album(decoder: *ch_decoder) [*c]const u8;
extern fn ch_decode_cover(decoder: *ch_decoder, size: *u64) [*c]const u8;
extern fn ch_decode_close(decoder: *ch_decoder) void;
extern fn ch_decode_last_error() [*c]const u8;

var global_error: [256]u8 = @splat(0);

fn setGlobalError(msg: []const u8) void {
    const n = @min(msg.len, global_error.len - 1);
    @memcpy(global_error[0..n], msg[0..n]);
    global_error[n] = 0;
}

fn copyAudioError() void {
    setGlobalError(std.mem.span(ch_audio_last_error()));
}

fn sleepMs(ms: u32) void {
    _ = std.posix.poll(&.{}, @intCast(ms)) catch {};
}

const Ring = struct {
    buf: []f32 = undefined,
    cap: usize = 0,
    read: usize = 0, // frames consumidos
    write: usize = 0, // frames escritos
    discard: usize = 0, // frames que el lector debe saltar
};

pub const Engine = struct {
    allocator: Allocator,
    audio: ?*anyopaque = null,
    decoder: ?*ch_decoder = null,

    ring: Ring = .{},
    scratch: []f32 = undefined,
    scratch_frames: usize = 0,

    thread: ?std.Thread = null,
    stop: bool = false,
    idle: bool = true,

    playing: bool = false,
    eof: bool = false,
    played: usize = 0,
    frames: usize = 0,
    seek_req: usize = NO_SEEK,
    volume_bits: u32 = @bitCast(@as(f32, 1)),
    equalizer: eq.Equalizer = .{},

    title: [256]u8 = @splat(0),
    artist: [256]u8 = @splat(0),
    album: [256]u8 = @splat(0),
    cover: ?[]u8 = null,

    err: [256]u8 = @splat(0),

    fn setError(self: *Engine, msg: []const u8) void {
        const n = @min(msg.len, self.err.len - 1);
        @memcpy(self.err[0..n], msg[0..n]);
        self.err[n] = 0;
    }

    fn clearError(self: *Engine) void {
        self.err[0] = 0;
    }

    fn volume(self: *const Engine) f32 {
        return @bitCast(@atomicLoad(u32, &self.volume_bits, .monotonic));
    }

    fn fail(self: *Engine, msg: []const u8, code: i32) i32 {
        self.setError(msg);
        return code;
    }

    fn writeRingAt(self: *Engine, start_frame: usize, data: []const f32) void {
        const cap = self.ring.cap;
        var frame = start_frame % cap;
        var src: usize = 0;
        var remaining = data.len / CHANNELS;
        while (remaining > 0) {
            const chunk = @min(remaining, cap - frame);
            @memcpy(
                self.ring.buf[frame * CHANNELS ..][0 .. chunk * CHANNELS],
                data[src * CHANNELS ..][0 .. chunk * CHANNELS],
            );
            frame = (frame + chunk) % cap;
            src += chunk;
            remaining -= chunk;
        }
    }

    fn readRingAt(self: *Engine, start_frame: usize, out: []f32) void {
        const cap = self.ring.cap;
        var frame = start_frame % cap;
        var dst: usize = 0;
        var remaining = out.len / CHANNELS;
        while (remaining > 0) {
            const chunk = @min(remaining, cap - frame);
            @memcpy(
                out[dst * CHANNELS ..][0 .. chunk * CHANNELS],
                self.ring.buf[frame * CHANNELS ..][0 .. chunk * CHANNELS],
            );
            frame = (frame + chunk) % cap;
            dst += chunk;
            remaining -= chunk;
        }
    }

    fn writeRing(self: *Engine, data: []const f32) usize {
        const total = data.len / CHANNELS;
        var done: usize = 0;
        while (done < total) {
            if (@atomicLoad(bool, &self.stop, .acquire)) break;
            if (@atomicLoad(usize, &self.seek_req, .acquire) != NO_SEEK) break;
            if (!@atomicLoad(bool, &self.playing, .acquire)) break;
            const w = @atomicLoad(usize, &self.ring.write, .acquire);
            const r = @atomicLoad(usize, &self.ring.read, .acquire);
            var used = w -% r;
            if (used > self.ring.cap) used = 0;
            const free = self.ring.cap - used;
            if (free == 0) {
                sleepMs(2);
                continue;
            }
            const chunk = @min(free, total - done);
            self.writeRingAt(w, data[done * CHANNELS ..][0 .. chunk * CHANNELS]);
            @atomicStore(usize, &self.ring.write, w +% chunk, .release);
            done += chunk;
        }
        return done;
    }

    fn flushRing(self: *Engine) void {
        const w = @atomicLoad(usize, &self.ring.write, .acquire);
        const r = @atomicLoad(usize, &self.ring.read, .acquire);
        var avail = w -% r;
        if (avail > self.ring.cap) avail = 0;
        _ = @atomicRmw(usize, &self.ring.discard, .Xchg, avail, .release);
        var i: usize = 0;
        while (i < 1000) : (i += 1) {
            const r2 = @atomicLoad(usize, &self.ring.read, .acquire);
            const w2 = @atomicLoad(usize, &self.ring.write, .acquire);
            if (r2 == w2) return;
            sleepMs(1);
        }
    }

    fn waitIdle(self: *Engine, tries: usize) bool {
        var i: usize = 0;
        while (i < tries) : (i += 1) {
            if (@atomicLoad(bool, &self.idle, .acquire)) return true;
            sleepMs(1);
        }
        return false;
    }

    fn doSeek(self: *Engine, target: u64) void {
        const d = self.decoder orelse return;
        self.flushRing();
        _ = ch_decode_seek_frame(d, target);
        @atomicStore(bool, &self.eof, false, .release);
        const frames = @atomicLoad(usize, &self.frames, .acquire);
        const clamped = if (frames > 0) @min(target, @as(u64, frames)) else target;
        @atomicStore(usize, &self.played, @intCast(clamped), .release);
    }

    fn render(self: *Engine, out: []f32) void {
        const frames_out = out.len / CHANNELS;
        @memset(out, 0);

        const d = @atomicRmw(usize, &self.ring.discard, .Xchg, 0, .acq_rel);
        if (d > 0) {
            const r = @atomicLoad(usize, &self.ring.read, .acquire);
            const w = @atomicLoad(usize, &self.ring.write, .acquire);
            var avail = w -% r;
            if (avail > self.ring.cap) avail = 0;
            const skip = @min(d, avail);
            @atomicStore(usize, &self.ring.read, r +% skip, .release);
        }

        if (!@atomicLoad(bool, &self.playing, .acquire)) {
            return;
        }

        const r = @atomicLoad(usize, &self.ring.read, .acquire);
        const w = @atomicLoad(usize, &self.ring.write, .acquire);
        var avail = w -% r;
        if (avail > self.ring.cap) avail = 0;
        const take = @min(frames_out, avail);
        if (take > 0) {
            self.readRingAt(r, out[0 .. take * CHANNELS]);
            @atomicStore(usize, &self.ring.read, r +% take, .release);
            _ = @atomicRmw(usize, &self.played, .Add, take, .monotonic);
        }

        const produced = take * CHANNELS;
        self.equalizer.process(out[0..produced], take);

        const vol = self.volume();
        if (vol != 1) {
            for (out[0..produced]) |*s| s.* *= vol;
        }

        if (take == 0 and @atomicLoad(bool, &self.eof, .acquire)) {
            @atomicStore(bool, &self.playing, false, .release);
        }
    }

    fn storeCover(self: *Engine, d: *ch_decoder) void {
        if (self.cover) |old| {
            self.allocator.free(old);
            self.cover = null;
        }
        var size: u64 = 0;
        const ptr = ch_decode_cover(d, &size);
        if (ptr == null or size == 0) return;
        const n: usize = @intCast(size);
        const copy = self.allocator.alloc(u8, n) catch return;
        @memcpy(copy, ptr[0..n]);
        self.cover = copy;
    }
};

fn decoderLoop(self: *Engine) void {
    while (!@atomicLoad(bool, &self.stop, .acquire)) {
        const target = @atomicRmw(usize, &self.seek_req, .Xchg, NO_SEEK, .acq_rel);
        if (target != NO_SEEK) {
            @atomicStore(bool, &self.idle, false, .release);
            self.doSeek(@intCast(target));
            continue;
        }
        if (!@atomicLoad(bool, &self.playing, .acquire)) {
            @atomicStore(bool, &self.idle, true, .release);
            sleepMs(2);
            continue;
        }
        if (@atomicLoad(bool, &self.eof, .acquire)) {
            @atomicStore(bool, &self.idle, true, .release);
            sleepMs(2);
            continue;
        }
        @atomicStore(bool, &self.idle, false, .release);
        const d = self.decoder orelse {
            sleepMs(2);
            continue;
        };

        const w = @atomicLoad(usize, &self.ring.write, .acquire);
        const r = @atomicLoad(usize, &self.ring.read, .acquire);
        var used = w -% r;
        if (used > self.ring.cap) used = 0;
        const free = self.ring.cap - used;
        if (free < self.scratch_frames) {
            sleepMs(2);
            continue;
        }

        const got = ch_decode_read(d, self.scratch.ptr, self.scratch_frames);
        if (got == 0) {
            @atomicStore(bool, &self.eof, true, .release);
            continue;
        }
        _ = self.writeRing(self.scratch[0 .. @as(usize, @intCast(got)) * CHANNELS]);
    }
    @atomicStore(bool, &self.idle, true, .release);
}

fn renderAudio(user: ?*anyopaque, out: [*]f32, frames: u32) callconv(.c) void {
    const self: *Engine = @ptrCast(@alignCast(user orelse return));
    self.render(out[0 .. @as(usize, frames) * CHANNELS]);
}

fn copyCString(dst: *[256]u8, src: [*c]const u8) void {
    dst[0] = 0;
    if (src == null) return;
    const s = std.mem.span(src);
    const n = @min(s.len, dst.len - 1);
    @memcpy(dst[0..n], s[0..n]);
    dst[n] = 0;
}

fn destroyEngine(e: *Engine) void {
    if (e.audio) |audio| ch_audio_destroy(audio);
    if (e.decoder) |d| ch_decode_close(d);
    if (e.cover) |c| e.allocator.free(c);
    e.allocator.free(e.scratch);
    e.allocator.free(e.ring.buf);
    e.allocator.destroy(e);
}

export fn ch_core_version() [*c]const u8 {
    return @ptrCast("0.2.0");
}

export fn ch_core_last_error() [*c]const u8 {
    return @ptrCast(&global_error);
}

export fn ch_engine_create() ?*Engine {
    const alloc = std.heap.c_allocator;
    const self = alloc.create(Engine) catch {
        setGlobalError("no se pudo reservar memoria para el motor");
        return null;
    };
    self.* = .{ .allocator = alloc };

    self.ring.buf = alloc.alloc(f32, RING_FRAMES * CHANNELS) catch {
        setGlobalError("no se pudo reservar el búfer de audio");
        alloc.destroy(self);
        return null;
    };
    self.ring.cap = RING_FRAMES;

    self.scratch = alloc.alloc(f32, SCRATCH_FRAMES * CHANNELS) catch {
        setGlobalError("no se pudo reservar el búfer de decodificación");
        alloc.free(self.ring.buf);
        alloc.destroy(self);
        return null;
    };
    self.scratch_frames = SCRATCH_FRAMES;

    @atomicStore(bool, &self.idle, true, .release);

    self.audio = ch_audio_create(&renderAudio, self, SAMPLE_RATE, CHANNELS) orelse {
        copyAudioError();
        alloc.free(self.scratch);
        alloc.free(self.ring.buf);
        alloc.destroy(self);
        return null;
    };

    const thread = std.Thread.spawn(.{}, decoderLoop, .{self}) catch {
        setGlobalError("no se pudo iniciar el hilo de audio");
        ch_audio_destroy(self.audio);
        self.audio = null;
        alloc.free(self.scratch);
        alloc.free(self.ring.buf);
        alloc.destroy(self);
        return null;
    };
    self.thread = thread;

    if (ch_audio_start(self.audio) != 0) {
        copyAudioError();
        @atomicStore(bool, &self.stop, true, .release);
        thread.join();
        destroyEngine(self);
        return null;
    }

    return self;
}

export fn ch_engine_destroy(self: ?*Engine) void {
    const e = self orelse return;
    @atomicStore(bool, &e.stop, true, .release);
    @atomicStore(bool, &e.playing, false, .release);
    if (e.thread) |t| t.join();
    destroyEngine(e);
}

export fn ch_engine_load(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    const p = path orelse return e.fail("ruta nula", -1);
    e.clearError();

    @atomicStore(bool, &e.playing, false, .release);
    @atomicStore(usize, &e.seek_req, NO_SEEK, .release);
    if (!e.waitIdle(2000)) {
        return e.fail("el motor de audio no respondió", -3);
    }

    if (e.decoder) |old| {
        ch_decode_close(old);
        e.decoder = null;
    }

    const d = ch_decode_open(p, SAMPLE_RATE, CHANNELS) orelse {
        const msg = std.mem.span(ch_decode_last_error());
        return e.fail(if (msg.len == 0) "no se pudo decodificar el archivo" else msg, -2);
    };

    e.flushRing();

    e.decoder = d;
    const seconds = ch_decode_duration(d);
    const frames_f: f64 = if (seconds > 0) seconds * SAMPLE_RATE else 0;
    const frames: usize = if (frames_f > 0) @intFromFloat(frames_f) else 0;
    @atomicStore(usize, &e.frames, frames, .release);
    @atomicStore(usize, &e.played, 0, .release);
    @atomicStore(bool, &e.eof, false, .release);

    copyCString(&e.title, ch_decode_title(d));
    copyCString(&e.artist, ch_decode_artist(d));
    copyCString(&e.album, ch_decode_album(d));
    e.storeCover(d);

    return 0;
}

export fn ch_engine_play(self: ?*Engine) i32 {
    const e = self orelse return -1;
    if (e.decoder == null) return e.fail("no hay pista cargada", -2);
    const frames = @atomicLoad(usize, &e.frames, .acquire);
    const played = @atomicLoad(usize, &e.played, .acquire);
    if (frames > 0 and played >= frames) {
        @atomicStore(usize, &e.seek_req, 0, .release);
        @atomicStore(bool, &e.eof, false, .release);
    }
    @atomicStore(bool, &e.playing, true, .release);
    return 0;
}

export fn ch_engine_pause(self: ?*Engine) i32 {
    const e = self orelse return -1;
    @atomicStore(bool, &e.playing, false, .release);
    return 0;
}

export fn ch_engine_seek(self: ?*Engine, seconds: f64) i32 {
    const e = self orelse return -1;
    if (e.decoder == null) return e.fail("no hay pista cargada", -2);
    const frames = @atomicLoad(usize, &e.frames, .acquire);
    const target_f = @max(0, seconds) * SAMPLE_RATE;
    var clamped = target_f;
    if (frames > 0) {
        clamped = @min(target_f, @as(f64, @floatFromInt(frames)));
    }
    const frame: usize = @intFromFloat(clamped);
    @atomicStore(usize, &e.seek_req, frame, .release);
    return 0;
}

export fn ch_engine_set_volume(self: ?*Engine, volume: f32) i32 {
    const e = self orelse return -1;
    const clamped = std.math.clamp(volume, 0, 1);
    @atomicStore(u32, &e.volume_bits, @bitCast(clamped), .monotonic);
    return 0;
}

export fn ch_engine_eq_band_count() i32 {
    return eq.BAND_COUNT;
}

export fn ch_engine_set_eq_gains(self: ?*Engine, gains_db: [*c]const f32, count: i32) i32 {
    const e = self orelse return -1;
    if (gains_db == null or count <= 0) return e.fail("bandas de EQ inválidas", -2);
    const n: usize = @min(@as(usize, @intCast(count)), eq.BAND_COUNT);
    e.equalizer.setGains(gains_db[0..n]);
    return 0;
}

export fn ch_engine_set_band_gain(self: ?*Engine, band: i32, db: f32) i32 {
    const e = self orelse return -1;
    if (band < 0 or band >= eq.BAND_COUNT) return e.fail("banda de EQ fuera de rango", -2);
    var gains: [eq.BAND_COUNT]f32 = @splat(0);
    var i: usize = 0;
    while (i < eq.BAND_COUNT) : (i += 1) {
        gains[i] = 0;
    }
    gains[@intCast(band)] = db;
    e.equalizer.setGains(&gains);
    return 0;
}

export fn ch_engine_position(self: ?*Engine) f64 {
    const e = self orelse return 0;
    return @as(f64, @floatFromInt(@atomicLoad(usize, &e.played, .acquire))) / SAMPLE_RATE;
}

export fn ch_engine_duration(self: ?*Engine) f64 {
    const e = self orelse return 0;
    return @as(f64, @floatFromInt(@atomicLoad(usize, &e.frames, .acquire))) / SAMPLE_RATE;
}

export fn ch_engine_sample_rate(self: ?*Engine) f64 {
    _ = self;
    return SAMPLE_RATE;
}

export fn ch_engine_channels(self: ?*Engine) i32 {
    _ = self;
    return CHANNELS;
}

export fn ch_engine_is_playing(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return if (@atomicLoad(bool, &e.playing, .acquire)) 1 else 0;
}

export fn ch_engine_title(self: ?*Engine) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    return @ptrCast(&e.title);
}

export fn ch_engine_artist(self: ?*Engine) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    return @ptrCast(&e.artist);
}

export fn ch_engine_album(self: ?*Engine) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    return @ptrCast(&e.album);
}

export fn ch_engine_cover(self: ?*Engine, size: ?*u64) [*c]const u8 {
    const e = self orelse {
        if (size) |s| s.* = 0;
        return null;
    };
    if (e.cover) |cover| {
        if (size) |s| s.* = @intCast(cover.len);
        return @ptrCast(cover.ptr);
    }
    if (size) |s| s.* = 0;
    return null;
}

export fn ch_engine_last_error(self: ?*Engine) [*c]const u8 {
    const e = self orelse return @ptrCast(&global_error);
    return @ptrCast(&e.err);
}
