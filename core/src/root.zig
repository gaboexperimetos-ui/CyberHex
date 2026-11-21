const std = @import("std");
const eq = @import("eq.zig");
const fft = @import("fft.zig");
const Stretch = @import("stretch.zig").Stretch;

pub const SAMPLE_RATE: u32 = 48000;
pub const CHANNELS: u32 = 2;

const Allocator = std.mem.Allocator;
const RenderFn = *const fn (?*anyopaque, [*]f32, u32) callconv(.c) void;

const RING_FRAMES: usize = SAMPLE_RATE * 4; // 4 segundos de margen
const SCRATCH_FRAMES: usize = 4096;
const NO_SEEK: usize = std.math.maxInt(usize);

/// Sube cuando cambia el ABI (nombres, firmas o semantica de las funciones).
pub const ABI_VERSION: i32 = 3;
const MAX_SEGMENTS: usize = 256;
const MAX_XFADE_FRAMES: usize = SAMPLE_RATE * 12;
const SP_FRAMES: usize = 2048; // ventana del analizador de espectro (~43 ms)
const FADE_COEFF: f32 = 1.0 - @exp(-1.0 / (0.008 * @as(f32, @floatFromInt(SAMPLE_RATE))));

const ch_decoder = opaque {};

extern fn ch_audio_create(render: RenderFn, user: ?*anyopaque, sample_rate: u32, channels: u32, device_index: i32) ?*anyopaque;
extern fn ch_audio_destroy(audio: ?*anyopaque) void;
extern fn ch_audio_start(audio: ?*anyopaque) i32;
extern fn ch_audio_stop(audio: ?*anyopaque) i32;
extern fn ch_audio_device_count() i32;
extern fn ch_audio_device_name(index: i32) [*c]const u8;
extern fn ch_audio_default_device() i32;
extern fn ch_audio_last_error() [*c]const u8;

extern fn ch_decode_open(path: [*c]const u8, out_rate: u32, out_channels: u32) ?*ch_decoder;
extern fn ch_decode_read(decoder: *ch_decoder, out: [*]f32, frames: u64) u64;
extern fn ch_decode_seek_frame(decoder: *ch_decoder, frame: u64) i32;
extern fn ch_decode_duration(decoder: *ch_decoder) f64;
extern fn ch_decode_title(decoder: *ch_decoder) [*c]const u8;
extern fn ch_decode_artist(decoder: *ch_decoder) [*c]const u8;
extern fn ch_decode_album(decoder: *ch_decoder) [*c]const u8;
extern fn ch_decode_tag(decoder: *ch_decoder, key: [*c]const u8) [*c]const u8;
extern fn ch_decode_cover(decoder: *ch_decoder, size: *u64) [*c]const u8;
extern fn ch_decode_cover_count(decoder: *ch_decoder) u32;
extern fn ch_decode_cover_at(decoder: *ch_decoder, index: u32, size: *u64) [*c]const u8;

const ChPlaylist = extern struct { items: [*c][*c]u8, count: c_int };
pub const ChEvent = extern struct { kind: c_int, a: c_int, b: c_int, value: f64 };
pub const EV_STATE: c_int = 1;
pub const EV_TRACK: c_int = 2;
pub const EV_QUEUE: c_int = 3;
pub const EV_END: c_int = 4;
pub const EV_SLEEP: c_int = 5;
extern fn ch_playlist_read(path: [*c]const u8) ChPlaylist;
extern fn ch_playlist_free(playlist: *ChPlaylist) void;
extern fn ch_playlist_write(path: [*c]const u8, items: [*c]const [*c]const u8, count: c_int) i32;

const ch_lyrics = opaque {};
extern fn ch_lyrics_read_file(path: [*c]const u8) ?*ch_lyrics;
extern fn ch_lyrics_free(lyrics: ?*ch_lyrics) void;
extern fn ch_lyrics_count(lyrics: ?*ch_lyrics) c_int;
extern fn ch_lyrics_line_at(lyrics: ?*ch_lyrics, time_s: f64, line_start: ?*f64, index: ?*c_int) [*c]const u8;
extern fn ch_lyrics_offset_ms(lyrics: ?*ch_lyrics) [*c]const u8;

const ch_library = opaque {};
extern fn c_lib_create() ?*ch_library;
extern fn c_lib_destroy(lib: ?*ch_library) void;
extern fn c_lib_scan(lib: ?*ch_library, root: [*c]const u8, exts: [*c]const [*c]const u8, ext_count: c_int) c_int;
extern fn c_lib_count(lib: ?*const ch_library) c_int;
extern fn c_lib_path(lib: ?*const ch_library, index: c_int) [*c]const u8;
extern fn c_lib_removed(lib: ?*const ch_library) c_int;
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

fn monoMs() u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(@max(ts.sec, 0))) * 1000 +
        @as(u64, @intCast(@divTrunc(@max(ts.nsec, 0), 1_000_000)));
}

fn parseLeadingFloat(text: []const u8) ?f32 {
    var end: usize = 0;
    var digits: usize = 0;
    while (end < text.len) : (end += 1) {
        switch (text[end]) {
            '0'...'9' => digits += 1,
            '-', '+', '.' => {},
            else => break,
        }
    }
    if (digits == 0) return null;
    return std.fmt.parseFloat(f32, text[0..end]) catch null;
}

fn copyCString(dst: *[256]u8, src: [*c]const u8) void {
    dst[0] = 0;
    if (src == null) return;
    const s = std.mem.span(src);
    const n = @min(s.len, dst.len - 1);
    @memcpy(dst[0..n], s[0..n]);
    dst[n] = 0;
}

/// Sustituye la extension de `path` por `.lrc` (nueva cadena del allocador).
fn lrcPathFor(allocator: Allocator, path: []const u8) ![:0]u8 {
    var base = path;
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
        const slash = std.mem.lastIndexOfScalar(u8, base, '/');
        if (slash == null or dot > slash.?) base = base[0..dot];
    }
    const out = try allocator.allocSentinel(u8, base.len + 4, 0);
    @memcpy(out[0..base.len], base);
    @memcpy(out[base.len..], ".lrc");
    return out;
}

const Ring = struct {
    buf: []f32 = undefined,
    cap: usize = 0,
    read: usize = 0,
    write: usize = 0,
    discard: usize = 0,
};

const SpinLock = struct {
    state: std.atomic.Mutex = .unlocked,

    fn lock(self: *SpinLock) void {
        while (!self.state.tryLock()) std.Thread.yield() catch {};
    }

    fn tryLock(self: *SpinLock) bool {
        return self.state.tryLock();
    }

    fn unlock(self: *SpinLock) void {
        self.state.unlock();
    }
};

const MAX_COVERS: usize = 4;

const Segment = struct {
    start: usize = 0,
    end: usize = 0,
    index: usize = 0,
    title: [256]u8 = @splat(0),
    artist: [256]u8 = @splat(0),
    album: [256]u8 = @splat(0),
    rg_gain: f32 = 1,
    rg_gain_db: f32 = 0,
    rg_peak: f32 = 0,
    covers: [MAX_COVERS]?[]u8 = @splat(null),
    cover_count: u8 = 0,
    lyrics: ?*ch_lyrics = null,
    lyrics_offset: f64 = 0,
};

threadlocal var tls_title: [256]u8 = undefined;
threadlocal var tls_artist: [256]u8 = undefined;
threadlocal var tls_album: [256]u8 = undefined;

fn moveIndex(from: usize, to: usize, p: usize) usize {
    if (p == from) return to;
    if (from < to) {
        if (p > from and p <= to) return p - 1;
    } else {
        if (p >= to and p < from) return p + 1;
    }
    return p;
}

