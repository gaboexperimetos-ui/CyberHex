const std = @import("std");
const eq = @import("eq.zig");

pub const SAMPLE_RATE: u32 = 48000;
pub const CHANNELS: u32 = 2;

const Allocator = std.mem.Allocator;
const RenderFn = *const fn (?*anyopaque, [*]f32, u32) callconv(.c) void;

const RING_FRAMES: usize = SAMPLE_RATE * 4; // 4 segundos de margen
const SCRATCH_FRAMES: usize = 4096;
const NO_SEEK: usize = std.math.maxInt(usize);
const MAX_SEGMENTS: usize = 256;
const MAX_XFADE_FRAMES: usize = SAMPLE_RATE * 12;

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
    cover: ?[]u8 = null,
};

threadlocal var tls_title: [256]u8 = undefined;
threadlocal var tls_artist: [256]u8 = undefined;
threadlocal var tls_album: [256]u8 = undefined;

pub const Engine = struct {
    allocator: Allocator,
    audio: ?*anyopaque = null,
    output_device: i32 = -1,
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
    seek_req: usize = NO_SEEK,
    skip_req: usize = NO_SEEK,
    volume_bits: u32 = @bitCast(@as(f32, 1)),
    rg_enabled: bool = true,
    equalizer: eq.Equalizer = .{},

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
    retired_covers: std.ArrayListUnmanaged([]u8) = .empty,

    err: [256]u8 = @splat(0),

    fn setError(self: *Engine, msg: []const u8) void {
        const n = @min(msg.len, self.err.len - 1);
        @memcpy(self.err[0..n], msg[0..n]);
        self.err[n] = 0;
    }

    fn clearError(self: *Engine) void {
        self.err[0] = 0;
    }

    fn fail(self: *Engine, msg: []const u8, code: i32) i32 {
        self.setError(msg);
        return code;
    }

    fn volume(self: *const Engine) f32 {
        return @bitCast(@atomicLoad(u32, &self.volume_bits, .monotonic));
    }

    fn findSegment(self: *Engine, frame: usize) ?usize {
        var i = self.seg_count;
        while (i > 0) {
            i -= 1;
            if (frame >= self.segments[i].start) return i;
        }
        return if (self.seg_count > 0) 0 else null;
    }

    fn trimAfter(self: *Engine, pos: usize) void {
        if (pos + 1 >= self.seg_count) return;
        for (self.segments[pos + 1 .. self.seg_count]) |*s| {
            if (s.cover) |c| self.retired_covers.append(self.allocator, c) catch self.allocator.free(c);
            s.* = .{};
        }
        self.seg_count = pos + 1;
    }

    fn resetSegments(self: *Engine) void {
        self.seg_lock.lock();
        for (self.segments[0..self.seg_count]) |*s| {
            if (s.cover) |c| self.retired_covers.append(self.allocator, c) catch self.allocator.free(c);
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

    fn addSegment(self: *Engine, index: usize, d: *ch_decoder, overlap: usize) bool {
        if (self.seg_count >= MAX_SEGMENTS) return false;

        var seg = Segment{};
        seg.index = index;

        const seconds = ch_decode_duration(d);
        const frames_f: f64 = if (seconds > 0) seconds * SAMPLE_RATE else 0;
        var frames: usize = if (frames_f > 0) @intFromFloat(frames_f) else 0;
        if (frames == 0) frames = SAMPLE_RATE;

        copyCString(&seg.title, ch_decode_title(d));
        copyCString(&seg.artist, ch_decode_artist(d));
        copyCString(&seg.album, ch_decode_album(d));

        const db = parseLeadingFloat(std.mem.span(ch_decode_tag(d, "REPLAYGAIN_TRACK_GAIN"))) orelse 0;
        seg.rg_gain_db = db;
        var linear = std.math.pow(f32, 10, db / 20);
        const peak = parseLeadingFloat(std.mem.span(ch_decode_tag(d, "REPLAYGAIN_TRACK_PEAK"))) orelse 0;
        seg.rg_peak = @max(peak, 0);
        if (seg.rg_peak > 0 and linear * seg.rg_peak > 1) linear = 1 / seg.rg_peak;
        seg.rg_gain = linear;

        var size: u64 = 0;
        const ptr = ch_decode_cover(d, &size);
        if (ptr != null and size > 0) {
            const n: usize = @intCast(size);
            if (self.allocator.alloc(u8, n)) |copy| {
                @memcpy(copy, ptr[0..n]);
                seg.cover = copy;
            } else |_| {}
        }

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

    fn audibleIndex(self: *Engine) ?usize {
        self.seg_lock.lock();
        defer self.seg_lock.unlock();
        const p = @atomicLoad(usize, &self.played, .acquire);
        if (self.findSegment(p)) |pos| return self.segments[pos].index;
        return null;
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
        self.list_mutex.unlock();

        if (old) |o| ch_decode_close(o);
        return true;
    }

    fn beginAt(self: *Engine, index: usize) i32 {
        self.resetSegments();
        if (!self.openDecoderOnly(index)) {
            const msg = std.mem.span(ch_decode_last_error());
            return self.fail(if (msg.len == 0) "no se pudo decodificar el archivo" else msg, -2);
        }
        const d = self.decoder.?;
        _ = self.addSegment(index, d, 0);
        @atomicStore(usize, &self.played, 0, .release);
        @atomicStore(bool, &self.eof, false, .release);
        return 0;
    }

    fn openNextAuto(self: *Engine) bool {
        self.list_mutex.lock();
        const next = self.queue_index + 1;
        if (next >= self.playlist.items.len) {
            self.list_mutex.unlock();
            return false;
        }
        const path = self.playlist.items[next];
        const d = ch_decode_open(path.ptr, SAMPLE_RATE, CHANNELS) orelse {
            self.list_mutex.unlock();
            return false;
        };
        const old = self.decoder;
        self.decoder = d;
        self.queue_index = next;
        self.list_mutex.unlock();

        if (old) |o| ch_decode_close(o);
        _ = self.addSegment(next, d, 0);
        @atomicStore(bool, &self.eof, false, .release);
        @atomicStore(bool, &self.playing, true, .release);
        return true;
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
        const next = self.queue_index + 1;
        if (next >= self.playlist.items.len) {
            self.list_mutex.unlock();
            return false;
        }
        const path = self.playlist.items[next];
        const d = ch_decode_open(path.ptr, SAMPLE_RATE, CHANNELS) orelse {
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

        if (!@atomicLoad(bool, &self.playing, .acquire)) return;

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

        var gain = self.volume();
        if (@atomicLoad(bool, &self.rg_enabled, .monotonic)) gain *= self.audibleGain();
        if (gain != 1) {
            for (out[0..produced]) |*s| s.* *= gain;
        }

        if (take == 0) {
            const seeking = @atomicLoad(usize, &self.seek_req, .acquire) != NO_SEEK;
            if (!seeking and @atomicLoad(bool, &self.eof, .acquire)) {
                self.seg_lock.lock();
                const last_end = if (self.seg_count > 0) self.segments[self.seg_count - 1].end else 0;
                self.seg_lock.unlock();
                if (@atomicLoad(usize, &self.played, .acquire) >= last_end) {
                    @atomicStore(bool, &self.playing, false, .release);
                }
            }
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
        if (s.cover) |c| e.allocator.free(c);
    }
    for (e.retired_covers.items) |c| e.allocator.free(c);
    e.retired_covers.deinit(e.allocator);
    for (e.playlist.items) |p| e.allocator.free(p);
    e.playlist.deinit(e.allocator);
    e.allocator.free(e.scratch);
    e.allocator.free(e.ring.buf);
    e.allocator.destroy(e);
}

export fn ch_core_version() [*c]const u8 {
    return @ptrCast("0.3.0");
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

    self.audio = ch_audio_create(&renderAudio, self, SAMPLE_RATE, CHANNELS, self.output_device) orelse {
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
    return 0;
}

export fn ch_engine_pause(self: ?*Engine) i32 {
    const e = self orelse return -1;
    @atomicStore(bool, &e.playing, false, .release);
    return 0;
}

fn addPath(self: *Engine, path: []const u8) ?usize {
    const copy = self.allocator.dupeSentinel(u8, path, 0) catch return null;
    self.playlist.append(self.allocator, copy) catch {
        self.allocator.free(copy);
        return null;
    };
    return self.playlist.items.len - 1;
}

fn clearPlaylist(self: *Engine) void {
    for (self.playlist.items) |p| self.allocator.free(p);
    self.playlist.clearRetainingCapacity();
    self.queue_index = 0;
}

export fn ch_engine_queue_add(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    const p = path orelse return -2;
    e.list_mutex.lock();
    const index = addPath(e, std.mem.span(p));
    e.list_mutex.unlock();
    if (index) |i| return @intCast(i);
    return e.fail("sin memoria para la lista de reproducción", -2);
}

export fn ch_engine_queue_count(self: ?*Engine) i32 {
    const e = self orelse return 0;
    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    return @intCast(e.playlist.items.len);
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
    return 0;
}

export fn ch_engine_next(self: ?*Engine) i32 {
    const e = self orelse return -1;
    const current = e.audibleIndex() orelse e.queue_index;
    const target = current + 1;
    e.list_mutex.lock();
    const ok = target < e.playlist.items.len;
    e.list_mutex.unlock();
    if (!ok) return e.fail("no hay pista siguiente", -2);
    @atomicStore(usize, &e.skip_req, target, .release);
    @atomicStore(bool, &e.playing, true, .release);
    return 0;
}

export fn ch_engine_previous(self: ?*Engine) i32 {
    const e = self orelse return -1;
    const current = e.audibleIndex() orelse e.queue_index;
    if (current == 0) return e.fail("no hay pista anterior", -2);
    @atomicStore(usize, &e.skip_req, current - 1, .release);
    @atomicStore(bool, &e.playing, true, .release);
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

export fn ch_engine_set_replaygain(self: ?*Engine, enabled: i32) i32 {
    const e = self orelse return -1;
    @atomicStore(bool, &e.rg_enabled, enabled != 0, .monotonic);
    return 0;
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
    gains[@intCast(band)] = db;
    e.equalizer.setGains(&gains);
    return 0;
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

export fn ch_engine_cover(self: ?*Engine, size: ?*u64) [*c]const u8 {
    const e = self orelse {
        if (size) |s| s.* = 0;
        return null;
    };
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    const p = @atomicLoad(usize, &e.played, .acquire);
    if (e.findSegment(p)) |pos| {
        if (e.segments[pos].cover) |cover| {
            if (size) |s| s.* = @intCast(cover.len);
            return @ptrCast(cover.ptr);
        }
    }
    if (size) |s| s.* = 0;
    return null;
}

export fn ch_engine_last_error(self: ?*Engine) [*c]const u8 {
    const e = self orelse return @ptrCast(&global_error);
    return @ptrCast(&e.err);
}