pub const Engine = struct {
    allocator: Allocator,
    audio: ?*anyopaque = null,
    output_device: i32 = -1,
    decoder: ?*ch_decoder = null,

    ring: Ring = .{},
    scratch: []f32 = undefined,
    scratch_frames: usize = 0,
    stretch: ?Stretch = null,
    stretch_buf: []f32 = &.{},
    stretch_buf_frames: usize = 0,
    speed_bits: u32 = @bitCast(@as(f32, 1)),
    pitch_bits: u32 = @bitCast(@as(f32, 0)),

    sp_buf: []f32 = &.{},
    sp_pos: usize = 0,
    sp_lock: SpinLock = .{},
    sp_re: []f32 = &.{},
    sp_im: []f32 = &.{},

    thread: ?std.Thread = null,
    stop: bool = false,
    idle: bool = true,

    playing: bool = false,
    eof: bool = false,
    played: usize = 0,
    seek_req: usize = NO_SEEK,
    skip_req: usize = NO_SEEK,
    volume_bits: u32 = @bitCast(@as(f32, 1)),
    rg_enabled: bool = true,
    equalizer: eq.Equalizer = .{},
    // Últimas ganancias aplicadas (dB), para que set_band_gain pueda cambiar
    // una sola banda sin borrar las demás.
    eq_gains: [eq.BAND_COUNT]f32 = @splat(0),

    segments: [MAX_SEGMENTS]Segment = undefined,
    seg_count: usize = 0,
    running_end: usize = 0,
    seg_lock: SpinLock = .{},
    last_rg: f32 = 1,

    playlist: std.ArrayListUnmanaged([:0]u8) = .empty,
    queue_index: usize = 0,
    list_mutex: SpinLock = .{},
    gapless: bool = true,
    xfade_bits: u32 = @bitCast(@as(f32, 0)),
    repeat_mode: u32 = 0,
    shuffle: bool = false,
    rng_state: u32 = 0x9E3779B9,
    order: std.ArrayListUnmanaged(usize) = .empty,
    order_pos: usize = 0,
    fade_gain: f32 = 0,
    limit_enabled: bool = false,
    limit_ceiling: f32 = 0.891, // ~ -1 dBFS
    limit_gain: f32 = 1.0,
    sleep_end_ms: u64 = 0,
    sleep_fade_ms: u32 = 8000,
    sleep_fired: bool = false,
    buf_underflows: u64 = 0,
    // Niveles de salida para vumetros (bits de f32, legibles sin candados).
    level_rms: [2]u32 = @splat(0),
    level_peak: [2]u32 = @splat(0),
    pause_fade_bits: u32 = @bitCast(@as(f32, 0.05)),
    // Balance (-1 izquierda .. +1 derecha) en bits de f32 y modo de canales.
    balance_bits: u32 = 0,
    chan_mode: u32 = 0,
    // 0 = ReplayGain por pista, 1 = por album.
    rg_mode: u32 = 0,
    // Loop A-B en marcos absolutos de la cola (NO_SEEK = inactivo).
    ab_start: usize = NO_SEEK,
    ab_end: usize = NO_SEEK,
    // Pistas que no se pudieron abrir y se saltaron solas.
    skipped_tracks: u64 = 0,
    retired_covers: std.ArrayListUnmanaged([]u8) = .empty,

    ev_lock: SpinLock = .{},
    ev_buf: [64]ChEvent = undefined,
    ev_head: usize = 0,
    ev_tail: usize = 0,

    err: [256]u8 = @splat(0),

    fn setError(self: *Engine, msg: []const u8) void {
        const n = @min(msg.len, self.err.len - 1);
        @memcpy(self.err[0..n], msg[0..n]);
        self.err[n] = 0;
    }

    fn clearError(self: *Engine) void {
        self.err[0] = 0;
    }

    fn pushEvent(self: *Engine, kind: c_int, a: c_int, b: c_int, value: f64) void {
        // Se puede llamar desde el hilo de audio: si el consumidor tiene el
        // candado, se reintenta unas pocas veces y se descarta el evento antes
        // que bloquear el callback.
        var tries: usize = 0;
        while (!self.ev_lock.tryLock()) : (tries += 1) {
            if (tries >= 64) return;
            std.atomic.spinLoopHint();
        }
        const next = (self.ev_head + 1) % self.ev_buf.len;
        if (next == self.ev_tail) {
            self.ev_tail = (self.ev_tail + 1) % self.ev_buf.len;
        }
        self.ev_buf[self.ev_head] = .{ .kind = kind, .a = a, .b = b, .value = value };
        self.ev_head = next;
        self.ev_lock.unlock();
    }

    fn fail(self: *Engine, msg: []const u8, code: i32) i32 {
        self.setError(msg);
        return code;
    }

    fn volume(self: *const Engine) f32 {
        return @bitCast(@atomicLoad(u32, &self.volume_bits, .monotonic));
    }

    fn speedValue(self: *const Engine) f32 {
        return @bitCast(@atomicLoad(u32, &self.speed_bits, .monotonic));
    }

    fn pitchValue(self: *const Engine) f32 {
        return @bitCast(@atomicLoad(u32, &self.pitch_bits, .monotonic));
    }

    fn stretchActive(self: *const Engine) bool {
        return self.speedValue() != 1 or self.pitchValue() != 0;
    }

    fn resetStretch(self: *Engine) void {
        if (self.stretch) |*st| {
            st.configure(self.speedValue(), self.pitchValue());
            st.reset();
        }
    }

    fn stretchStale(self: *const Engine) bool {
        const st = if (self.stretch) |*s| s else return false;
        return st.speed != self.speedValue() or st.pitch != self.pitchValue();
    }

    fn applyHotStretchChange(self: *Engine) void {
        const d = self.decoder orelse {
            self.resetStretch();
            return;
        };
        const p = @atomicLoad(usize, &self.played, .acquire);
        var target: usize = 0;
        self.seg_lock.lock();
        if (self.findSegment(p)) |pos| {
            const s = &self.segments[pos];
            if (p > s.start) target = @min(p - s.start, s.end - s.start);
        }
        self.seg_lock.unlock();

        self.resetStretch();
        self.flushRing();
        _ = ch_decode_seek_frame(d, target);
        @atomicStore(bool, &self.eof, false, .release);
    }

    fn ringFree(self: *Engine) usize {
        const w = @atomicLoad(usize, &self.ring.write, .acquire);
        const r = @atomicLoad(usize, &self.ring.read, .acquire);
        var used = w -% r;
        if (used > self.ring.cap) used = 0;
        return self.ring.cap - used;
    }

    fn drainStretch(self: *Engine, st: *Stretch) bool {
        while (st.available() > 0) {
            const free = self.ringFree();
            if (free == 0) return false;
            const chunk = @min(@min(free, st.available()), self.stretch_buf_frames);
            if (chunk == 0) return false;
            const n = st.drain(self.stretch_buf[0 .. chunk * CHANNELS]);
            if (n == 0) break;
            _ = self.writeRing(self.stretch_buf[0 .. n * CHANNELS]);
        }
        return st.available() == 0;
    }

    fn findSegment(self: *Engine, frame: usize) ?usize {
        var i = self.seg_count;
        while (i > 0) {
            i -= 1;
            if (frame >= self.segments[i].start) return i;
        }
        return if (self.seg_count > 0) 0 else null;
    }

    fn dropCovers(self: *Engine, s: *Segment) void {
        var i: usize = 0;
        while (i < MAX_COVERS) : (i += 1) {
            if (s.covers[i]) |c| {
                self.retired_covers.append(self.allocator, c) catch self.allocator.free(c);
                s.covers[i] = null;
            }
        }
        s.cover_count = 0;
    }

    fn trimAfter(self: *Engine, pos: usize) void {
        if (pos + 1 >= self.seg_count) return;
        for (self.segments[pos + 1 .. self.seg_count]) |*s| {
            self.dropCovers(s);
            if (s.lyrics) |ly| ch_lyrics_free(ly);
            s.* = .{};
        }
        self.seg_count = pos + 1;
    }

    fn resetSegments(self: *Engine) void {
        self.seg_lock.lock();
        for (self.segments[0..self.seg_count]) |*s| {
            self.dropCovers(s);
            if (s.lyrics) |ly| ch_lyrics_free(ly);
            s.* = .{};
        }
        self.seg_count = 0;
        self.running_end = 0;
        self.seg_lock.unlock();
    }

    fn crossfadeFrames(self: *Engine) usize {
        const secs = @as(f32, @bitCast(@atomicLoad(u32, &self.xfade_bits, .monotonic)));
        if (!(secs > 0)) return 0;
        const f = secs * @as(f32, @floatFromInt(SAMPLE_RATE));
        if (f >= @as(f32, @floatFromInt(MAX_XFADE_FRAMES))) return MAX_XFADE_FRAMES;
        return @intFromFloat(f);
    }

    fn rebaseLocked(self: *Engine) void {
        if (self.seg_count == 0) return;
        const p = @atomicLoad(usize, &self.played, .acquire);
        var keep: usize = 0;
        while (keep + 1 < self.seg_count and self.segments[keep].end <= p) keep += 1;
        if (keep == 0) return;
        const offset = self.segments[keep].start;
        if (offset == 0) return;

        var i: usize = 0;
        while (i < keep) : (i += 1) {
            self.dropCovers(&self.segments[i]);
            if (self.segments[i].lyrics) |ly| ch_lyrics_free(ly);
            self.segments[i].lyrics = null;
        }

        const remaining = self.seg_count - keep;
        var j: usize = 0;
        while (j < remaining) : (j += 1) {
            self.segments[j] = self.segments[keep + j];
            self.segments[j].start -= offset;
            self.segments[j].end -= offset;
        }
        self.seg_count = remaining;
        self.running_end -= offset;
        _ = @atomicRmw(usize, &self.played, .Sub, offset, .release);
    }

    fn loadLyricsFor(self: *Engine, index: usize, seg: *Segment) void {
        if (index >= self.playlist.items.len) return;
        const path = self.playlist.items[index];
        const lrc = lrcPathFor(self.allocator, path) catch return;
        defer self.allocator.free(lrc);
        const lyrics = ch_lyrics_read_file(lrc.ptr);
        if (lyrics) |ly| {
            seg.lyrics = ly;
            seg.lyrics_offset = parseLeadingFloat(std.mem.span(ch_lyrics_offset_ms(ly))) orelse 0;
        }
    }

    fn addSegment(self: *Engine, index: usize, d: *ch_decoder, overlap: usize) bool {
        if (self.seg_count >= MAX_SEGMENTS) {
            self.seg_lock.lock();
            self.rebaseLocked();
            const full = self.seg_count >= MAX_SEGMENTS;
            self.seg_lock.unlock();
            if (full) return false;
        }

        var seg = Segment{};
        seg.index = index;

        const seconds = ch_decode_duration(d);
        const frames_f: f64 = if (seconds > 0) seconds * SAMPLE_RATE else 0;
        var frames: usize = if (frames_f > 0) @intFromFloat(frames_f) else 0;
        if (frames == 0) frames = SAMPLE_RATE;

        copyCString(&seg.title, ch_decode_title(d));
        copyCString(&seg.artist, ch_decode_artist(d));
        copyCString(&seg.album, ch_decode_album(d));

        // ReplayGain: modo album (una sola ganancia para todo el disco, sin
        // saltos entre pistas) o modo pista. R128_TRACK_GAIN esta en Q7.8.
        const track_db = parseLeadingFloat(std.mem.span(ch_decode_tag(d, "REPLAYGAIN_TRACK_GAIN")));
        const track_peak = parseLeadingFloat(std.mem.span(ch_decode_tag(d, "REPLAYGAIN_TRACK_PEAK")));
        const album_db = parseLeadingFloat(std.mem.span(ch_decode_tag(d, "REPLAYGAIN_ALBUM_GAIN")));
        const album_peak = parseLeadingFloat(std.mem.span(ch_decode_tag(d, "REPLAYGAIN_ALBUM_PEAK")));
        const r128_track = parseLeadingFloat(std.mem.span(ch_decode_tag(d, "R128_TRACK_GAIN")));
        const r128_album = parseLeadingFloat(std.mem.span(ch_decode_tag(d, "R128_ALBUM_GAIN")));

        // El tramo ha cambiado: el loop A-B era de la pista anterior.
        @atomicStore(usize, &self.ab_start, NO_SEEK, .release);
        @atomicStore(usize, &self.ab_end, NO_SEEK, .release);

        const album_mode = @atomicLoad(u32, &self.rg_mode, .acquire) == 1;
        var db: f32 = 0;
        var peak: f32 = 0;
        if (album_mode and album_db != null) {
            db = album_db.?;
            peak = album_peak orelse 0;
        } else if (track_db != null) {
            db = track_db.?;
            peak = track_peak orelse 0;
        } else {
            const q7 = if (album_mode) (r128_album orelse r128_track) else (r128_track orelse r128_album);
            if (q7) |q| db = q / 256.0;
        }

        seg.rg_gain_db = db;
        var linear = std.math.pow(f32, 10, db / 20);
        seg.rg_peak = @max(peak, 0);
        if (seg.rg_peak > 0 and linear * seg.rg_peak > 1) linear = 1 / seg.rg_peak;
        seg.rg_gain = linear;

        var size: u64 = 0;
        const total = ch_decode_cover_count(d);
        var ci: u32 = 0;
        while (ci < total and ci < MAX_COVERS) : (ci += 1) {
            const ptr = ch_decode_cover_at(d, ci, &size);
            if (ptr == null or size == 0) continue;
            const n: usize = @intCast(size);
            if (self.allocator.alloc(u8, n)) |copy| {
                @memcpy(copy, ptr[0..n]);
                seg.covers[seg.cover_count] = copy;
                seg.cover_count += 1;
            } else |_| {}
        }

        // Letra sincronizada: se busca un .lrc junto al audio (mismo nombre).
        self.loadLyricsFor(index, &seg);

        self.seg_lock.lock();
        if (overlap > 0 and self.seg_count > 0) {
            const prev = &self.segments[self.seg_count - 1];
            const real = @min(overlap, prev.end - prev.start);
            prev.end -= real;
            seg.start = prev.end;
        } else {
            seg.start = self.running_end;
        }
        seg.end = seg.start + frames;
        self.segments[self.seg_count] = seg;
        self.seg_count += 1;
        self.running_end = seg.end;
        self.seg_lock.unlock();
        return true;
    }

    fn remapSegments(self: *Engine, from: usize, to: usize, is_move: bool) void {
        self.seg_lock.lock();
        var k: usize = 0;
        while (k < self.seg_count) : (k += 1) {
            const idx = self.segments[k].index;
            if (is_move) {
                self.segments[k].index = moveIndex(from, to, idx);
            } else if (idx >= from) {
                self.segments[k].index = idx + 1;
            }
        }
        self.seg_lock.unlock();
    }

fn audibleLyrics(self: *Engine) ?*ch_lyrics {
    self.seg_lock.lock();
    defer self.seg_lock.unlock();
    const p = @atomicLoad(usize, &self.played, .acquire);
    if (self.findSegment(p)) |pos| return self.segments[pos].lyrics;
    return null;
}

fn audibleLyricsOffset(self: *Engine) f64 {
    self.seg_lock.lock();
    defer self.seg_lock.unlock();
    const p = @atomicLoad(usize, &self.played, .acquire);
    if (self.findSegment(p)) |pos| return self.segments[pos].lyrics_offset;
    return 0;
}

    fn audibleIndex(self: *Engine) ?usize {
        self.seg_lock.lock();
        defer self.seg_lock.unlock();
        const p = @atomicLoad(usize, &self.played, .acquire);
        if (self.findSegment(p)) |pos| return self.segments[pos].index;
        return null;
    }

    fn rand(self: *Engine) u32 {
        var x = self.rng_state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.rng_state = x;
        return x;
    }

    fn rebuildOrderLocked(self: *Engine, current: usize) void {
        const n = self.playlist.items.len;
        self.order.clearRetainingCapacity();
        self.order.ensureTotalCapacity(self.allocator, n) catch return;
        var i: usize = 0;
        while (i < n) : (i += 1) self.order.appendAssumeCapacity(i);
        i = n;
        while (i > 1) {
            i -= 1;
            const j = @as(usize, self.rand()) % (i + 1);
            const tmp = self.order.items[i];
            self.order.items[i] = self.order.items[j];
            self.order.items[j] = tmp;
        }
        self.order_pos = 0;
        if (n > 0 and current < n) {
            var k: usize = 0;
            while (k < n) : (k += 1) {
                if (self.order.items[k] == current) {
                    self.order.items[k] = self.order.items[0];
                    self.order.items[0] = current;
                    break;
                }
            }
        }
    }

    fn syncOrderLocked(self: *Engine, current: usize) void {
        const n = self.playlist.items.len;
        if (n == 0) {
            self.order.clearRetainingCapacity();
            self.order_pos = 0;
            return;
        }
        if (self.order.items.len != n) {
            self.rebuildOrderLocked(current);
            return;
        }
        if (self.order_pos >= n) self.order_pos = 0;
        var pos: usize = 0;
        while (pos < n and self.order.items[pos] != current) pos += 1;
        if (pos == n) {
            self.rebuildOrderLocked(current);
            return;
        }
        if (pos == self.order_pos) return;
        self.order_pos = pos;
    }

    fn nextAfterLocked(self: *Engine, current: usize) ?usize {
        const n = self.playlist.items.len;
        if (n == 0) return null;
        const repeat_all = @atomicLoad(u32, &self.repeat_mode, .monotonic) == 1;
        if (@atomicLoad(bool, &self.shuffle, .monotonic)) {
            self.syncOrderLocked(current);
            if (self.order.items.len != n) return if (repeat_all) current else null;
            if (self.order_pos + 1 < n) {
                self.order_pos += 1;
                return self.order.items[self.order_pos];
            }
            if (!repeat_all) return null;
            self.rebuildOrderLocked(current);
            if (n <= 1) return self.order.items[0];
            self.order_pos = 1;
            return self.order.items[1];
        }
        if (current + 1 < n) return current + 1;
        if (repeat_all) return 0;
        return null;
    }

    fn prevBeforeLocked(self: *Engine, current: usize) ?usize {
        const n = self.playlist.items.len;
        if (n == 0) return null;
        const repeat_all = @atomicLoad(u32, &self.repeat_mode, .monotonic) == 1;
        if (@atomicLoad(bool, &self.shuffle, .monotonic)) {
            self.syncOrderLocked(current);
            if (self.order.items.len != n) return if (repeat_all) current else null;
            if (self.order_pos > 0) {
                self.order_pos -= 1;
                return self.order.items[self.order_pos];
            }
            if (!repeat_all) return null;
            self.order_pos = n - 1;
            return self.order.items[self.order_pos];
        }
        if (current > 0) return current - 1;
        if (repeat_all) return n - 1;
        return null;
    }

    fn noteAddedLocked(self: *Engine, index: usize) void {
        if (!@atomicLoad(bool, &self.shuffle, .monotonic)) return;
        if (self.order.items.len != index) return;
        if (index == 0) {
            self.order.append(self.allocator, 0) catch {};
            self.order_pos = 0;
            return;
        }
        const span = index - self.order_pos;
        const pos = self.order_pos + 1 + @as(usize, self.rand()) % span;
        self.order.insert(self.allocator, pos, index) catch {
            self.order.append(self.allocator, index) catch {};
        };
    }

    fn rollbackOrder(self: *Engine, saved_pos: usize) void {
        self.list_mutex.lock();
        self.order_pos = saved_pos;
        self.list_mutex.unlock();
    }

    fn audibleGain(self: *Engine) f32 {
        if (self.seg_lock.tryLock()) {
            defer self.seg_lock.unlock();
            const p = @atomicLoad(usize, &self.played, .acquire);
            if (self.findSegment(p)) |pos| {
                self.last_rg = self.segments[pos].rg_gain;
                return self.last_rg;
            }
            return 1;
        }
        return self.last_rg;
    }

    fn copyMetaField(self: *Engine, out: *[256]u8, comptime field: []const u8) void {
        self.seg_lock.lock();
        defer self.seg_lock.unlock();
        out[0] = 0;
        const p = @atomicLoad(usize, &self.played, .acquire);
        if (self.findSegment(p)) |pos| {
            const src = @field(self.segments[pos], field);
            @memcpy(out[0..], src[0..]);
        }
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
            if (@atomicLoad(usize, &self.skip_req, .acquire) != NO_SEEK) break;
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

    fn openDecoderOnly(self: *Engine, index: usize) bool {
        self.list_mutex.lock();
        if (index >= self.playlist.items.len) {
            self.list_mutex.unlock();
            return false;
        }
        const path = self.playlist.items[index];
        const d = ch_decode_open(path.ptr, SAMPLE_RATE, CHANNELS) orelse {
            self.list_mutex.unlock();
            return false;
        };
        const old = self.decoder;
        self.decoder = d;
        self.queue_index = index;
        const count: c_int = @intCast(self.playlist.items.len);
        self.list_mutex.unlock();

        if (old) |o| ch_decode_close(o);
        self.pushEvent(EV_TRACK, @intCast(index), count, 0);
        return true;
    }

    fn beginAt(self: *Engine, index: usize) i32 {
        self.resetSegments();
        self.resetStretch();
        if (!self.openDecoderOnly(index)) {
            const msg = std.mem.span(ch_decode_last_error());
            return self.fail(if (msg.len == 0) "no se pudo decodificar el archivo" else msg, -2);
        }
        const d = self.decoder.?;
        _ = self.addSegment(index, d, 0);
        @atomicStore(usize, &self.played, 0, .release);
        @atomicStore(bool, &self.eof, false, .release);
        // Fundido de entrada suave (evita el clic al abrir una pista nueva).
        self.fade_gain = 0;
        return 0;
    }

    fn openNextAuto(self: *Engine) bool {
        self.list_mutex.lock();
        const mode = @atomicLoad(u32, &self.repeat_mode, .monotonic);
        var candidate: ?usize = if (mode == 2) self.queue_index else self.nextAfterLocked(self.queue_index);
        var attempts: usize = 0;
        while (candidate) |next| {
            if (next >= self.playlist.items.len) break;
            // Un archivo ilegible no debe cortar la cola: se salta y se prueba
            // el siguiente (con repeat-one no, seria un bucle sobre el roto).
            if (attempts >= self.playlist.items.len) break;
            if (mode == 2 and attempts > 0) break;
            attempts += 1;

            const path = self.playlist.items[next];
            if (ch_decode_open(path.ptr, SAMPLE_RATE, CHANNELS)) |d| {
                const old = self.decoder;
                self.decoder = d;
                self.queue_index = next;
                self.list_mutex.unlock();

                if (old) |o| ch_decode_close(o);
                self.resetStretch();
                _ = self.addSegment(next, d, 0);
                @atomicStore(bool, &self.eof, false, .release);
                @atomicStore(bool, &self.playing, true, .release);
                self.pushEvent(EV_TRACK, @intCast(next), 0, 0);
                return true;
            }
            self.skipped_tracks +%= 1;
            candidate = self.nextAfterLocked(next);
        }
        self.list_mutex.unlock();
        return false;
    }

    fn mixCrossfadeIntoRing(self: *Engine, abs_start: usize, head: []const f32, frames: usize) void {
        var off: usize = 0;
        while (off < frames) {
            const chunk = @min(frames - off, self.scratch_frames);
            const tmp = self.scratch[0 .. chunk * CHANNELS];
            self.readRingAt(abs_start + off, tmp);
            var i: usize = 0;
            while (i < chunk) : (i += 1) {
                const t = @as(f32, @floatFromInt(off + i)) / @as(f32, @floatFromInt(frames));
                const angle = t * (std.math.pi / 2.0);
                const fade_out = @cos(angle);
                const fade_in = @sin(angle);
                const src = head[(off + i) * CHANNELS ..][0..CHANNELS];
                var c: usize = 0;
                while (c < CHANNELS) : (c += 1) {
                    tmp[i * CHANNELS + c] = tmp[i * CHANNELS + c] * fade_out + src[c] * fade_in;
                }
            }
            self.writeRingAt(abs_start + off, tmp);
            off += chunk;
        }
    }

    fn crossfadeIntoNext(self: *Engine) bool {
        const want = self.crossfadeFrames();
        if (want == 0) return false;
        if (self.stretchActive()) return false;

        var prev_end: usize = 0;
        var a_frames: usize = 0;
        self.seg_lock.lock();
        if (self.seg_count == 0) {
            self.seg_lock.unlock();
            return false;
        }
        prev_end = self.segments[self.seg_count - 1].end;
        a_frames = prev_end - self.segments[self.seg_count - 1].start;
        self.seg_lock.unlock();

        self.list_mutex.lock();
        if (@atomicLoad(u32, &self.repeat_mode, .monotonic) == 2) {
            self.list_mutex.unlock();
            return false;
        }
        const saved_pos = self.order_pos;
        const next = self.nextAfterLocked(self.queue_index) orelse {
            self.list_mutex.unlock();
            return false;
        };
        if (next >= self.playlist.items.len) {
            self.list_mutex.unlock();
            return false;
        }
        const path = self.playlist.items[next];
        const d = ch_decode_open(path.ptr, SAMPLE_RATE, CHANNELS) orelse {
            self.order_pos = saved_pos;
            self.list_mutex.unlock();
            return false;
        };
        self.list_mutex.unlock();

        const b_seconds = ch_decode_duration(d);
        var b_frames: usize = if (b_seconds > 0) @intFromFloat(b_seconds * SAMPLE_RATE) else 0;
        if (b_frames == 0) b_frames = SAMPLE_RATE;

        const w = @atomicLoad(usize, &self.ring.write, .acquire);
        const r = @atomicLoad(usize, &self.ring.read, .acquire);
        var avail = w -% r;
        if (avail > self.ring.cap) avail = 0;

        var overlap = @min(want, @min(a_frames, b_frames));
        const margin: usize = SAMPLE_RATE / 2;
        if (avail > margin) {
            overlap = @min(overlap, avail - margin);
        } else {
            overlap = 0;
        }
        const min_overlap: usize = SAMPLE_RATE / 50;
        if (overlap < min_overlap) {
            self.rollbackOrder(saved_pos);
            ch_decode_close(d);
            return false;
        }

        const head = self.allocator.alloc(f32, overlap * CHANNELS) catch {
            ch_decode_close(d);
            return false;
        };
        defer self.allocator.free(head);

        var got: usize = 0;
        while (got < overlap) {
            const n = ch_decode_read(d, head.ptr + got * CHANNELS, overlap - got);
            if (n == 0) break;
            got += @intCast(n);
        }
        if (got < min_overlap) {
            self.rollbackOrder(saved_pos);
            ch_decode_close(d);
            return false;
        }
        overlap = got;

        const old = self.decoder;
        self.decoder = d;
        self.list_mutex.lock();
        self.queue_index = next;
        self.list_mutex.unlock();

        self.mixCrossfadeIntoRing(w - overlap, head, overlap);
        _ = self.addSegment(next, d, overlap);

        if (old) |o| ch_decode_close(o);
        @atomicStore(bool, &self.eof, false, .release);
        @atomicStore(bool, &self.playing, true, .release);
        self.pushEvent(EV_TRACK, @intCast(next), 0, 0);
        return true;
    }

    fn doSeek(self: *Engine, target: u64) void {
        const d = self.decoder orelse return;
        const p = @atomicLoad(usize, &self.played, .acquire);

        var seg_pos: usize = 0;
        var seg_start: usize = 0;
        var seg_end: usize = 0;
        var seg_index: usize = 0;
        var found = false;
        self.seg_lock.lock();
        if (self.findSegment(p)) |pos| {
            const s = &self.segments[pos];
            seg_pos = pos;
            seg_start = s.start;
            seg_end = s.end;
            seg_index = s.index;
            found = true;
        }
        self.seg_lock.unlock();

        if (!found) {
            self.flushRing();
            self.resetStretch();
            _ = ch_decode_seek_frame(d, target);
            @atomicStore(bool, &self.eof, false, .release);
            @atomicStore(usize, &self.played, @intCast(target), .release);
            return;
        }

        if (self.queue_index != seg_index) {
            if (!self.openDecoderOnly(seg_index)) return;
        }
        const dd = self.decoder orelse return;
        self.flushRing();
        self.resetStretch();
        _ = ch_decode_seek_frame(dd, target);

        const span = seg_end - seg_start;
        const t: usize = @min(@as(usize, @intCast(target)), span);
        @atomicStore(usize, &self.played, seg_start + t, .release);
        @atomicStore(bool, &self.eof, false, .release);

        self.seg_lock.lock();
        self.trimAfter(seg_pos);
        self.running_end = seg_end;
        self.seg_lock.unlock();
    }

    fn sleepRemainingMs(self: *Engine) i64 {
        const end = @atomicLoad(u64, &self.sleep_end_ms, .acquire);
        if (end == 0) return -1;
        const now = monoMs();
        if (now >= end) return 0;
        return @intCast(end - now);
    }

    fn sleepGain(self: *Engine) ?f32 {
        const remaining = self.sleepRemainingMs();
        if (remaining < 0) return null;
        const fade: i64 = @intCast(@atomicLoad(u32, &self.sleep_fade_ms, .monotonic));
        if (remaining == 0) return 0;
        if (remaining >= fade) return 1;
        if (fade <= 0) return 1;
        return @as(f32, @floatFromInt(remaining)) / @as(f32, @floatFromInt(fade));
    }

    fn fireSleep(self: *Engine) void {
        if (self.sleep_fired) return;
        self.sleep_fired = true;
        @atomicStore(u64, &self.sleep_end_ms, 0, .release);
        @atomicStore(bool, &self.playing, false, .release);
        self.pushEvent(EV_SLEEP, 0, 0, 0);
        self.pushEvent(EV_STATE, 0, 0, 0);
    }

    /// Actualiza los niveles con caida exponencial (~200 ms).
    fn applyLevels(self: *Engine, rms: [2]f32, peak: [2]f32, frames: usize) void {
        const n: f32 = @floatFromInt(@max(frames, 1));
        const decay: f32 = @exp(-n / (0.2 * @as(f32, @floatFromInt(SAMPLE_RATE))));
        for (0..2) |ch| {
            const prev_rms: f32 = @bitCast(@atomicLoad(u32, &self.level_rms[ch], .monotonic));
            const prev_peak: f32 = @bitCast(@atomicLoad(u32, &self.level_peak[ch], .monotonic));
            const next_rms = @max(rms[ch], prev_rms * decay);
            const next_peak = @max(peak[ch], prev_peak * decay);
            @atomicStore(u32, &self.level_rms[ch], @bitCast(next_rms), .monotonic);
            @atomicStore(u32, &self.level_peak[ch], @bitCast(next_peak), .monotonic);
        }
    }

    /// Inicio del tramo que contiene `frame` (0 si no hay segmentos).
    fn segmentStartFor(self: *Engine, frame: usize) usize {
        var start: usize = 0;
        self.seg_lock.lock();
        defer self.seg_lock.unlock();
        if (self.findSegment(frame)) |sp| start = self.segments[sp].start;
        return start;
    }

    /// Segundos de fundido de pausa (0 = corte inmediato).
    fn pauseFadeSeconds(self: *const Engine) f32 {
        const seconds: f32 = @bitCast(@atomicLoad(u32, &self.pause_fade_bits, .monotonic));
        return @max(seconds, 0);
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
            self.fade_gain = 0;
        }

        const playing = @atomicLoad(bool, &self.playing, .acquire);
        if (self.sleepGain()) |sg| {
            if (sg <= 0) self.fireSleep();
        }
        if (!playing and self.fade_gain < 0.001) {
            self.fade_gain = 0;
            // El vumetro tiene que bajar a cero, no quedarse congelado.
            self.applyLevels(.{ 0, 0 }, .{ 0, 0 }, frames_out);
            return;
        }

        // Loop A-B: al llegar a B se pide volver a A (mismo camino que un
        // seek normal, asi que respeta crossfade y estiramiento).
        {
            const ab_a = @atomicLoad(usize, &self.ab_start, .acquire);
            const ab_b = @atomicLoad(usize, &self.ab_end, .acquire);
            if (playing and ab_a != NO_SEEK and ab_b != NO_SEEK and ab_b > ab_a) {
                const p = @atomicLoad(usize, &self.played, .acquire);
                if (p >= ab_b) @atomicStore(usize, &self.seek_req, ab_a, .release);
            }
        }

        const r = @atomicLoad(usize, &self.ring.read, .acquire);
        const w = @atomicLoad(usize, &self.ring.write, .acquire);
        var avail = w -% r;
        if (avail > self.ring.cap) avail = 0;
        const take = @min(frames_out, avail);
        if (playing and take < frames_out) {
            _ = @atomicRmw(u64, &self.buf_underflows, .Add, 1, .monotonic);
        }
        if (take > 0) {
            self.readRingAt(r, out[0 .. take * CHANNELS]);
            @atomicStore(usize, &self.ring.read, r +% take, .release);
            {
                // Se cuenta siempre lo consumido, incluido el fundido de pausa:
                // si no, al reanudar el audio va por delante de la posicion
                // mostrada (~50 ms perdidos por cada pausa).
                const sp = self.speedValue();
                var adv: usize = take;
                if (sp != 1) {
                    const f = @as(f64, @floatFromInt(take)) * @as(f64, sp);
                    adv = @intFromFloat(@round(f));
                }
                _ = @atomicRmw(usize, &self.played, .Add, adv, .monotonic);
            }
        }

        const produced = take * CHANNELS;
        self.equalizer.process(out[0..produced], take);

        var target: f32 = 0;
        if (playing) {
            target = self.volume();
            if (@atomicLoad(bool, &self.rg_enabled, .monotonic)) target *= self.audibleGain();
            if (self.sleepGain()) |sg| {
                target *= sg;
                if (sg <= 0) self.fireSleep();
            }
        }
        if (take > 0) {
            var g = self.fade_gain;
            const fade_frames = self.pauseFadeSeconds() * @as(f32, @floatFromInt(SAMPLE_RATE));
            const fade_coeff: f32 = if (fade_frames <= 0)
                1.0
            else
                1.0 - @exp(-1.0 / fade_frames);
            const limiting = self.limit_enabled;
            const ceiling = self.limit_ceiling;
            var lg = self.limit_gain;
            // Ataque rapido, recuperacion lenta (~200 ms).
            const attack: f32 = 0.999;
            const release: f32 = 1.0 - @exp(-1.0 / (0.2 * @as(f32, @floatFromInt(SAMPLE_RATE))));
            const chan_mode = @atomicLoad(u32, &self.chan_mode, .monotonic);
            const balance: f32 = @bitCast(@atomicLoad(u32, &self.balance_bits, .monotonic));
            const gain_l: f32 = 1 - @max(balance, 0);
            const gain_r: f32 = 1 + @min(balance, 0);
            var i: usize = 0;
            while (i < take) : (i += 1) {
                g += (target - g) * fade_coeff;
                var l = out[i * CHANNELS];
                var rr = out[i * CHANNELS + 1];
                if (chan_mode == 1) {
                    // Mono: misma señal en los dos altavoces.
                    const m = (l + rr) * 0.5;
                    l = m;
                    rr = m;
                } else if (chan_mode == 2) {
                    const t = l;
                    l = rr;
                    rr = t;
                }
                var s = l * (g * gain_l);
                var s2 = rr * (g * gain_r);
                if (limiting) {
                    const peak = @max(@abs(s), @abs(s2));
                    var desired = lg;
                    if (peak > ceiling and peak > 0) desired = ceiling / peak;
                    if (desired < lg) {
                        lg = desired; // ataque inmediato
                    } else {
                        lg += (desired - lg) * release;
                    }
                    _ = attack;
                    s *= lg;
                    s2 *= lg;
                }
                out[i * CHANNELS] = s;
                out[i * CHANNELS + 1] = s2;
            }
            self.limit_gain = lg;
            self.fade_gain = if (!playing and g < 0.001) 0 else g;
        }

        {
            var sum_l: f32 = 0;
            var sum_r: f32 = 0;
            var peak_l: f32 = 0;
            var peak_r: f32 = 0;
            var li: usize = 0;
            while (li < take) : (li += 1) {
                const sl = out[li * CHANNELS];
                const sr = out[li * CHANNELS + 1];
                sum_l += sl * sl;
                sum_r += sr * sr;
                peak_l = @max(peak_l, @abs(sl));
                peak_r = @max(peak_r, @abs(sr));
            }
            const inv = 1.0 / @as(f32, @floatFromInt(@max(take, 1)));
            self.applyLevels(
                .{ @sqrt(sum_l * inv), @sqrt(sum_r * inv) },
                .{ peak_l, peak_r },
                frames_out,
            );
        }

        if (take > 0 and self.sp_lock.tryLock()) {
            defer self.sp_lock.unlock();
            var i: usize = 0;
            while (i < take) : (i += 1) {
                const l = out[i * CHANNELS];
                const rr = out[i * CHANNELS + 1];
                self.sp_buf[self.sp_pos] = (l + rr) * 0.5;
                self.sp_pos = (self.sp_pos + 1) % SP_FRAMES;
            }
        }

        if (take == 0) {
            const seeking = @atomicLoad(usize, &self.seek_req, .acquire) != NO_SEEK;
            const skipping = @atomicLoad(usize, &self.skip_req, .acquire) != NO_SEEK;
            if (playing and !seeking and !skipping and @atomicLoad(bool, &self.eof, .acquire)) {
                self.seg_lock.lock();
                const last_end = if (self.seg_count > 0) self.segments[self.seg_count - 1].end else 0;
                self.seg_lock.unlock();
                const p = @atomicLoad(usize, &self.played, .acquire);
                const tol = SAMPLE_RATE / 5;
                if (p + tol >= last_end) {
                    @atomicStore(bool, &self.playing, false, .release);
                    self.pushEvent(EV_END, 0, 0, 0);
                    self.pushEvent(EV_STATE, 0, 0, 0);
                }
            }
        }
    }

    fn spectrum(self: *Engine, out: []f32) void {
        const bands = out.len;
        if (bands == 0) return;
        if (!@atomicLoad(bool, &self.playing, .acquire)) {
            @memset(out, 0);
            return;
        }

        self.sp_lock.lock();
        const pos = self.sp_pos;
        var i: usize = 0;
        while (i < SP_FRAMES) : (i += 1) {
            const idx = (pos + i) % SP_FRAMES;
            const phase = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(SP_FRAMES));
            self.sp_re[i] = self.sp_buf[idx] * (0.5 - 0.5 * @cos(phase));
            self.sp_im[i] = 0;
        }
        self.sp_lock.unlock();

        fft.fft(self.sp_re, self.sp_im);

        const bin_hz = @as(f32, @floatFromInt(SAMPLE_RATE)) / @as(f32, @floatFromInt(SP_FRAMES));
        const max_bin = SP_FRAMES / 2;
        var b: usize = 0;
        while (b < bands) : (b += 1) {
            const t0 = @as(f32, @floatFromInt(b)) / @as(f32, @floatFromInt(bands));
            const t1 = @as(f32, @floatFromInt(b + 1)) / @as(f32, @floatFromInt(bands));
            const f0 = 20.0 * std.math.pow(f32, 1000.0, t0);
            const f1 = 20.0 * std.math.pow(f32, 1000.0, t1);
            var lo: usize = @intFromFloat(@floor(f0 / bin_hz));
            var hi: usize = @intFromFloat(@ceil(f1 / bin_hz));
            if (lo < 1) lo = 1;
            if (hi > max_bin) hi = max_bin;
            if (hi <= lo) hi = lo + 1;

            var sum: f32 = 0;
            var k = lo;
            while (k < hi) : (k += 1) {
                sum += self.sp_re[k] * self.sp_re[k] + self.sp_im[k] * self.sp_im[k];
            }
            const mean = sum / @as(f32, @floatFromInt(hi - lo));
            const db = 10.0 * std.math.log10(mean + 1e-20);
            out[b] = std.math.clamp((db + 80.0) / 80.0, 0.0, 1.0);
        }
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
        const skip = @atomicRmw(usize, &self.skip_req, .Xchg, NO_SEEK, .acq_rel);
        if (skip != NO_SEEK) {
            @atomicStore(bool, &self.idle, false, .release);
            const was_playing = @atomicLoad(bool, &self.playing, .acquire);
            self.flushRing();
            _ = self.beginAt(skip);
            if (was_playing) @atomicStore(bool, &self.playing, true, .release);
            continue;
        }
        if (!@atomicLoad(bool, &self.playing, .acquire)) {
            @atomicStore(bool, &self.idle, true, .release);
            sleepMs(2);
            continue;
        }
        if (self.stretchStale()) {
            self.applyHotStretchChange();
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

        if (self.stretchActive()) {
            const st = &self.stretch.?;

            if (!self.drainStretch(st)) {
                sleepMs(2);
                continue;
            }
            if (st.inFree() < self.scratch_frames or st.outFree() < self.scratch_frames) {
                sleepMs(2);
                continue;
            }

            const got = ch_decode_read(d, self.scratch.ptr, self.scratch_frames);
            if (got == 0) {
                st.flush();
                while (!self.drainStretch(st)) {
                    if (!@atomicLoad(bool, &self.playing, .acquire)) break;
                    sleepMs(2);
                }
                self.resetStretch();
                if (@atomicLoad(bool, &self.gapless, .acquire)) {
                    if (self.openNextAuto()) continue;
                }
                @atomicStore(bool, &self.eof, true, .release);
                continue;
            }
            st.push(self.scratch[0 .. @as(usize, @intCast(got)) * CHANNELS]);
            continue;
        }

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
            if (@atomicLoad(bool, &self.gapless, .acquire)) {
                if (self.crossfadeIntoNext()) continue;
                if (self.openNextAuto()) continue;
            }
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

fn destroyEngine(e: *Engine) void {
    if (e.audio) |audio| ch_audio_destroy(audio);
    if (e.decoder) |d| ch_decode_close(d);
    for (e.segments[0..e.seg_count]) |*s| {
        for (s.covers) |maybe| {
            if (maybe) |c| e.allocator.free(c);
        }
        if (s.lyrics) |ly| ch_lyrics_free(ly);
    }
    for (e.retired_covers.items) |c| e.allocator.free(c);
    e.retired_covers.deinit(e.allocator);
    for (e.playlist.items) |p| e.allocator.free(p);
    e.playlist.deinit(e.allocator);
    e.order.deinit(e.allocator);
    if (e.stretch) |*st| st.deinit();
    e.allocator.free(e.stretch_buf);
    e.allocator.free(e.sp_im);
    e.allocator.free(e.sp_re);
    e.allocator.free(e.sp_buf);
    e.allocator.free(e.scratch);
    e.allocator.free(e.ring.buf);
    e.allocator.destroy(e);
}

export fn ch_core_version() [*c]const u8 {
    return @ptrCast("0.8.0");
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

    self.sp_buf = alloc.alloc(f32, SP_FRAMES) catch {
        setGlobalError("no se pudo reservar el analizador de espectro");
        alloc.free(self.scratch);
        alloc.free(self.ring.buf);
        alloc.destroy(self);
        return null;
    };
    self.sp_re = alloc.alloc(f32, SP_FRAMES) catch {
        setGlobalError("no se pudo reservar el analizador de espectro");
        alloc.free(self.sp_buf);
        alloc.free(self.scratch);
        alloc.free(self.ring.buf);
        alloc.destroy(self);
        return null;
    };
    self.sp_im = alloc.alloc(f32, SP_FRAMES) catch {
        setGlobalError("no se pudo reservar el analizador de espectro");
        alloc.free(self.sp_re);
        alloc.free(self.sp_buf);
        alloc.free(self.scratch);
        alloc.free(self.ring.buf);
        alloc.destroy(self);
        return null;
    };
    @memset(self.sp_buf, 0);
    self.sp_pos = 0;

    self.stretch = Stretch.init(alloc) catch {
        setGlobalError("no se pudo reservar el motor de velocidad/tono");
        alloc.free(self.sp_im);
        alloc.free(self.sp_re);
        alloc.free(self.sp_buf);
        alloc.free(self.scratch);
        alloc.free(self.ring.buf);
        alloc.destroy(self);
        return null;
    };
    self.stretch_buf = alloc.alloc(f32, SCRATCH_FRAMES * CHANNELS) catch {
        setGlobalError("no se pudo reservar el búfer de estiramiento");
        self.stretch.?.deinit();
        alloc.free(self.sp_im);
        alloc.free(self.sp_re);
        alloc.free(self.sp_buf);
        alloc.free(self.scratch);
        alloc.free(self.ring.buf);
        alloc.destroy(self);
        return null;
    };
    self.stretch_buf_frames = SCRATCH_FRAMES;

    @atomicStore(bool, &self.idle, true, .release);

    self.audio = ch_audio_create(&renderAudio, self, SAMPLE_RATE, CHANNELS, self.output_device) orelse {
        copyAudioError();
        if (self.stretch) |*st| st.deinit();
        alloc.free(self.stretch_buf);
        alloc.free(self.sp_im);
        alloc.free(self.sp_re);
        alloc.free(self.sp_buf);
        alloc.free(self.scratch);
        alloc.free(self.ring.buf);
        alloc.destroy(self);
        return null;
    };

    const thread = std.Thread.spawn(.{}, decoderLoop, .{self}) catch {
        setGlobalError("no se pudo iniciar el hilo de audio");
        ch_audio_destroy(self.audio);
        self.audio = null;
        if (self.stretch) |*st| st.deinit();
        alloc.free(self.stretch_buf);
        alloc.free(self.sp_im);
        alloc.free(self.sp_re);
        alloc.free(self.sp_buf);
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
    @atomicStore(usize, &e.skip_req, NO_SEEK, .release);
    if (!e.waitIdle(2000)) return e.fail("el motor de audio no respondió", -3);

    e.flushRing();

    e.list_mutex.lock();
    clearPlaylist(e);
    const added = addPath(e, std.mem.span(p));
    e.list_mutex.unlock();
    if (added == null) return e.fail("sin memoria para la lista de reproducción", -2);

    return e.beginAt(0);
}

/// Reproduce la pista `index` de la cola **sin vaciarla**: la actual se
/// reemplaza por la pedida y el resto de la lista se conserva.
export fn ch_engine_play_index(self: ?*Engine, index: i32) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const count: usize = e.playlist.items.len;
    e.list_mutex.unlock();
    if (index < 0 or index >= @as(i32, @intCast(count))) {
        return e.fail("indice de cola fuera de rango", -1);
    }

    @atomicStore(bool, &e.playing, false, .release);
    @atomicStore(usize, &e.seek_req, NO_SEEK, .release);
    @atomicStore(usize, &e.skip_req, NO_SEEK, .release);
    if (!e.waitIdle(2000)) return e.fail("el motor de audio no respondió", -3);
    e.flushRing();

    const rc = e.beginAt(@intCast(index));
    if (rc != 0) return rc;
    @atomicStore(bool, &e.playing, true, .release);
    e.pushEvent(EV_STATE, 1, 0, 0);
    return 0;
}

/// Añade `path` al final de la cola y la reproduce, conservando lo que ya
/// había (a diferencia de `ch_engine_load`, que deja la cola con una pista).
export fn ch_engine_load_add(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    const p = path orelse return e.fail("ruta nula", -1);
    e.clearError();

    e.list_mutex.lock();
    const added = addPath(e, std.mem.span(p));
    const count: c_int = @intCast(e.playlist.items.len);
    e.list_mutex.unlock();

    const index = added orelse return e.fail("sin memoria para la lista de reproducción", -2);
    e.pushEvent(EV_QUEUE, count, 0, 0);
    return ch_engine_play_index(e, @intCast(index));
}

export fn ch_engine_play(self: ?*Engine) i32 {
    const e = self orelse return -1;
    if (e.decoder == null) return e.fail("no hay pista cargada", -2);

    const played = @atomicLoad(usize, &e.played, .acquire);
    var at_end = false;
    e.seg_lock.lock();
    if (e.seg_count > 0) {
        at_end = played >= e.segments[e.seg_count - 1].end;
    }
    e.seg_lock.unlock();
    if (at_end) {
        @atomicStore(usize, &e.seek_req, 0, .release);
        @atomicStore(bool, &e.eof, false, .release);
    }
    @atomicStore(bool, &e.playing, true, .release);
    e.pushEvent(EV_STATE, 1, 0, 0);
    return 0;
}

export fn ch_engine_pause(self: ?*Engine) i32 {
    const e = self orelse return -1;
    @atomicStore(bool, &e.playing, false, .release);
    e.pushEvent(EV_STATE, 0, 0, 0);
    return 0;
}

fn addPath(self: *Engine, path: []const u8) ?usize {
    const copy = self.allocator.dupeSentinel(u8, path, 0) catch return null;
    self.playlist.append(self.allocator, copy) catch {
        self.allocator.free(copy);
        return null;
    };
    const index = self.playlist.items.len - 1;
    self.noteAddedLocked(index);
    return index;
}

fn clearPlaylist(self: *Engine) void {
    for (self.playlist.items) |p| self.allocator.free(p);
    self.playlist.clearRetainingCapacity();
    self.queue_index = 0;
    self.order.clearRetainingCapacity();
    self.order_pos = 0;
}

export fn ch_engine_queue_add(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    const p = path orelse return -2;
    e.list_mutex.lock();
    const index = addPath(e, std.mem.span(p));
    const count: c_int = @intCast(e.playlist.items.len);
    e.list_mutex.unlock();
    if (index) |i| {
        e.pushEvent(EV_QUEUE, count, 0, 0);
        return @intCast(i);
    }
    return e.fail("sin memoria para la lista de reproducción", -2);
}

export fn ch_engine_queue_count(self: ?*Engine) i32 {
    const e = self orelse return 0;
    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    return @intCast(e.playlist.items.len);
}

export fn ch_engine_queue_import(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    const p = path orelse return e.fail("ruta nula", -1);
    var pl = ch_playlist_read(p);
    if (pl.count < 0) return e.fail("no se pudo leer la lista", -2);
    defer ch_playlist_free(&pl);

    var added: i32 = 0;
    e.list_mutex.lock();
    var i: usize = 0;
    const n: usize = @intCast(pl.count);
    while (i < n) : (i += 1) {
        const item = pl.items[i];
        if (item == null) continue;
        if (addPath(e, std.mem.span(item)) != null) added += 1;
    }
    const count: c_int = @intCast(e.playlist.items.len);
    e.list_mutex.unlock();
    if (added > 0) e.pushEvent(EV_QUEUE, count, 0, 0);
    return added;
}

export fn ch_engine_queue_export(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    const p = path orelse return e.fail("ruta nula", -1);

    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const arr = e.allocator.alloc([*c]const u8, n) catch {
        e.list_mutex.unlock();
        return e.fail("sin memoria para exportar la lista", -2);
    };
    var i: usize = 0;
    while (i < n) : (i += 1) arr[i] = e.playlist.items[i].ptr;
    e.list_mutex.unlock();
    defer e.allocator.free(arr);

    if (ch_playlist_write(p, arr.ptr, @intCast(n)) != 0) {
        return e.fail("no se pudo escribir la lista", -2);
    }
    return 0;
}

export fn ch_engine_queue_index(self: ?*Engine) i32 {
    const e = self orelse return -1;
    if (e.audibleIndex()) |i| return @intCast(i);
    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    return @intCast(e.queue_index);
}

export fn ch_engine_queue_clear(self: ?*Engine) i32 {
    const e = self orelse return -1;
    @atomicStore(bool, &e.playing, false, .release);
    @atomicStore(usize, &e.seek_req, NO_SEEK, .release);
    @atomicStore(usize, &e.skip_req, NO_SEEK, .release);
    _ = e.waitIdle(2000);
    e.flushRing();
    e.list_mutex.lock();
    if (e.decoder) |d| {
        ch_decode_close(d);
        e.decoder = null;
    }
    clearPlaylist(e);
    e.list_mutex.unlock();
    e.resetSegments();
    @atomicStore(usize, &e.played, 0, .release);
    @atomicStore(bool, &e.eof, true, .release);
    e.pushEvent(EV_QUEUE, 0, 0, 0);
    return 0;
}

export fn ch_engine_queue_move(self: ?*Engine, from: i32, to: i32) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    if (from < 0 or to < 0 or from >= @as(i32, @intCast(n)) or to >= @as(i32, @intCast(n))) {
        e.list_mutex.unlock();
        return e.fail("indice de cola fuera de rango", -1);
    }
    if (from == to) {
        e.list_mutex.unlock();
        return 0;
    }
    const f: usize = @intCast(from);
    const t: usize = @intCast(to);
    const item = e.playlist.items[f];
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    if (f < t) {
        var i = f;
        while (i < t) : (i += 1) e.playlist.items[i] = e.playlist.items[i + 1];
    } else {
        var i = t;
        while (i < f) : (i += 1) e.playlist.items[i + 1] = e.playlist.items[i];
    }
    e.playlist.items[t] = item;

    e.remapSegments(f, t, true);
    e.queue_index = moveIndex(f, t, e.queue_index);
    const count: c_int = @intCast(n);
    e.list_mutex.unlock();
    e.pushEvent(EV_QUEUE, count, @intCast(e.queue_index), 0);
    return 0;
}

export fn ch_engine_queue_remove(self: ?*Engine, index: i32) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    if (index < 0 or index >= @as(i32, @intCast(n))) {
        e.list_mutex.unlock();
        return e.fail("indice de cola fuera de rango", -1);
    }
    const i: usize = @intCast(index);
    // La pista que suena puede ir por detras del decodificador (precarga
    // gapless): lo que importa es el indice audible.
    const active = e.audibleIndex() orelse e.queue_index;
    const was_active = i == active;

    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    e.allocator.free(e.playlist.items[i]);
    _ = e.playlist.orderedRemove(i);
    const remaining = e.playlist.items.len;

    if (was_active) {
        if (remaining == 0) {
            e.list_mutex.unlock();
            @atomicStore(bool, &e.playing, false, .release);
            @atomicStore(usize, &e.seek_req, NO_SEEK, .release);
            @atomicStore(usize, &e.skip_req, NO_SEEK, .release);
            _ = e.waitIdle(2000);
            e.flushRing();
            e.list_mutex.lock();
            if (e.decoder) |d| {
                ch_decode_close(d);
                e.decoder = null;
            }
            e.list_mutex.unlock();
            e.resetSegments();
            @atomicStore(usize, &e.played, 0, .release);
            @atomicStore(bool, &e.eof, true, .release);
            e.pushEvent(EV_QUEUE, 0, -1, 0);
            e.pushEvent(EV_STATE, 0, 0, 0);
            return 0;
        }
        const target = @min(i, remaining - 1);
        const was_playing = @atomicLoad(bool, &e.playing, .acquire);
        e.list_mutex.unlock();

        // Cambio sincrono: la cola queda coherente al volver de la llamada.
        @atomicStore(bool, &e.playing, false, .release);
        @atomicStore(usize, &e.seek_req, NO_SEEK, .release);
        _ = e.waitIdle(2000);
        e.flushRing();
        const ok = e.beginAt(target);
        if (ok == 0 and was_playing) {
            @atomicStore(bool, &e.playing, true, .release);
            e.pushEvent(EV_STATE, 1, 0, 0);
        }
        e.pushEvent(EV_QUEUE, @intCast(remaining), @intCast(target), 0);
        return 0;
    }

    if (i < e.queue_index) e.queue_index -= 1;

    // Los segmentos guardan el indice de lista: los posteriores bajan uno.
    e.seg_lock.lock();
    var k: usize = 0;
    while (k < e.seg_count) : (k += 1) {
        if (e.segments[k].index > i) e.segments[k].index -= 1;
    }
    e.seg_lock.unlock();

    const count: c_int = @intCast(remaining);
    const cur: c_int = @intCast(e.queue_index);
    e.list_mutex.unlock();
    e.pushEvent(EV_QUEUE, count, cur, 0);
    return 0;
}

export fn ch_engine_queue_insert(self: ?*Engine, index: i32, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    const p = path orelse return e.fail("ruta nula", -1);
    const copy = e.allocator.dupeSentinel(u8, std.mem.span(p), 0) catch
        return e.fail("sin memoria para la lista", -2);
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    var at: usize = if (index < 0) n else @intCast(@min(index, @as(i32, @intCast(n))));
    if (at > n) at = n;
    e.playlist.insert(e.allocator, at, copy) catch {
        e.allocator.free(copy);
        e.list_mutex.unlock();
        return e.fail("sin memoria para la lista", -2);
    };
    e.remapSegments(at, 0, false);
    if (at <= e.queue_index) e.queue_index += 1;
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    const count: c_int = @intCast(e.playlist.items.len);
    e.list_mutex.unlock();
    e.pushEvent(EV_QUEUE, count, @intCast(e.queue_index), 0);
    return @intCast(at);
}

export fn ch_engine_next(self: ?*Engine) i32 {
    const e = self orelse return -1;
    const audible = e.audibleIndex();
    e.list_mutex.lock();
    const current = audible orelse e.queue_index;
    const target = e.nextAfterLocked(current);
    e.list_mutex.unlock();
    const t = target orelse return e.fail("no hay pista siguiente", -2);
    @atomicStore(usize, &e.skip_req, t, .release);
    @atomicStore(bool, &e.playing, true, .release);
    return 0;
}

export fn ch_engine_previous(self: ?*Engine) i32 {
    const e = self orelse return -1;
    const audible = e.audibleIndex();
    e.list_mutex.lock();
    const current = audible orelse e.queue_index;
    const target = e.prevBeforeLocked(current);
    e.list_mutex.unlock();
    const t = target orelse return e.fail("no hay pista anterior", -2);
    @atomicStore(usize, &e.skip_req, t, .release);
    @atomicStore(bool, &e.playing, true, .release);
    return 0;
}

export fn ch_engine_set_repeat(self: ?*Engine, mode: i32) i32 {
    const e = self orelse return -1;
    if (mode < 0 or mode > 2) return e.fail("modo de repeticion invalido", -1);
    @atomicStore(u32, &e.repeat_mode, @intCast(mode), .monotonic);
    return 0;
}

export fn ch_engine_repeat(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return @intCast(@atomicLoad(u32, &e.repeat_mode, .monotonic));
}

export fn ch_engine_set_shuffle(self: ?*Engine, enabled: i32) i32 {
    const e = self orelse return -1;
    const on = enabled != 0;
    e.list_mutex.lock();
    @atomicStore(bool, &e.shuffle, on, .monotonic);
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    e.list_mutex.unlock();
    return 0;
}

export fn ch_engine_shuffle(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return if (@atomicLoad(bool, &e.shuffle, .monotonic)) 1 else 0;
}

export fn ch_engine_set_shuffle_seed(self: ?*Engine, seed: u32) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    e.rng_state = if (seed == 0) 0x9E3779B9 else seed;
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

export fn ch_engine_set_gapless(self: ?*Engine, enabled: i32) i32 {
    const e = self orelse return -1;
    @atomicStore(bool, &e.gapless, enabled != 0, .release);
    return 0;
}

export fn ch_engine_gapless(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return if (@atomicLoad(bool, &e.gapless, .acquire)) 1 else 0;
}

export fn ch_engine_set_crossfade(self: ?*Engine, seconds: f32) i32 {
    const e = self orelse return -1;
    const secs = std.math.clamp(seconds, 0, 12);
    @atomicStore(u32, &e.xfade_bits, @bitCast(@as(f32, secs)), .monotonic);
    return 0;
}

export fn ch_engine_crossfade(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return @bitCast(@atomicLoad(u32, &e.xfade_bits, .monotonic));
}

export fn ch_engine_set_speed(self: ?*Engine, speed: f32) i32 {
    const e = self orelse return -1;
    if (!(speed > 0)) return -1;
    const s = std.math.clamp(speed, 0.25, 4.0);
    @atomicStore(u32, &e.speed_bits, @bitCast(s), .monotonic);
    return 0;
}

export fn ch_engine_speed(self: ?*Engine) f32 {
    const e = self orelse return 1;
    return e.speedValue();
}

export fn ch_engine_set_pitch(self: ?*Engine, semitones: f32) i32 {
    const e = self orelse return -1;
    const p = std.math.clamp(semitones, -12, 12);
    @atomicStore(u32, &e.pitch_bits, @bitCast(p), .monotonic);
    return 0;
}

export fn ch_engine_pitch(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.pitchValue();
}

export fn ch_engine_spectrum(self: ?*Engine, out: [*c]f32, bands: i32) i32 {
    const e = self orelse return -1;
    if (bands <= 0 or out == null) return -1;
    if (e.sp_buf.len == 0) return -1;
    const n: usize = @intCast(bands);
    e.spectrum(out[0..n]);
    return 0;
}

export fn ch_engine_seek(self: ?*Engine, seconds: f64) i32 {
    const e = self orelse return -1;
    if (e.decoder == null) return e.fail("no hay pista cargada", -2);

    const played = @atomicLoad(usize, &e.played, .acquire);
    var span: usize = 0;
    e.seg_lock.lock();
    if (e.findSegment(played)) |pos| span = e.segments[pos].end - e.segments[pos].start;
    e.seg_lock.unlock();

    const target_f = @max(0, seconds) * SAMPLE_RATE;
    var clamped = target_f;
    if (span > 0) clamped = @min(target_f, @as(f64, @floatFromInt(span)));
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

export fn ch_engine_set_sleep_timer(self: ?*Engine, seconds: f64, fade_seconds: f64) i32 {
    const e = self orelse return -1;
    if (!(seconds > 0)) {
        @atomicStore(u64, &e.sleep_end_ms, 0, .release);
        e.sleep_fired = false;
        return 0;
    }
    const now = monoMs();
    const ms: u64 = @intFromFloat(@min(seconds * 1000.0, 604800000.0));
    @atomicStore(u64, &e.sleep_end_ms, now + ms, .release);
    @atomicStore(u32, &e.sleep_fade_ms, @intFromFloat(std.math.clamp(fade_seconds * 1000.0, 0.0, 60000.0)), .monotonic);
    e.sleep_fired = false;
    return 0;
}

export fn ch_engine_sleep_remaining(self: ?*Engine) f64 {
    const e = self orelse return -1;
    const remaining = e.sleepRemainingMs();
    if (remaining < 0) return -1;
    return @as(f64, @floatFromInt(remaining)) / 1000.0;
}

export fn ch_engine_set_replaygain(self: ?*Engine, enabled: i32) i32 {
    const e = self orelse return -1;
    @atomicStore(bool, &e.rg_enabled, enabled != 0, .monotonic);
    return 0;
}

/// Limitador de picos en caliente: evita el recorte cuando la señal supera
/// `ceiling` (dBFS). Ataque inmediato y recuperación suave (~200 ms).
export fn ch_engine_set_limiter(self: ?*Engine, enabled: i32, ceiling_db: f32) i32 {
    const e = self orelse return -1;
    const ceiling: f32 = std.math.pow(f32, 10, ceiling_db / 20);
    e.limit_ceiling = std.math.clamp(ceiling, 0.01, 1.0);
    e.limit_enabled = enabled != 0;
    if (!e.limit_enabled) e.limit_gain = 1.0;
    return 0;
}

export fn ch_engine_limiter(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return if (e.limit_enabled) 1 else 0;
}

export fn ch_engine_replaygain_gain_db(self: ?*Engine) f32 {
    const e = self orelse return 0;
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    const p = @atomicLoad(usize, &e.played, .acquire);
    if (e.findSegment(p)) |pos| return e.segments[pos].rg_gain_db;
    return 0;
}

export fn ch_engine_replaygain_peak(self: ?*Engine) f32 {
    const e = self orelse return 0;
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    const p = @atomicLoad(usize, &e.played, .acquire);
    if (e.findSegment(p)) |pos| return e.segments[pos].rg_peak;
    return 0;
}

export fn ch_engine_output_device_count() i32 {
    return ch_audio_device_count();
}

export fn ch_engine_output_device_name(index: i32) [*c]const u8 {
    return ch_audio_device_name(index);
}

export fn ch_engine_output_device(self: ?*Engine) i32 {
    const e = self orelse return -1;
    return e.output_device;
}

export fn ch_engine_set_output_device(self: ?*Engine, index: i32) i32 {
    const e = self orelse return -1;
    const count = ch_audio_device_count();
    if (index < -1 or index >= count) return e.fail("dispositivo de audio inválido", -2);
    if (index == e.output_device) return 0;

    const was_playing = @atomicLoad(bool, &e.playing, .acquire);
    @atomicStore(bool, &e.playing, false, .release);
    if (!e.waitIdle(2000)) return e.fail("el motor de audio no respondió", -3);

    if (e.audio) |audio| {
        ch_audio_destroy(audio);
        e.audio = null;
    }
    e.output_device = index;
    e.audio = ch_audio_create(&renderAudio, e, SAMPLE_RATE, CHANNELS, index) orelse {
        copyAudioError();
        e.output_device = -1;
        e.audio = ch_audio_create(&renderAudio, e, SAMPLE_RATE, CHANNELS, -1) orelse {
            copyAudioError();
            return -2;
        };
        if (ch_audio_start(e.audio) != 0) {
            copyAudioError();
            return -3;
        }
        return -2;
    };
    if (ch_audio_start(e.audio) != 0) {
        copyAudioError();
        return -3;
    }
    if (was_playing) @atomicStore(bool, &e.playing, true, .release);
    return 0;
}

export fn ch_engine_eq_band_count() i32 {
    return eq.BAND_COUNT;
}

export fn ch_engine_eq_band_freq(index: i32) f32 {
    if (index < 0 or index >= eq.BAND_COUNT) return 0;
    return eq.FREQS[@intCast(index)];
}

export fn ch_engine_set_eq_gains(self: ?*Engine, gains_db: [*c]const f32, count: i32) i32 {
    const e = self orelse return -1;
    if (gains_db == null or count <= 0) return e.fail("bandas de EQ inválidas", -2);
    const n: usize = @min(@as(usize, @intCast(count)), eq.BAND_COUNT);
    var gains: [eq.BAND_COUNT]f32 = @splat(0);
    for (0..n) |i| {
        gains[i] = std.math.clamp(gains_db[i], -eq.MAX_GAIN_DB, eq.MAX_GAIN_DB);
    }
    e.eq_gains = gains;
    e.equalizer.setGains(&gains);
    return 0;
}

export fn ch_engine_set_band_gain(self: ?*Engine, band: i32, db: f32) i32 {
    const e = self orelse return -1;
    if (band < 0 or band >= eq.BAND_COUNT) return e.fail("banda de EQ fuera de rango", -2);
    e.eq_gains[@intCast(band)] = std.math.clamp(db, -eq.MAX_GAIN_DB, eq.MAX_GAIN_DB);
    e.equalizer.setGains(&e.eq_gains);
    return 0;
}

/// Version del ABI del nucleo: sube cuando cambia algo incompatible.
export fn ch_engine_abi_version() i32 {
    return ABI_VERSION;
}

/// Balance estereo: -1 todo a la izquierda, 0 centrado, +1 a la derecha.
export fn ch_engine_set_balance(self: ?*Engine, balance: f32) i32 {
    const e = self orelse return -1;
    @atomicStore(u32, &e.balance_bits, @bitCast(std.math.clamp(balance, -1, 1)), .monotonic);
    return 0;
}

export fn ch_engine_balance(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return @bitCast(@atomicLoad(u32, &e.balance_bits, .monotonic));
}

/// 0 = estereo normal, 1 = mono (suma a los dos canales), 2 = intercambiados.
export fn ch_engine_set_channel_mode(self: ?*Engine, mode: i32) i32 {
    const e = self orelse return -1;
    if (mode < 0 or mode > 2) return e.fail("modo de canales inválido", -2);
    @atomicStore(u32, &e.chan_mode, @intCast(mode), .monotonic);
    return 0;
}

export fn ch_engine_channel_mode(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return @intCast(@atomicLoad(u32, &e.chan_mode, .monotonic));
}

/// Loop A-B de la pista actual, en segundos. `end <= start` lo desactiva.
export fn ch_engine_set_loop(self: ?*Engine, start_s: f64, end_s: f64) i32 {
    const e = self orelse return -1;
    if (!(end_s > start_s) or start_s < 0) {
        @atomicStore(usize, &e.ab_start, NO_SEEK, .release);
        @atomicStore(usize, &e.ab_end, NO_SEEK, .release);
        return 0;
    }
    const frames = @as(f64, @floatFromInt(SAMPLE_RATE));
    const base = e.segmentStartFor(@atomicLoad(usize, &e.played, .acquire));
    const a = base + @as(usize, @intFromFloat(start_s * frames));
    const b = base + @as(usize, @intFromFloat(end_s * frames));
    @atomicStore(usize, &e.ab_start, a, .release);
    @atomicStore(usize, &e.ab_end, b, .release);
    return 0;
}

/// Principio del loop en segundos desde el inicio de la pista (-1 si no hay).
export fn ch_engine_loop_start(self: ?*Engine) f64 {
    const e = self orelse return -1;
    const a = @atomicLoad(usize, &e.ab_start, .acquire);
    if (a == NO_SEEK) return -1;
    const base = e.segmentStartFor(@atomicLoad(usize, &e.played, .acquire));
    if (a < base) return -1;
    return @as(f64, @floatFromInt(a - base)) / @as(f64, @floatFromInt(SAMPLE_RATE));
}

/// Final del loop en segundos desde el inicio de la pista (-1 si no hay).
export fn ch_engine_loop_end(self: ?*Engine) f64 {
    const e = self orelse return -1;
    const b = @atomicLoad(usize, &e.ab_end, .acquire);
    if (b == NO_SEEK) return -1;
    const base = e.segmentStartFor(@atomicLoad(usize, &e.played, .acquire));
    if (b < base) return -1;
    return @as(f64, @floatFromInt(b - base)) / @as(f64, @floatFromInt(SAMPLE_RATE));
}

/// Cuantas pistas se saltaron por no poder abrirlas.
export fn ch_engine_skipped_tracks(self: ?*Engine) u64 {
    const e = self orelse return 0;
    return @atomicLoad(u64, &e.skipped_tracks, .monotonic);
}

/// Preamp del EQ en dB (0 a -24). Baja la señal antes del banco de filtros.
export fn ch_engine_set_eq_preamp(self: ?*Engine, db: f32) i32 {
    const e = self orelse return -1;
    e.equalizer.setPreamp(db);
    return 0;
}

export fn ch_engine_eq_preamp(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.equalizer.preamp_db;
}

/// 1 = ReplayGain por album, 0 = por pista. Afecta a las pistas que se abran
/// despues (las ya cargadas conservan su ganancia).
export fn ch_engine_set_replaygain_mode(self: ?*Engine, mode: i32) i32 {
    const e = self orelse return -1;
    if (mode != 0 and mode != 1) return e.fail("modo de ReplayGain inválido", -2);
    @atomicStore(u32, &e.rg_mode, @intCast(mode), .release);
    return 0;
}

export fn ch_engine_replaygain_mode(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return @intCast(@atomicLoad(u32, &e.rg_mode, .acquire));
}

export fn ch_engine_position(self: ?*Engine) f64 {
    const e = self orelse return 0;
    const p = @atomicLoad(usize, &e.played, .acquire);
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    if (e.findSegment(p)) |pos| {
        const s = &e.segments[pos];
        if (p >= s.start and p <= s.end) {
            return @as(f64, @floatFromInt(p - s.start)) / SAMPLE_RATE;
        }
        if (p > s.end) {
            return @as(f64, @floatFromInt(s.end - s.start)) / SAMPLE_RATE;
        }
    }
    return 0;
}

export fn ch_engine_duration(self: ?*Engine) f64 {
    const e = self orelse return 0;
    const p = @atomicLoad(usize, &e.played, .acquire);
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    if (e.findSegment(p)) |pos| {
        const s = &e.segments[pos];
        return @as(f64, @floatFromInt(s.end - s.start)) / SAMPLE_RATE;
    }
    return 0;
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
    e.copyMetaField(&tls_title, "title");
    return @ptrCast(&tls_title);
}

export fn ch_engine_artist(self: ?*Engine) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    e.copyMetaField(&tls_artist, "artist");
    return @ptrCast(&tls_artist);
}

export fn ch_engine_album(self: ?*Engine) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    e.copyMetaField(&tls_album, "album");
    return @ptrCast(&tls_album);
}

/// Etiqueta arbitraria del decodificador actual ("" si no existe).
export fn ch_engine_tag(self: ?*Engine, key: [*c]const u8) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (key == null) return @ptrCast("");
    const d = e.decoder orelse return @ptrCast("");
    return ch_decode_tag(d, key);
}

export fn ch_engine_date(self: ?*Engine) [*c]const u8 {
    return ch_engine_tag(self, "date");
}

export fn ch_engine_genre(self: ?*Engine) [*c]const u8 {
    return ch_engine_tag(self, "genre");
}

export fn ch_engine_composer(self: ?*Engine) [*c]const u8 {
    return ch_engine_tag(self, "composer");
}

export fn ch_engine_track_number(self: ?*Engine) i32 {
    const e = self orelse return 0;
    const raw = std.mem.span(ch_engine_tag(e, "track"));
    const slash = std.mem.indexOfScalar(u8, raw, '/');
    const head = if (slash) |s| raw[0..s] else raw;
    return std.fmt.parseInt(i32, std.mem.trim(u8, head, " \t"), 10) catch 0;
}

export fn ch_engine_disc_number(self: ?*Engine) i32 {
    const e = self orelse return 0;
    const raw = std.mem.span(ch_engine_tag(e, "disc"));
    const slash = std.mem.indexOfScalar(u8, raw, '/');
    const head = if (slash) |s| raw[0..s] else raw;
    return std.fmt.parseInt(i32, std.mem.trim(u8, head, " \t"), 10) catch 0;
}

export fn ch_engine_lyrics_count(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return @intCast(ch_lyrics_count(e.audibleLyrics()));
}

/// Texto de la linea activa en la posicion actual, o "" si no hay letra.
export fn ch_engine_lyric_line(self: ?*Engine, out: [*c]u8, out_size: u32) i32 {
    const e = self orelse return -1;
    if (out == null or out_size == 0) return -1;
    const lyrics = e.audibleLyrics() orelse {
        out[0] = 0;
        return 0;
    };
    const pos = @as(f64, @floatFromInt(@atomicLoad(usize, &e.played, .acquire))) /
        @as(f64, @floatFromInt(SAMPLE_RATE));
    const adjusted = pos - e.audibleLyricsOffset() / 1000.0;
    const line = ch_lyrics_line_at(lyrics, adjusted, null, null);
    const dst = out[0..@as(usize, out_size)];
    if (line == null) {
        dst[0] = 0;
        return 0;
    }
    const src = std.mem.span(line);
    const n = @min(src.len, dst.len - 1);
    @memcpy(dst[0..n], src[0..n]);
    dst[n] = 0;
    return @intCast(n);
}

export fn ch_engine_cover(self: ?*Engine, size: ?*u64) [*c]const u8 {
    return ch_engine_cover_at(self, 0, size);
}

export fn ch_engine_cover_count(self: ?*Engine) i32 {
    const e = self orelse return 0;
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    const p = @atomicLoad(usize, &e.played, .acquire);
    if (e.findSegment(p)) |pos| return @intCast(e.segments[pos].cover_count);
    return 0;
}

export fn ch_engine_cover_at(self: ?*Engine, index: i32, size: ?*u64) [*c]const u8 {
    const e = self orelse {
        if (size) |s| s.* = 0;
        return null;
    };
    if (index < 0) {
        if (size) |s| s.* = 0;
        return null;
    }
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    const p = @atomicLoad(usize, &e.played, .acquire);
    if (e.findSegment(p)) |pos| {
        const seg = &e.segments[pos];
        const i: usize = @intCast(index);
        if (i < seg.cover_count) {
            if (seg.covers[i]) |cover| {
                if (size) |s| s.* = @intCast(cover.len);
                return @ptrCast(cover.ptr);
            }
        }
    }
    if (size) |s| s.* = 0;
    return null;
}

export fn ch_engine_last_error(self: ?*Engine) [*c]const u8 {
    const e = self orelse return @ptrCast(&global_error);
    return @ptrCast(&e.err);
}

/// Segundos de audio pendientes en el búfer (0..4).
export fn ch_engine_buffered_seconds(self: ?*Engine) f64 {
    const e = self orelse return 0;
    const r = @atomicLoad(usize, &e.ring.read, .acquire);
    const w = @atomicLoad(usize, &e.ring.write, .acquire);
    var avail = w -% r;
    if (avail > e.ring.cap) avail = 0;
    return @as(f64, @floatFromInt(avail)) / @as(f64, @floatFromInt(SAMPLE_RATE));
}

/// Niveles de salida para vumetros: escribe rms_l, rms_r, peak_l, peak_r
/// (0..1, con caida ~200 ms). Devuelve cuantos valores escribio.
export fn ch_engine_levels(self: ?*Engine, out: [*c]f32, count: i32) i32 {
    const e = self orelse return -1;
    if (out == null or count <= 0) return -1;
    const values = [4]f32{
        @bitCast(@atomicLoad(u32, &e.level_rms[0], .monotonic)),
        @bitCast(@atomicLoad(u32, &e.level_rms[1], .monotonic)),
        @bitCast(@atomicLoad(u32, &e.level_peak[0], .monotonic)),
        @bitCast(@atomicLoad(u32, &e.level_peak[1], .monotonic)),
    };
    const n: usize = @min(@as(usize, @intCast(count)), values.len);
    for (0..n) |i| out[i] = values[i];
    return @intCast(n);
}

/// Fundido al pausar, en segundos (0 = corte inmediato).
export fn ch_engine_set_pause_fade(self: ?*Engine, seconds: f32) i32 {
    const e = self orelse return -1;
    @atomicStore(u32, &e.pause_fade_bits, @bitCast(std.math.clamp(seconds, 0, 2)), .monotonic);
    return 0;
}

export fn ch_engine_pause_fade(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.pauseFadeSeconds();
}

/// Nº de veces que el hilo de audio se quedo sin datos (underrun).
export fn ch_engine_buffer_underflows(self: ?*Engine) u64 {
    const e = self orelse return 0;
    return @atomicLoad(u64, &e.buf_underflows, .monotonic);
}

// ---- Biblioteca de audio (escaneo incremental de carpetas) ----

export fn ch_library_create() ?*ch_library {
    return c_lib_create();
}

export fn ch_library_destroy(lib: ?*ch_library) void {
    c_lib_destroy(lib);
}

export fn ch_library_scan(lib: ?*ch_library, root: [*c]const u8) i32 {
    if (root == null) return -1;
    return @intCast(c_lib_scan(lib, root, null, 0));
}

export fn ch_library_count(lib: ?*const ch_library) i32 {
    return @intCast(c_lib_count(lib));
}

export fn ch_library_path(lib: ?*const ch_library, index: i32) [*c]const u8 {
    if (index < 0) return @ptrCast("");
    const p = c_lib_path(lib, index);
    return if (p == null) @ptrCast("") else p;
}

export fn ch_library_removed(lib: ?*const ch_library) i32 {
    return @intCast(c_lib_removed(lib));
}

/// Analiza `path` y devuelve en `lead`/`tail` los segundos de silencio al
/// principio y al final (por debajo de `threshold_db` dBFS). Devuelve 0 si ok.
export fn ch_engine_detect_silence(path: [*c]const u8, threshold_db: f32, lead: *f64, tail: *f64) i32 {
    if (path == null) return -1;
    const d = ch_decode_open(path, SAMPLE_RATE, CHANNELS) orelse return -2;
    defer ch_decode_close(d);

    const total = ch_decode_duration(d);
    const thr: f32 = std.math.pow(f32, 10, threshold_db / 20);

    const chunk_frames: usize = 4096;
    const buf = std.heap.c_allocator.alloc(f32, chunk_frames * CHANNELS) catch return -3;
    defer std.heap.c_allocator.free(buf);

    var pos_frames: u64 = 0;
    var first_loud: ?u64 = null;
    var last_loud: u64 = 0;

    while (true) {
        const got = ch_decode_read(d, buf.ptr, chunk_frames);
        if (got == 0) break;
        const n: usize = @intCast(got);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const l = buf[i * CHANNELS];
            const r = buf[i * CHANNELS + 1];
            const peak = @max(@abs(l), @abs(r));
            if (peak >= thr) {
                if (first_loud == null) first_loud = pos_frames + i;
                last_loud = pos_frames + i;
            }
        }
        pos_frames += got;
    }

    const rate: f64 = @floatFromInt(SAMPLE_RATE);
    if (first_loud) |fl| {
        lead.* = @as(f64, @floatFromInt(fl)) / rate;
        const total_frames = pos_frames;
        const tail_start = @min(last_loud + 1, total_frames);
        tail.* = @as(f64, @floatFromInt(total_frames - tail_start)) / rate;
    } else {
        // Silencio total: se reporta todo como silencio.
        lead.* = if (total > 0) total else 0;
        tail.* = 0;
    }
    return 0;
}

export fn ch_engine_poll_event(self: ?*Engine, out: ?*ChEvent) i32 {
    const e = self orelse return -1;
    const ev = out orelse return -1;
    e.ev_lock.lock();
    defer e.ev_lock.unlock();
    if (e.ev_tail == e.ev_head) return 0;
    ev.* = e.ev_buf[e.ev_tail];
    e.ev_tail = (e.ev_tail + 1) % e.ev_buf.len;
    return 1;
}

test "eq: frecuencias de banda" {
    try std.testing.expectEqual(@as(i32, 36), ch_engine_eq_band_count());
    try std.testing.expectEqual(@as(f32, 20.0), ch_engine_eq_band_freq(0));
    try std.testing.expectEqual(@as(f32, 20000.0), ch_engine_eq_band_freq(35));
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_eq_band_freq(-1));
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_eq_band_freq(36));
}

test "api: los punteros nulos devuelven error, no revientan" {
    try std.testing.expectEqual(@as(i32, -1), ch_engine_play(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_play_index(null, 0));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_load_add(null, null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_band_gain(null, 0, 3));
    try std.testing.expectEqual(@as(f64, 0.0), ch_engine_position(null));
    try std.testing.expectEqual(@as(u64, 0), ch_engine_buffer_underflows(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_levels(null, null, 4));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_pause_fade(null, 0.1));
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_pause_fade(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_eq_preamp(null, -3));
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_eq_preamp(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_replaygain_mode(null, 1));
    try std.testing.expectEqual(@as(i32, 0), ch_engine_replaygain_mode(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_loop(null, 0, 10));
    try std.testing.expectEqual(@as(f64, -1.0), ch_engine_loop_start(null));
    try std.testing.expectEqual(@as(f64, -1.0), ch_engine_loop_end(null));
    try std.testing.expectEqual(@as(u64, 0), ch_engine_skipped_tracks(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_balance(null, 0.5));
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_balance(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_channel_mode(null, 1));
    try std.testing.expectEqual(@as(i32, 0), ch_engine_channel_mode(null));
    try std.testing.expectEqual(ABI_VERSION, ch_engine_abi_version());
}

test "moveIndex reordena sin perder pistas" {
    // 0..4, mover 0 a 3 -> [1, 2, 3, 0, 4]
    try std.testing.expectEqual(@as(usize, 3), moveIndex(0, 3, 0));
    try std.testing.expectEqual(@as(usize, 0), moveIndex(0, 3, 1));
    try std.testing.expectEqual(@as(usize, 1), moveIndex(0, 3, 2));
    try std.testing.expectEqual(@as(usize, 2), moveIndex(0, 3, 3));
    try std.testing.expectEqual(@as(usize, 4), moveIndex(0, 3, 4));
    // mover 3 a 1 -> [0, 3, 1, 2, 4]
    try std.testing.expectEqual(@as(usize, 0), moveIndex(3, 1, 0));
    try std.testing.expectEqual(@as(usize, 2), moveIndex(3, 1, 1));
    try std.testing.expectEqual(@as(usize, 3), moveIndex(3, 1, 2));
    try std.testing.expectEqual(@as(usize, 1), moveIndex(3, 1, 3));
    try std.testing.expectEqual(@as(usize, 4), moveIndex(3, 1, 4));
}

test "parseLeadingFloat lee las etiquetas de ReplayGain" {
    try std.testing.expectEqual(@as(f32, -7.5), parseLeadingFloat("-7.50 dB").?);
    try std.testing.expectEqual(@as(f32, 1.2), parseLeadingFloat("+1.2").?);
    try std.testing.expectEqual(@as(f32, 0.95), parseLeadingFloat("0.950").?);
    try std.testing.expect(parseLeadingFloat("sin numeros") == null);
    try std.testing.expect(parseLeadingFloat("") == null);
}

test "lrcPathFor cambia la extension, no las carpetas" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const uno = try lrcPathFor(a, "/musica/tema.flac");
    try std.testing.expectEqualStrings("/musica/tema.lrc", uno);

    const dos = try lrcPathFor(a, "/musica/carpeta.con.puntos/tema");
    try std.testing.expectEqualStrings("/musica/carpeta.con.puntos/tema.lrc", dos);
}
