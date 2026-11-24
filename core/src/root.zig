const std = @import("std");
const eq = @import("eq.zig");
const dsp = @import("dsp_spatial.zig");
const ambient = @import("dsp_ambient.zig");
const bpm_mod = @import("bpm.zig");
const fft = @import("fft.zig");
const Stretch = @import("stretch.zig").Stretch;
const png = @import("png.zig");
const Canvas = png.Canvas;

pub const SAMPLE_RATE: u32 = 48000;
const SAMPLE_RATE_F: f32 = 48000.0;
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
extern fn ch_audio_set_s16(audio: ?*anyopaque, enabled: i32) i32;
extern fn ch_audio_quantize_s16(sample: f32, state: ?*u32) i16;

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
extern fn ch_lyrics_shift(lyrics: ?*ch_lyrics, delta_s: f64) c_int;
extern fn ch_lyrics_write_file(lyrics: ?*const ch_lyrics, path: [*c]const u8) c_int;

const ch_library = opaque {};
extern fn c_lib_create() ?*ch_library;
extern fn c_lib_destroy(lib: ?*ch_library) void;
extern fn c_lib_scan(lib: ?*ch_library, root: [*c]const u8, exts: [*c]const [*c]const u8, ext_count: c_int) c_int;
extern fn c_lib_count(lib: ?*const ch_library) c_int;
extern fn c_lib_path(lib: ?*const ch_library, index: c_int) [*c]const u8;
extern fn c_lib_removed(lib: ?*const ch_library) c_int;
extern fn c_lib_search(lib: ?*const ch_library, needle: [*c]const u8, count_out: *i32) ?[*]i32;
extern fn c_lib_remove(lib: ?*ch_library, path: [*c]const u8) i32;

extern fn ch_file_read_all(path: [*c]const u8, size: *u64) [*c]u8;
extern fn ch_file_free(data: [*c]u8) void;
extern fn ch_file_write_atomic(path: [*c]const u8, data: [*c]const u8, size: u64) i32;
extern fn ch_tags_set(path: [*c]const u8, key: [*c]const u8, value: [*c]const u8) i32;
extern fn ch_tags_mp3_set(path: [*c]const u8, key: [*c]const u8, value: [*c]const u8) i32;
extern fn ch_tags_aac_set(path: [*c]const u8, key: [*c]const u8, value: [*c]const u8) i32;
extern fn ch_tags_mp4_set(path: [*c]const u8, key: [*c]const u8, value: [*c]const u8) i32;
extern fn ch_tags_aiff_set(path: [*c]const u8, key: [*c]const u8, value: [*c]const u8) i32;
extern fn ch_tags_ogg_set(path: [*c]const u8, key: [*c]const u8, value: [*c]const u8) i32;
extern fn ch_tags_opus_set(path: [*c]const u8, key: [*c]const u8, value: [*c]const u8) i32;
const SetFn = *const fn ([*c]const u8, [*c]const u8, [*c]const u8) callconv(.c) i32;
extern fn ch_dir_list_audio(dir: [*c]const u8, extensions: [*c]const [*c]const u8, count_out: *i32) [*c]u8;

const ChLoudness = extern struct {
    integrated_lufs: f64,
    sample_peak_dbfs: f64,
    duration_s: f64,
};
extern fn ch_loudness_scan(path: [*c]const u8, out: *ChLoudness) i32;
extern fn ch_waveform_peaks(path: [*c]const u8, buckets: u32, out_max: [*c]f32) i32;
extern fn ch_bpm_detect(path: [*c]const u8, out_bpm: [*c]f64) i32;
extern fn ch_dr_measure(path: [*c]const u8, out_dr: [*c]f64, out_blocks: [*c]u32) i32;
extern fn ch_key_detect(path: [*c]const u8, out: [*c]u8, out_size: usize, confidence: [*c]f64) i32;
extern fn ch_silence_segments(path: [*c]const u8, threshold_db: f64, min_s: f64, out: [*c]f64, max_segments: i32) i32;
extern fn ch_strip_silence(src: [*c]const u8, dst: [*c]const u8, threshold_db: f64, min_s: f64, gap_s: f64, rate: i32) i32;
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

/// Duerme `ms` milisegundos sin depender del reloj del sistema.
///
/// Antes se usaba `poll` con una lista vacia, que en Zig 0.17 pasa un puntero
/// no valido al kernel: `poll` devuelve EFAULT y el std lo trata como
/// `unreachable` (panico). Con la lista vacia lo correcto es `nanosleep`.
fn sleepMs(ms: u32) void {
    var req: std.c.timespec = .{
        .sec = @intCast(ms / 1000),
        .nsec = @intCast((ms % 1000) * 1_000_000),
    };
    _ = std.c.nanosleep(&req, null);
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

/// Tipos de banda de EQ parametrico.
const PEQType = enum(u8) { peaking, low_shelf, high_shelf };

/// Una banda de EQ parametrico.
const PEQ = struct {
    enabled: bool = false,
    type: PEQType = .peaking,
    freq: f32 = 1000,
    gain_db: f32 = 0,
    q: f32 = 1.0,
    // Coeficientes biquad (RBJ).
    b0: f32 = 1,
    b1: f32 = 0,
    b2: f32 = 0,
    a1: f32 = 0,
    a2: f32 = 0,
    fn recompute(self: *PEQ) void {
        const w0 = 2.0 * std.math.pi * self.freq / SAMPLE_RATE_F;
        const cos_w0 = @cos(w0);
        const sin_w0 = @sin(w0);
        const a = std.math.pow(f32, 10, self.gain_db / 40.0);
        var b0: f32 = 1;
        var b1: f32 = 0;
        var b2: f32 = 0;
        var a0: f32 = 1;
        var a1: f32 = 0;
        var a2: f32 = 0;
        switch (self.type) {
            .peaking => {
                const alpha = sin_w0 / (2.0 * self.q);
                b0 = 1 + alpha * a;
                b1 = -2 * cos_w0;
                b2 = 1 - alpha * a;
                a0 = 1 + alpha / a;
                a1 = -2 * cos_w0;
                a2 = 1 - alpha / a;
            },
            .low_shelf => {
                const alpha = sin_w0 / 2.0 * std.math.sqrt((a + 1.0 / a) * (1.0 / self.q - 1.0) + 2.0);
                const t = 2.0 * std.math.sqrt(a) * alpha;
                b0 = a * ((a + 1) - (a - 1) * cos_w0 + t);
                b1 = 2 * a * ((a - 1) - (a + 1) * cos_w0);
                b2 = a * ((a + 1) - (a - 1) * cos_w0 - t);
                a0 = (a + 1) + (a - 1) * cos_w0 + t;
                a1 = -2 * ((a - 1) + (a + 1) * cos_w0);
                a2 = (a + 1) + (a - 1) * cos_w0 - t;
            },
            .high_shelf => {
                const alpha = sin_w0 / 2.0 * std.math.sqrt((a + 1.0 / a) * (1.0 / self.q - 1.0) + 2.0);
                const t = 2.0 * std.math.sqrt(a) * alpha;
                b0 = a * ((a + 1) + (a - 1) * cos_w0 + t);
                b1 = -2 * a * ((a - 1) + (a + 1) * cos_w0);
                b2 = a * ((a + 1) + (a - 1) * cos_w0 - t);
                a0 = (a + 1) - (a - 1) * cos_w0 + t;
                a1 = 2 * ((a - 1) - (a + 1) * cos_w0);
                a2 = (a + 1) - (a - 1) * cos_w0 - t;
            },
        }
        self.b0 = b0 / a0;
        self.b1 = b1 / a0;
        self.b2 = b2 / a0;
        self.a1 = a1 / a0;
        self.a2 = a2 / a0;
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

    // Bucle A-B (frames; NO_SEEK = desactivado).
    ab_start: usize = NO_SEEK,
    ab_end: usize = NO_SEEK,

    // Cadena DSP de la fase 2: karaoke -> 9D -> ancho/punch. El ancho estereo
    // (1 = normal, 0 = mono, 2 = muy amplio) vive ahora en la cadena.
    dsp: dsp.Dsp = .{},

    // Paisaje sonoro (fase 3): se mezcla bajo la musica, antes del limitador.
    // Atomicos: el hilo de audio lo lee sin candados y sin reservar memoria.
    soundscape: ambient.Soundscape = .{},

    // Recorte automatico de silencio al abrir pista.
    trim_enabled: bool = false,
    trim_threshold_db: f32 = -60,

    // Fundido de entrada al abrir pista (segundos, 0 = el de 8 ms por defecto).
    fade_in_s: f32 = 0,
    // Fundido de salida al llegar al final de la pista (segundos, 0 = corte).
    fade_out_s: f32 = 0,
    // Silencio entre pistas (segundos, 0 = sin pausa).
    gap_s: f32 = 0,
    gap_wait_frames: usize = 0,

    // Crossfeed Bauer para auriculares (API ch_engine_set_crossfeed).
    cf_enabled: bool = false,
    cf_strength_bits: u32 = @bitCast(@as(f32, 0.5)),
    cf_lp_l: f32 = 0,
    cf_lp_r: f32 = 0,
    // Ancho estereo por matriz mid/side (1 = normal, 0 = mono, 2 = amplio).
    width_bits: u32 = @bitCast(@as(f32, 1)),

    // Efecto 8D/espacial: auto-paneo giratorio + reverb.
    spatial_enabled: bool = false,
    spatial_speed_bits: u32 = @bitCast(@as(f32, 0.25)), // vueltas/seg
    spatial_depth_bits: u32 = @bitCast(@as(f32, 0.7)), // 0..1
    spatial_phase: f32 = 0,
    // HRTF: localizacion binaural (angulo -1..1) con retardo interaural.
    hrtf_enabled: bool = false,
    hrtf_angle_bits: u32 = @bitCast(@as(f32, 0)), // -1 izq .. 1 der
    hrtf_delay_l: usize = 0,
    hrtf_delay_r: usize = 0,
    hrtf_buf: ?[]f32 = null,
    hrtf_len: usize = 0,
    hrtf_pos: usize = 0,
    reverb_enabled: bool = false,
    reverb_mix_bits: u32 = @bitCast(@as(f32, 0.25)),
    reverb_buf: ?[]f32 = null,
    reverb_len: usize = 0,
    reverb_pos: usize = 0,

    // Compresor dinamico (dB).
    comp_enabled: bool = false,
    comp_threshold_bits: u32 = @bitCast(@as(f32, -18)),
    comp_ratio_bits: u32 = @bitCast(@as(f32, 4.0)),
    comp_attack_bits: u32 = @bitCast(@as(f32, 0.01)),
    comp_release_bits: u32 = @bitCast(@as(f32, 0.15)),
    comp_env: f32 = 0,

    // EQ parametrico (4 bandas: peaking + low/high shelf). Cada banda tiene
    // {freq, gain_db, q} y un tipo. Se procesan despues del EQ grafico.
    peq_enabled: bool = false,
    peq: [4]PEQ = .{ .{}, .{}, .{}, .{} },
    peq_z: [4][2][2]f32 = .{ .{ .{ 0, 0 }, .{ 0, 0 } }, .{ .{ 0, 0 }, .{ 0, 0 } }, .{ .{ 0, 0 }, .{ 0, 0 } }, .{ .{ 0, 0 }, .{ 0, 0 } } },

    // Mezcla: mono y balance (-1 izquierda .. +1 derecha).
    balance_bits: u32 = @bitCast(@as(f32, 0)),
    gain_db_bits: u32 = @bitCast(@as(f32, 0)),

    // Medidores (ventana desde la ultima lectura).
    meter_lock: SpinLock = .{},
    meter_peak_l: f32 = 0,
    meter_peak_r: f32 = 0,
    meter_sum: f64 = 0,
    meter_frames: usize = 0,
    // Estadisticas de escucha.
    stats_lock: SpinLock = .{},
    play_count: u64 = 0,
    listen_frames: u64 = 0,
    // Favoritos (rutas persistentes).
    favorites: std.ArrayListUnmanaged([]u8) = .empty,
    // Historial de reproduccion reciente (para shuffle con recencia).
    recent: std.ArrayListUnmanaged([]u8) = .empty,
    recent_cap: usize = 50,
    avoid_recent: bool = false,
    pause_at_dir_end: bool = false,
    auto_gain: bool = false,
    auto_gain_target: f64 = -14.0,
    sleep_end_ms: u64 = 0,
    sleep_fade_ms: u32 = 8000,
    sleep_fired: bool = false,
    buf_underflows: u64 = 0,
    // Niveles de salida para vumetros (bits de f32, legibles sin candados).
    level_rms: [2]u32 = @splat(0),
    level_peak: [2]u32 = @splat(0),
    pause_fade_bits: u32 = @bitCast(@as(f32, 0.05)),
    // Modo de canales: 0 estereo, 1 mono, 2 intercambiados.
    chan_mode: u32 = 0,
    // 0 = ReplayGain por pista, 1 = por album.
    rg_mode: u32 = 0,
    // Salida S16 con dither TPDF (por defecto se entrega f32 al dispositivo).
    s16_output: bool = false,
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

    /// Busca cover.jpg / cover.png junto al audio y lo carga si existe.
    fn loadCoverFromFile(self: *Engine, index: usize, seg: *Segment) void {
        if (index >= self.playlist.items.len) return;
        const path = self.playlist.items[index];
        const dir_end = std.mem.lastIndexOfScalar(u8, path, '/') orelse return;
        const dir = path[0 .. dir_end + 1];
        const names = [_][]const u8{ "cover.jpg", "cover.png", "Cover.jpg", "Cover.png", "folder.jpg", "front.jpg" };
        for (names) |name| {
            const full = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ dir, name }) catch continue;
            defer self.allocator.free(full);
            var sz: u64 = 0;
            const raw = ch_file_read_all(full.ptr, &sz) orelse continue;
            const len: usize = @intCast(sz);
            if (len == 0) {
                ch_file_free(raw);
                continue;
            }
            if (self.allocator.alloc(u8, len)) |copy| {
                @memcpy(copy, raw[0..len]);
                seg.covers[seg.cover_count] = copy;
                seg.cover_count = 1;
            } else |_| {}
            ch_file_free(raw);
            return;
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
        // Caratula desde archivo: si el audio no traia, buscar cover.jpg/png.
        if (seg.cover_count == 0) {
            self.loadCoverFromFile(index, &seg);
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
        // Estadistica: cuenta una reproduccion.
        self.stats_lock.lock();
        self.play_count += 1;
        self.stats_lock.unlock();
        // Historial reciente (evita repetir en shuffle).
        if (index < self.playlist.items.len) {
            const path = self.playlist.items[index];
            var already = false;
            for (self.recent.items) |r| {
                if (std.mem.eql(u8, r, path)) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                if (self.recent.items.len >= self.recent_cap) {
                    const old = self.recent.orderedRemove(0);
                    self.allocator.free(old);
                }
                const copy = self.allocator.dupe(u8, path) catch null;
                if (copy) |c| self.recent.append(self.allocator, c) catch {
                    self.allocator.free(c);
                };
            }
        }
        // Fundido de entrada suave (evita el clic al abrir una pista nueva).
        self.fade_gain = 0;
        if (self.trim_enabled) self.applyTrim(index);
        if (self.auto_gain) self.applyAutoGain(index);
        return 0;
    }

    /// Ajusta la ganancia manual para que la pista suene a `auto_gain_target`.
    fn applyAutoGain(self: *Engine, index: usize) void {
        if (index >= self.playlist.items.len) return;
        var result: ChLoudness = undefined;
        if (ch_loudness_scan(self.playlist.items[index].ptr, &result) != 0) return;
        const gain = std.math.clamp(self.auto_gain_target - result.integrated_lufs, -24, 24);
        _ = ch_engine_set_gain_db(self, @floatCast(gain));
    }

    /// Recorta el silencio inicial/final de la pista recién añadida.
    fn applyTrim(self: *Engine, index: usize) void {
        if (index >= self.playlist.items.len) return;
        const path = self.playlist.items[index];
        var lead: f64 = 0;
        var tail: f64 = 0;
        if (ch_engine_detect_silence(path.ptr, self.trim_threshold_db, &lead, &tail) != 0) return;

        const lead_frames: usize = @intFromFloat(@max(0, lead) * SAMPLE_RATE);
        const tail_frames: usize = @intFromFloat(@max(0, tail) * SAMPLE_RATE);

        self.seg_lock.lock();
        if (self.seg_count > 0) {
            const seg = &self.segments[self.seg_count - 1];
            const span = seg.end -| seg.start;
            seg.end -= @min(tail_frames, span);
        }
        self.seg_lock.unlock();

        // Aplicar tambien el desplazamiento a la posicion base del segmento:
        // el reloj del motor resta `seg.start`, asi que sin esto `played` quedaria
        // por debajo del inicio y el analisis de posicion seria incorrecto.
        if (lead_frames > 0) {
            self.seg_lock.lock();
            if (self.seg_count > 0) {
                const seg = &self.segments[self.seg_count - 1];
                seg.start += @min(lead_frames, seg.end - seg.start);
                self.running_end = seg.end;
            }
            self.seg_lock.unlock();
            @atomicStore(usize, &self.seek_req, lead_frames, .release);
        }
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
                // Estadistica: tiempo escuchado (frames reproducidos).
                self.stats_lock.lock();
                self.listen_frames += adv;
                self.stats_lock.unlock();
            }
        }

        const produced = take * CHANNELS;
        self.equalizer.process(out[0..produced], take);

        // EQ parametrico de 4 bandas (despues del grafico).
        if (self.peq_enabled) {
            self.processPEQ(out[0..produced], take);
        }

        // Compresor dinamico (antes del limitador y los medidores).
        if (self.comp_enabled) {
            self.processCompressor(out[0..produced], take);
        }

        // Bucle A-B: al llegar a B se vuelve a A.
        const ab_end = @atomicLoad(usize, &self.ab_end, .acquire);
        if (playing and ab_end != NO_SEEK) {
            const p = @atomicLoad(usize, &self.played, .acquire);
            if (p >= ab_end) {
                @atomicStore(usize, &self.seek_req, @atomicLoad(usize, &self.ab_start, .acquire), .release);
            }
        }

        var target: f32 = 0;
        var fade_out_gain: f32 = 1;
        if (playing) {
            target = self.volume();
            if (@atomicLoad(bool, &self.rg_enabled, .monotonic)) target *= self.audibleGain();
            const gain_db = @as(f32, @bitCast(@atomicLoad(u32, &self.gain_db_bits, .monotonic)));
            if (gain_db != 0) target *= std.math.pow(f32, 10, gain_db / 20);
            if (self.sleepGain()) |sg| {
                target *= sg;
                if (sg <= 0) self.fireSleep();
            }
            // Fundido de salida cuando quedan menos de N segundos de pista.
            if (self.fade_out_s > 0 and self.seg_count > 0) {
                e_fade: {
                    self.seg_lock.lock();
                    if (self.seg_count == 0) {
                        self.seg_lock.unlock();
                        break :e_fade;
                    }
                    const end = self.segments[self.seg_count - 1].end;
                    self.seg_lock.unlock();
                    const pos = @atomicLoad(usize, &self.played, .acquire);
                    if (end <= pos) break :e_fade;
                    const remaining = @as(f32, @floatFromInt(end - pos)) / @as(f32, @floatFromInt(SAMPLE_RATE));
                    const total = self.fade_out_s;
                    if (remaining < total) {
                        const x = std.math.clamp(remaining / total, 0, 1);
                        fade_out_gain = x * x; // curva cuadratica suave
                    }
                }
            }
            target *= fade_out_gain;
        }
        if (take > 0) {
            var g = self.fade_gain;
            const fade_frames = if (self.fade_in_s > 0)
                self.fade_in_s * @as(f32, @floatFromInt(SAMPLE_RATE))
            else
                self.pauseFadeSeconds() * @as(f32, @floatFromInt(SAMPLE_RATE));
            const fade_coeff: f32 = if (fade_frames <= 0)
                1.0
            else
                1.0 - @exp(-1.0 / fade_frames);
            const limiting = self.limit_enabled;
            const ceiling = self.limit_ceiling;
            var lg = self.limit_gain;
            const crossfeeding = self.cf_enabled;
            const width = @as(f32, @bitCast(@atomicLoad(u32, &self.width_bits, .monotonic)));
            const spatial = self.spatial_enabled;
            const spatial_speed = @as(f32, @bitCast(@atomicLoad(u32, &self.spatial_speed_bits, .monotonic)));
            const spatial_depth = @as(f32, @bitCast(@atomicLoad(u32, &self.spatial_depth_bits, .monotonic)));
            const reverb_on = self.reverb_enabled;
            const reverb_mix = @as(f32, @bitCast(@atomicLoad(u32, &self.reverb_mix_bits, .monotonic)));
            const hrtf_on = self.hrtf_enabled;
            const hrtf_angle = @as(f32, @bitCast(@atomicLoad(u32, &self.hrtf_angle_bits, .monotonic)));
            var spatial_phase = self.spatial_phase;
            const cf_strength = @as(f32, @bitCast(@atomicLoad(u32, &self.cf_strength_bits, .monotonic)));
            const cf_wet = 0.6 * std.math.clamp(cf_strength, 0.0, 1.0);
            const cf_alpha = 1.0 - @exp(-2.0 * std.math.pi * 700.0 / @as(f32, @floatFromInt(SAMPLE_RATE)));
            var lp_l = self.cf_lp_l;
            var lp_r = self.cf_lp_r;
            var peak_l: f32 = 0;
            var peak_r: f32 = 0;
            var sq: f64 = 0;
            // Ataque rapido, recuperacion lenta (~200 ms).
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
                    // Mono: misma senal en los dos altavoces.
                    const m = (l + rr) * 0.5;
                    l = m;
                    rr = m;
                } else if (chan_mode == 2) {
                    const t = l;
                    l = rr;
                    rr = t;
                } else if (chan_mode == 3) {
                    // Solo canal izquierdo.
                    rr = l;
                } else if (chan_mode == 4) {
                    // Solo canal derecho.
                    l = rr;
                } else if (chan_mode == 5) {
                    // Karaoke: cancela la voz centrada (L - R).
                    const m = (l - rr) * 0.5;
                    l = m;
                    rr = m;
                }
                var s = l * g;
                var s2 = rr * g;

                // Karaoke -> 9D -> ancho/punch -> crossfeed -> modo noche:
                // atomicos, sin candados y sin reservar memoria (esto corre en
                // el callback de audio). El limitador va justo despues.
                if (!self.dsp.isIdle()) {
                    const shaped = self.dsp.process(s, s2);
                    s = shaped[0];
                    s2 = shaped[1];
                }

                // Paisaje sonoro: se suma bajo la musica y antes del limitador,
                // asi el limitador tambien protege de la suma.
                if (!self.soundscape.isIdle()) {
                    const sc = self.soundscape.process();
                    s += sc[0];
                    s2 += sc[1];
                }
                if (crossfeeding) {
                    // Bauer simplificado: mezcla el canal opuesto filtrado paso bajo.
                    lp_l += (s2 - lp_l) * cf_alpha;
                    lp_r += (s - lp_r) * cf_alpha;
                    const l2 = s * (1.0 - cf_wet * 0.5) + lp_l * cf_wet;
                    const r2 = s2 * (1.0 - cf_wet * 0.5) + lp_r * cf_wet;
                    s = l2;
                    s2 = r2;
                }
                if (width != 1.0) {
                    // Matriz mid/side: width 0 = mono, 1 = normal, 2 = amplio.
                    const mid = (s + s2) * 0.5;
                    const side = (s - s2) * 0.5 * width;
                    s = mid + side;
                    s2 = mid - side;
                }
                if (spatial) {
                    // Auto-paneo giratorio (efecto 8D): rota la imagen estereo.
                    const angle = spatial_phase;
                    const pan = @sin(angle) * spatial_depth;
                    // Ganancias de paneo (ley seno/coseno).
                    const gl = std.math.cos((pan + 1.0) * std.math.pi * 0.25);
                    const gr = std.math.sin((pan + 1.0) * std.math.pi * 0.25);
                    const mid = (s + s2) * 0.5;
                    s = mid * gl * 1.4142;
                    s2 = mid * gr * 1.4142;
                    spatial_phase += spatial_speed * 2.0 * std.math.pi / @as(f32, @floatFromInt(SAMPLE_RATE));
                    if (spatial_phase > 2.0 * std.math.pi) spatial_phase -= 2.0 * std.math.pi;
                }
                if (balance != 0) {
                    s *= gain_l;
                    s2 *= gain_r;
                }
                if (reverb_on) {
                    // Reverb estéreo simple (delay con feedback cruzado).
                    if (self.reverb_buf) |rbuf| {
                        const dly = 1557; // ~32 ms @ 48k
                        const fb: f32 = 0.35;
                        const wet = reverb_mix;
                        const dry = 1.0 - wet * 0.5;
                        const rev_l = rbuf[self.reverb_pos];
                        const rev_r = rbuf[(self.reverb_pos + dly) % self.reverb_len];
                        rbuf[self.reverb_pos] = s * fb + rev_r * fb;
                        rbuf[(self.reverb_pos + dly) % self.reverb_len] = s2 * fb + rev_l * fb;
                        s = s * dry + rev_l * wet;
                        s2 = s2 * dry + rev_r * wet;
                        self.reverb_pos = (self.reverb_pos + 1) % self.reverb_len;
                    }
                }
                if (hrtf_on) {
                    // Localizacion binaural: retardo interaural + sombra.
                    if (self.hrtf_buf) |hbuf| {
                        const half = self.hrtf_len / 2;
                        const pos = self.hrtf_pos;
                        const ang = std.math.clamp(hrtf_angle, -1, 1);
                        const max_delay: usize = half - 1;
                        const hdly = @as(usize, @intFromFloat(@abs(ang) * @as(f32, @floatFromInt(max_delay))));
                        // Leer la muestra del canal derecho retardada (o izq).
                        const r_idx = (pos + half - hdly) % half;
                        const l_idx = (pos + half - hdly) % half;
                        // Escribir actuales en el buffer circular.
                        hbuf[pos] = s;
                        hbuf[pos + half] = s2;
                        // Aplicar retardo al canal contrario.
                        if (ang > 0) {
                            s2 = hbuf[l_idx];
                        } else if (ang < 0) {
                            s = hbuf[r_idx];
                        }
                        self.hrtf_pos = (pos + 1) % half;
                        // Sombra: atenuar el lado opuesto.
                        const atten = 1.0 - @abs(ang) * 0.25;
                        if (ang > 0) s *= atten;
                        if (ang < 0) s2 *= atten;
                    }
                }
                if (limiting) {
                    const peak = @max(@abs(s), @abs(s2));
                    var desired = lg;
                    if (peak > ceiling and peak > 0) desired = ceiling / peak;
                    if (desired < lg) {
                        lg = desired; // ataque inmediato
                    } else {
                        lg += (desired - lg) * release;
                    }
                    s *= lg;
                    s2 *= lg;
                }
                out[i * CHANNELS] = s;
                out[i * CHANNELS + 1] = s2;

                const al = @abs(s);
                const ar = @abs(s2);
                if (al > peak_l) peak_l = al;
                if (ar > peak_r) peak_r = ar;
                sq += @as(f64, s) * s + @as(f64, s2) * s2;
            }
            self.limit_gain = lg;
            self.cf_lp_l = lp_l;
            self.cf_lp_r = lp_r;
            self.spatial_phase = spatial_phase;
            self.fade_gain = if (!playing and g < 0.001) 0 else g;

            self.meter_lock.lock();
            if (peak_l > self.meter_peak_l) self.meter_peak_l = peak_l;
            if (peak_r > self.meter_peak_r) self.meter_peak_r = peak_r;
            self.meter_sum += sq;
            self.meter_frames += take;
            self.meter_lock.unlock();
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
                    // Gap entre pistas: mantener silencio N segundos antes del salto.
                    if (self.gap_s > 0 and self.gap_wait_frames == 0 and
                        self.queue_index + 1 < self.playlist.items.len)
                    {
                        self.gap_wait_frames = @intFromFloat(self.gap_s * SAMPLE_RATE);
                    }
                    if (self.gap_wait_frames > 0) {
                        const chunk = @min(self.gap_wait_frames, @as(usize, @intCast(tol)));
                        self.gap_wait_frames -= chunk;
                        @atomicStore(usize, &self.played, p, .release);
                        return;
                    }
                    @atomicStore(bool, &self.playing, false, .release);
                    self.pushEvent(EV_END, 0, 0, 0);
                    self.pushEvent(EV_STATE, 0, 0, 0);
                    // Pausar al final de carpeta: si la siguiente pista esta en
                    // otro directorio, no seguir (la UI decide si continuar).
                    if (self.pause_at_dir_end and self.differentDir(self.queue_index)) {
                        self.pushEvent(EV_QUEUE, -1, 0, 0);
                    }
                }
            }
        }
    }

    fn processPEQ(self: *Engine, buf: []f32, frames: usize) void {
        for (0..4) |bi| {
            const bp = &self.peq[bi];
            if (!bp.enabled) continue;
            const b = bp.*;
            for (0..2) |ch| {
                var z1 = self.peq_z[bi][ch][0];
                var z2 = self.peq_z[bi][ch][1];
                var i: usize = 0;
                while (i < frames) : (i += 1) {
                    const idx = i * CHANNELS + ch;
                    const x = buf[idx];
                    const y = b.b0 * x + z1;
                    z1 = b.b1 * x - b.a1 * y + z2;
                    z2 = b.b2 * x - b.a2 * y;
                    buf[idx] = y;
                }
                self.peq_z[bi][ch][0] = z1;
                self.peq_z[bi][ch][1] = z2;
            }
        }
    }

    fn processCompressor(self: *Engine, buf: []f32, frames: usize) void {
        const threshold_db = @as(f32, @bitCast(@atomicLoad(u32, &self.comp_threshold_bits, .monotonic)));
        const ratio = @as(f32, @bitCast(@atomicLoad(u32, &self.comp_ratio_bits, .monotonic)));
        const attack = @as(f32, @bitCast(@atomicLoad(u32, &self.comp_attack_bits, .monotonic)));
        const release = @as(f32, @bitCast(@atomicLoad(u32, &self.comp_release_bits, .monotonic)));
        const attack_coef = 1.0 - @exp(-1.0 / (attack * SAMPLE_RATE_F + 1e-6));
        const release_coef = 1.0 - @exp(-1.0 / (release * SAMPLE_RATE_F + 1e-6));
        var env = self.comp_env;
        var i: usize = 0;
        while (i < frames) : (i += 1) {
            const l = buf[i * CHANNELS];
            const r = buf[i * CHANNELS + 1];
            const peak = @max(@abs(l), @abs(r));
            // Envolvente (dB).
            const level_db = if (peak > 1e-7) 20.0 * std.math.log10(peak) else -120.0;
            const target_env = level_db;
            const coef = if (target_env > env) attack_coef else release_coef;
            env += (target_env - env) * coef;
            // Solo comprime por encima del umbral.
            var gain_db: f32 = 0;
            if (env > threshold_db) {
                gain_db = (threshold_db - env) * (1.0 - 1.0 / ratio);
            }
            const g = std.math.pow(f32, 10, gain_db / 20.0);
            buf[i * CHANNELS] = l * g;
            buf[i * CHANNELS + 1] = r * g;
        }
        self.comp_env = env;
    }

    /// Comprueba si la pista `index` y la siguiente estan en directorios distintos.
    fn differentDir(self: *Engine, index: usize) bool {
        if (index + 1 >= self.playlist.items.len) return false;
        const a = self.playlist.items[index];
        const b = self.playlist.items[index + 1];
        const da = std.mem.lastIndexOfScalar(u8, a, '/') orelse return false;
        const db = std.mem.lastIndexOfScalar(u8, b, '/') orelse return false;
        return !std.mem.eql(u8, a[0..da], b[0..db]);
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
    for (e.favorites.items) |f| e.allocator.free(f);
    e.favorites.deinit(e.allocator);
    for (e.recent.items) |r| e.allocator.free(r);
    e.recent.deinit(e.allocator);
    for (e.playlist.items) |p| e.allocator.free(p);
    e.playlist.deinit(e.allocator);
    e.order.deinit(e.allocator);
    if (e.stretch) |*st| st.deinit();
    e.allocator.free(e.stretch_buf);
    e.allocator.free(e.sp_im);
    e.allocator.free(e.sp_re);
    e.allocator.free(e.sp_buf);
    e.allocator.free(e.scratch);
    if (e.reverb_buf) |b| e.allocator.free(b);
    if (e.hrtf_buf) |b| e.allocator.free(b);
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

    // Buffer de reverb estereo (~50 ms x 2 canales).
    self.reverb_len = 4096;
    self.reverb_buf = alloc.alloc(f32, self.reverb_len) catch null;
    self.reverb_pos = 0;

    // Buffer de retardo interaural para HRTF (~2 ms).
    self.hrtf_len = 128;
    self.hrtf_buf = alloc.alloc(f32, self.hrtf_len * 2) catch null;
    self.hrtf_pos = 0;

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

/// Añade a la cola todos los audios de un directorio (no recursivo).
/// Devuelve el numero de archivos añadidos, o negativo si error.
export fn ch_engine_load_dir(self: ?*Engine, dir: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (dir == null) return -1;

    // Lista de extensiones soportadas (terminada en null).
    const exts = [_]?[*:0]const u8{ ".flac", ".mp3", ".wav", ".ogg", ".opus", ".m4a", ".aac", ".aiff", ".alac", null };
    var count: i32 = 0;
    const raw = ch_dir_list_audio(dir, @ptrCast(&exts), &count);
    if (raw == null) return 0;
    defer ch_file_free(raw);

    var added: i32 = 0;
    var it = std.mem.splitScalar(u8, raw[0..@intCast(std.mem.len(raw))], '\n');
    e.list_mutex.lock();
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const z = e.allocator.dupeSentinel(u8, line, 0) catch continue;
        e.playlist.append(e.allocator, z) catch {
            e.allocator.free(z);
            continue;
        };
        added += 1;
    }
    e.list_mutex.unlock();

    if (added > 0) {
        e.pushEvent(EV_QUEUE, added, 0, 0);
        e.order.clearRetainingCapacity();
        e.order_pos = 0;
    }
    return added;
}

/// Exporta la cola actual a un archivo JSON (solo rutas). Devuelve 0 si ok.
export fn ch_engine_queue_export_json(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);
    buf.appendSlice(e.allocator, "{\n  \"queue\": [\n") catch return -2;
    e.list_mutex.lock();
    for (e.playlist.items, 0..) |item, i| {
        buf.appendSlice(e.allocator, "    \"") catch {};
        appendJsonString(&buf, e.allocator, item) catch {};
        buf.appendSlice(e.allocator, "\"") catch {};
        if (i + 1 < e.playlist.items.len) buf.append(e.allocator, ',') catch {};
        buf.append(e.allocator, '\n') catch {};
    }
    e.list_mutex.unlock();
    buf.appendSlice(e.allocator, "  ],\n  \"index\": ") catch return -2;
    var tmp: [32]u8 = undefined;
    const num = std.fmt.bufPrint(&tmp, "{d}", .{e.queue_index}) catch return -2;
    buf.appendSlice(e.allocator, num) catch return -2;
    buf.appendSlice(e.allocator, "\n}\n") catch return -2;
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Exporta la cola a M3U con #EXTINF (titulo - artista) ademas de la ruta.
export fn ch_engine_queue_export_m3u_ext(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);
    buf.appendSlice(e.allocator, "#EXTM3U\n") catch return -2;
    e.list_mutex.lock();
    for (e.playlist.items) |item| {
        // readFileMeta copia antes de cerrar el decodificador: los punteros de
        // ch_decode_* dejan de ser validos en ch_decode_close.
        var meta = readFileMeta(e.allocator, item) orelse FileMeta{ .title = &.{}, .artist = &.{}, .album = &.{}, .duration = 0 };
        defer meta.deinit(e.allocator);
        const title: []const u8 = meta.title;
        const artist: []const u8 = meta.artist;
        var tmp: [512]u8 = undefined;
        const line = std.fmt.bufPrint(&tmp, "#EXTINF:-1,{s} - {s}\n{s}\n", .{ artist, title, item }) catch continue;
        buf.appendSlice(e.allocator, line) catch {};
    }
    e.list_mutex.unlock();
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Igual que ch_engine_queue_export_m3u_ext pero con rutas relativas al
/// directorio del .m3u (util para mover la lista con la musica).
export fn ch_engine_queue_export_m3u_relative(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    const span = std.mem.span(path);
    const slash = std.mem.lastIndexOfScalar(u8, span, '/');
    const base: []const u8 = if (slash) |i| span[0 .. i + 1] else "";

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);
    buf.appendSlice(e.allocator, "#EXTM3U\n") catch return -2;

    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    for (e.playlist.items) |item| {
        const full: []const u8 = item;
        // Quitar el prefijo comun para dejar la ruta relativa.
        var rel: []const u8 = full;
        if (base.len > 0 and std.mem.startsWith(u8, full, base)) {
            rel = full[base.len..];
        }
        var meta = readFileMeta(e.allocator, item) orelse FileMeta{ .title = &.{}, .artist = &.{}, .album = &.{}, .duration = 0 };
        defer meta.deinit(e.allocator);
        const title: []const u8 = meta.title;
        const artist: []const u8 = meta.artist;
        var tmp: [512]u8 = undefined;
        const line = std.fmt.bufPrint(&tmp, "#EXTINF:-1,{s} - {s}\n{s}\n", .{ artist, title, rel }) catch continue;
        buf.appendSlice(e.allocator, line) catch {};
    }
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Importa una cola desde un JSON exportado por ch_engine_queue_export_json.
/// Devuelve el numero de pistas importadas, o negativo si error.
export fn ch_engine_queue_import_json(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var size: u64 = 0;
    const raw = ch_file_read_all(path, &size) orelse return -2;
    defer ch_file_free(raw);
    const data = raw[0..@intCast(size)];

    var added: i32 = 0;
    // Buscar lineas que empiecen por espacios + comilla (los paths).
    var it = std.mem.splitScalar(u8, data, '\n');
    e.list_mutex.lock();
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t");
        if (t.len < 2 or t[0] != '"') continue;
        // Extraer el contenido entre comillas (con escapes).
        const end = std.mem.lastIndexOfScalar(u8, t, '"') orelse continue;
        if (end <= 0) continue;
        const content = t[1..end];
        // Desescapar.
        var clean: std.ArrayListUnmanaged(u8) = .empty;
        defer clean.deinit(e.allocator);
        var i: usize = 0;
        while (i < content.len) : (i += 1) {
            if (content[i] == '\\' and i + 1 < content.len) {
                i += 1;
                clean.append(e.allocator, switch (content[i]) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    else => content[i],
                }) catch {};
            } else {
                clean.append(e.allocator, content[i]) catch {};
            }
        }
        if (clean.items.len == 0) continue;
        const z = e.allocator.dupeSentinel(u8, clean.items, 0) catch continue;
        e.playlist.append(e.allocator, z) catch {
            e.allocator.free(z);
            continue;
        };
        added += 1;
    }
    e.list_mutex.unlock();
    if (added > 0) {
        e.pushEvent(EV_QUEUE, added, 0, 0);
        e.order.clearRetainingCapacity();
        e.order_pos = 0;
    }
    return added;
}

/// Ordena la cola alfabeticamente por ruta. Devuelve 0 si ok.
export fn ch_engine_queue_sort(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    std.mem.sort([:0]u8, e.playlist.items, {}, struct {
        fn lt(_: void, a: [:0]u8, b: [:0]u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por titulo (abre cada archivo para leer el tag). Devuelve 0.
export fn ch_engine_queue_sort_title(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    // Precomputar titulos.
    const titles = e.allocator.alloc([]const u8, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(titles);
    var owned = e.allocator.alloc([]u8, n) catch {
        e.allocator.free(titles);
        e.list_mutex.unlock();
        return -2;
    };
    defer {
        for (owned) |o| e.allocator.free(o);
        e.allocator.free(owned);
    }
    for (e.playlist.items, 0..) |item, i| {
        owned[i] = readTagDup(e.allocator, item, "title");
        titles[i] = if (owned[i].len > 0) owned[i] else item;
    }
    // Ordenar por titulo (simple insertion sort, n pequeno).
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, titles[j], titles[j - 1])) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap([]const u8, &titles[j], &titles[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por artista (abre cada archivo para leer el tag). Devuelve 0.
export fn ch_engine_queue_sort_artist(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const arts = e.allocator.alloc([]const u8, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(arts);
    // El tag vive dentro del decodificador y deja de ser valido al cerrarlo,
    // asi que se copia y se libera despues de ordenar.
    var metas = e.allocator.alloc(FileMeta, n) catch {
        e.allocator.free(arts);
        e.list_mutex.unlock();
        return -2;
    };
    defer {
        for (metas) |*m| m.deinit(e.allocator);
        e.allocator.free(metas);
    }
    for (e.playlist.items, 0..) |item, i| {
        metas[i] = readFileMeta(e.allocator, item) orelse FileMeta{ .title = &.{}, .artist = &.{}, .album = &.{}, .duration = 0 };
        arts[i] = if (metas[i].artist.len > 0) metas[i].artist else item;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, arts[j], arts[j - 1])) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap([]const u8, &arts[j], &arts[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por album. Devuelve 0.
export fn ch_engine_queue_sort_album(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const vals = e.allocator.alloc([]const u8, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(vals);
    var metas = e.allocator.alloc(FileMeta, n) catch {
        e.allocator.free(vals);
        e.list_mutex.unlock();
        return -2;
    };
    defer {
        for (metas) |*m| m.deinit(e.allocator);
        e.allocator.free(metas);
    }
    for (e.playlist.items, 0..) |item, i| {
        metas[i] = readFileMeta(e.allocator, item) orelse FileMeta{ .title = &.{}, .artist = &.{}, .album = &.{}, .duration = 0 };
        vals[i] = if (metas[i].album.len > 0) metas[i].album else item;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, vals[j], vals[j - 1])) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap([]const u8, &vals[j], &vals[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por año (tag date). Devuelve 0.
export fn ch_engine_queue_sort_year(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const years = e.allocator.alloc(i32, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(years);
    for (e.playlist.items, 0..) |item, i| {
        var year: i32 = 0;
        if (ch_decode_open(item.ptr, SAMPLE_RATE, CHANNELS)) |d| {
            const dt = parseLeadingFloat(std.mem.span(ch_decode_tag(d, "date"))) orelse 0;
            year = @intFromFloat(dt);
            ch_decode_close(d);
        }
        years[i] = year;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and years[j] < years[j - 1]) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap(i32, &years[j], &years[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por numero de pista. Devuelve 0.
export fn ch_engine_queue_sort_track(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const nums = e.allocator.alloc(i32, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(nums);
    for (e.playlist.items, 0..) |item, i| {
        var num: i32 = 0;
        if (ch_decode_open(item.ptr, SAMPLE_RATE, CHANNELS)) |d| {
            num = @intFromFloat(parseLeadingFloat(std.mem.span(ch_decode_tag(d, "track"))) orelse 0);
            ch_decode_close(d);
        }
        nums[i] = num;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and nums[j] < nums[j - 1]) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap(i32, &nums[j], &nums[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por duracion (menor a mayor). Devuelve 0.
export fn ch_engine_queue_sort_duration(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const durs = e.allocator.alloc(f64, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(durs);
    for (e.playlist.items, 0..) |item, i| {
        var dur: f64 = 0;
        if (ch_decode_open(item.ptr, SAMPLE_RATE, CHANNELS)) |d| {
            dur = ch_decode_duration(d);
            ch_decode_close(d);
        }
        durs[i] = dur;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and durs[j] < durs[j - 1]) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap(f64, &durs[j], &durs[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por albumartist. Devuelve 0.
export fn ch_engine_queue_sort_albumartist(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const vals = e.allocator.alloc([]const u8, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(vals);
    var owned = e.allocator.alloc([]u8, n) catch {
        e.allocator.free(vals);
        e.list_mutex.unlock();
        return -2;
    };
    defer {
        for (owned) |o| e.allocator.free(o);
        e.allocator.free(owned);
    }
    for (e.playlist.items, 0..) |item, i| {
        owned[i] = readTagDup(e.allocator, item, "albumartist");
        vals[i] = if (owned[i].len > 0) owned[i] else item;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, vals[j], vals[j - 1])) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap([]const u8, &vals[j], &vals[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por genero. Devuelve 0.
export fn ch_engine_queue_sort_genre(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const vals = e.allocator.alloc([]const u8, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(vals);
    var owned = e.allocator.alloc([]u8, n) catch {
        e.allocator.free(vals);
        e.list_mutex.unlock();
        return -2;
    };
    defer {
        for (owned) |o| e.allocator.free(o);
        e.allocator.free(owned);
    }
    for (e.playlist.items, 0..) |item, i| {
        owned[i] = readTagDup(e.allocator, item, "genre");
        vals[i] = if (owned[i].len > 0) owned[i] else item;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, vals[j], vals[j - 1])) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap([]const u8, &vals[j], &vals[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por compositor. Devuelve 0.
export fn ch_engine_queue_sort_composer(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const vals = e.allocator.alloc([]const u8, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(vals);
    var owned = e.allocator.alloc([]u8, n) catch {
        e.allocator.free(vals);
        e.list_mutex.unlock();
        return -2;
    };
    defer {
        for (owned) |o| e.allocator.free(o);
        e.allocator.free(owned);
    }
    for (e.playlist.items, 0..) |item, i| {
        owned[i] = readTagDup(e.allocator, item, "composer");
        vals[i] = if (owned[i].len > 0) owned[i] else item;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and std.mem.lessThan(u8, vals[j], vals[j - 1])) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap([]const u8, &vals[j], &vals[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Ordena la cola por tamaño de archivo (menor a mayor). Devuelve 0.
export fn ch_engine_queue_sort_filesize(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    const sizes = e.allocator.alloc(u64, n) catch {
        e.list_mutex.unlock();
        return -2;
    };
    defer e.allocator.free(sizes);
    for (e.playlist.items, 0..) |item, i| {
        var sz: u64 = 0;
        if (ch_file_read_all(item.ptr, &sz)) |raw| {
            ch_file_free(raw);
        }
        sizes[i] = sz;
    }
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var j = i;
        while (j > 0 and sizes[j] < sizes[j - 1]) {
            std.mem.swap([:0]u8, &e.playlist.items[j], &e.playlist.items[j - 1]);
            std.mem.swap(u64, &sizes[j], &sizes[j - 1]);
            j -= 1;
        }
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Invierte el orden de la cola.
export fn ch_engine_queue_reverse(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    std.mem.reverse([:0]u8, e.playlist.items);
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Reordena la cola actual aleatoriamente (Fisher-Yates con PRNG).
export fn ch_engine_queue_shuffle(self: ?*Engine, seed: u32) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    var rng = std.Random.DefaultPrng.init(seed);
    const r = rng.random();
    var i: usize = e.playlist.items.len;
    while (i > 1) {
        i -= 1;
        const j = r.intRangeLessThan(usize, 0, i + 1);
        std.mem.swap([:0]u8, &e.playlist.items[i], &e.playlist.items[j]);
    }
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return 0;
}

/// Inserta una pista en la cola manteniendo el orden alfabetico. Devuelve el
/// indice insertado, o negativo si error.
export fn ch_engine_queue_insert_sorted(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    const p = std.mem.span(path);
    const copy = e.allocator.dupeSentinel(u8, p, 0) catch return -2;

    e.list_mutex.lock();
    // Encontrar posicion: primera ruta mayor que la nueva.
    var pos: usize = 0;
    while (pos < e.playlist.items.len and std.mem.lessThan(u8, e.playlist.items[pos], copy)) : (pos += 1) {}
    e.playlist.insert(e.allocator, pos, copy) catch {
        e.list_mutex.unlock();
        e.allocator.free(copy);
        return -2;
    };
    const idx: i32 = @intCast(pos);
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return idx;
}

/// Deja en la cola solo la pista que suena ahora. Devuelve el numero eliminado.
export fn ch_engine_queue_keep_current(self: ?*Engine) i32 {
    const e = self orelse return -1;
    var removed: i32 = 0;
    e.list_mutex.lock();
    const current = e.audibleIndex() orelse e.queue_index;
    var i: usize = 0;
    while (i < e.playlist.items.len) {
        if (i != current) {
            e.allocator.free(e.playlist.items[i]);
            _ = e.playlist.orderedRemove(i);
            removed += 1;
        } else {
            i += 1;
        }
    }
    e.queue_index = 0;
    e.list_mutex.unlock();
    if (removed > 0) {
        e.order.clearRetainingCapacity();
        e.order_pos = 0;
    }
    return removed;
}

/// Duplica la pista actual al final de la cola. Devuelve el nuevo indice.
export fn ch_engine_queue_duplicate_current(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const current = e.audibleIndex() orelse e.queue_index;
    if (current >= e.playlist.items.len) {
        e.list_mutex.unlock();
        return -1;
    }
    const copy = e.allocator.dupeSentinel(u8, e.playlist.items[current], 0) catch {
        e.list_mutex.unlock();
        return -2;
    };
    e.playlist.append(e.allocator, copy) catch {
        e.list_mutex.unlock();
        e.allocator.free(copy);
        return -2;
    };
    const idx: i32 = @intCast(e.playlist.items.len - 1);
    e.list_mutex.unlock();
    return idx;
}

/// Gira la cola: la pista actual pasa al final. Devuelve el numero de entradas.
export fn ch_engine_queue_rotate(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const n = e.playlist.items.len;
    if (n < 2) {
        e.list_mutex.unlock();
        return @intCast(n);
    }
    const current = e.audibleIndex() orelse e.queue_index;
    if (current >= n) {
        e.list_mutex.unlock();
        return @intCast(n);
    }
    // Mover la pista actual al final.
    const item = e.playlist.orderedRemove(current);
    e.playlist.append(e.allocator, item) catch {
        e.list_mutex.unlock();
        return @intCast(n);
    };
    e.queue_index = @intCast(n - 1);
    e.list_mutex.unlock();
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    return @intCast(n);
}

/// Cuenta cuantas pistas de la cola tienen la extension `ext` (".flac", ...).
export fn ch_engine_queue_count_ext(self: ?*Engine, ext: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (ext == null) return 0;
    const x = std.mem.span(ext);
    var count: i32 = 0;
    e.list_mutex.lock();
    for (e.playlist.items) |item| {
        if (std.mem.endsWith(u8, item, x)) count += 1;
    }
    e.list_mutex.unlock();
    return count;
}

/// Devuelve la ruta de la pista `index` de la cola ("" si no existe).
export fn ch_engine_queue_path(self: ?*Engine, index: i32) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (index < 0) return @ptrCast("");
    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    if (index >= @as(i32, @intCast(e.playlist.items.len))) return @ptrCast("");
    return @ptrCast(e.playlist.items[@intCast(index)].ptr);
}

/// Devolve el indice de la pista que suena ahora (o -1).
export fn ch_engine_queue_current_index(self: ?*Engine) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    const idx = e.audibleIndex() orelse e.queue_index;
    return @intCast(idx);
}

/// Titulo de la pista `index` de la cola ("" si no se puede leer).
export fn ch_engine_queue_title(self: ?*Engine, index: i32) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (index < 0) return @ptrCast("");
    e.list_mutex.lock();
    const path: ?[:0]u8 = if (index < @as(i32, @intCast(e.playlist.items.len))) e.playlist.items[@intCast(index)] else null;
    e.list_mutex.unlock();
    return tagToTls(path.?, "title");
}

/// Copia un tag de `path` al buffer TLS, cerrando el decodificador despues de
/// copiar (los punteros de ch_decode_* no sobreviven a ch_decode_close).
fn tagToTls(path: [*:0]const u8, key: [*:0]const u8) [*c]const u8 {
    const d = ch_decode_open(path, SAMPLE_RATE, CHANNELS) orelse return @ptrCast("");
    const v = ch_decode_tag(d, key);
    const copy = copyTls(std.mem.span(v));
    ch_decode_close(d);
    return copy;
}

fn copyTls(s: []const u8) [*c]const u8 {
    const buf = &tls_queue_meta;
    const n = @min(s.len, buf.len - 1);
    @memcpy(buf[0..n], s[0..n]);
    buf[n] = 0;
    return @ptrCast(&tls_queue_meta);
}

var tls_queue_meta: [1024]u8 = std.mem.zeroes([1024]u8);

/// Artista de la pista `index` de la cola ("" si no se puede leer).
export fn ch_engine_queue_artist(self: ?*Engine, index: i32) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (index < 0) return @ptrCast("");
    e.list_mutex.lock();
    const path: ?[:0]u8 = if (index < @as(i32, @intCast(e.playlist.items.len))) e.playlist.items[@intCast(index)] else null;
    e.list_mutex.unlock();
    return tagToTls(path.?, "artist");
}

/// Album de la pista `index` de la cola ("" si no se puede leer).
export fn ch_engine_queue_album(self: ?*Engine, index: i32) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (index < 0) return @ptrCast("");
    e.list_mutex.lock();
    const path: ?[:0]u8 = if (index < @as(i32, @intCast(e.playlist.items.len))) e.playlist.items[@intCast(index)] else null;
    e.list_mutex.unlock();
    return tagToTls(path.?, "album");
}

/// Duracion de la pista `index` de la cola en segundos (-1 si no se puede leer).
export fn ch_engine_queue_duration(self: ?*Engine, index: i32) f64 {
    const e = self orelse return -1;
    if (index < 0) return -1;
    e.list_mutex.lock();
    const path: ?[:0]u8 = if (index < @as(i32, @intCast(e.playlist.items.len))) e.playlist.items[@intCast(index)] else null;
    e.list_mutex.unlock();
    const p = path orelse return -1;
    if (ch_decode_open(p.ptr, SAMPLE_RATE, CHANNELS)) |d| {
        const dur = ch_decode_duration(d);
        ch_decode_close(d);
        return dur;
    }
    return -1;
}

/// Numero de caratulas de la pista `index` de la cola (-1 si no se puede leer).
export fn ch_engine_queue_cover_count(self: ?*Engine, index: i32) i32 {
    const e = self orelse return -1;
    if (index < 0) return -1;
    e.list_mutex.lock();
    const path: ?[:0]u8 = if (index < @as(i32, @intCast(e.playlist.items.len))) e.playlist.items[@intCast(index)] else null;
    e.list_mutex.unlock();
    const p = path orelse return -1;
    if (ch_decode_open(p.ptr, SAMPLE_RATE, CHANNELS)) |d| {
        const n = ch_decode_cover_count(d);
        ch_decode_close(d);
        return @intCast(n);
    }
    return -1;
}

/// Genero de la pista `index` de la cola ("" si no se puede leer).
export fn ch_engine_queue_genre(self: ?*Engine, index: i32) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (index < 0) return @ptrCast("");
    e.list_mutex.lock();
    const path: ?[:0]u8 = if (index < @as(i32, @intCast(e.playlist.items.len))) e.playlist.items[@intCast(index)] else null;
    e.list_mutex.unlock();
    return tagToTls(path.?, "genre");
}

/// Fecha de la pista `index` de la cola ("" si no se puede leer).
export fn ch_engine_queue_date(self: ?*Engine, index: i32) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (index < 0) return @ptrCast("");
    e.list_mutex.lock();
    const path: ?[:0]u8 = if (index < @as(i32, @intCast(e.playlist.items.len))) e.playlist.items[@intCast(index)] else null;
    e.list_mutex.unlock();
    return tagToTls(path.?, "date");
}

/// Compositor de la pista `index` de la cola ("" si no se puede leer).
export fn ch_engine_queue_composer(self: ?*Engine, index: i32) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (index < 0) return @ptrCast("");
    e.list_mutex.lock();
    const path: ?[:0]u8 = if (index < @as(i32, @intCast(e.playlist.items.len))) e.playlist.items[@intCast(index)] else null;
    e.list_mutex.unlock();
    return tagToTls(path.?, "composer");
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

/// Ruta de la pista `index` de la cola, o "" si no existe. Valida hasta que
/// cambie la cola: la UI debe copiarla, no guardar el puntero.
export fn ch_engine_queue_item(self: ?*Engine, index: i32) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (index < 0) return @ptrCast("");
    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    const i: usize = @intCast(index);
    if (i >= e.playlist.items.len) return @ptrCast("");
    return e.playlist.items[i].ptr;
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

/// Elimina de la cola las rutas que ya no existen en disco. Devuelve el numero
/// de entradas eliminadas.
export fn ch_engine_queue_prune(self: ?*Engine) i32 {
    const e = self orelse return -1;
    var removed: i32 = 0;
    e.list_mutex.lock();
    var i: usize = 0;
    while (i < e.playlist.items.len) {
        const path = e.playlist.items[i];
        const exists = blk: {
            var st: std.c.Stat = undefined;
            break :blk std.c.stat(path.ptr, &st) == 0;
        };
        if (!exists) {
            e.allocator.free(path);
            _ = e.playlist.orderedRemove(i);
            removed += 1;
        } else {
            i += 1;
        }
    }
    e.list_mutex.unlock();
    if (removed > 0) {
        e.pushEvent(EV_QUEUE, removed, 0, 0);
        e.order.clearRetainingCapacity();
        e.order_pos = 0;
    }
    return removed;
}

/// Elimina duplicados de la cola (misma ruta). Devuelve el numero eliminado.
export fn ch_engine_queue_dedup(self: ?*Engine) i32 {
    const e = self orelse return -1;
    var removed: i32 = 0;
    e.list_mutex.lock();
    var i: usize = 0;
    while (i < e.playlist.items.len) {
        var dup = false;
        var j: usize = 0;
        while (j < i) : (j += 1) {
            if (std.mem.eql(u8, e.playlist.items[j], e.playlist.items[i])) {
                dup = true;
                break;
            }
        }
        if (dup) {
            e.allocator.free(e.playlist.items[i]);
            _ = e.playlist.orderedRemove(i);
            removed += 1;
        } else {
            i += 1;
        }
    }
    e.list_mutex.unlock();
    if (removed > 0) {
        e.pushEvent(EV_QUEUE, removed, 0, 0);
        e.order.clearRetainingCapacity();
        e.order_pos = 0;
    }
    return removed;
}

/// Favoritos: lista persistente de rutas (una por linea) en un archivo.
export fn ch_engine_favorites_add(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    const p = std.mem.span(path);
    if (e.favorites.items.len >= 4096) return -2;
    for (e.favorites.items) |f| {
        if (std.mem.eql(u8, f, p)) return 0;
    }
    const copy = e.allocator.dupe(u8, p) catch return -2;
    e.favorites.append(e.allocator, copy) catch {
        e.allocator.free(copy);
        return -2;
    };
    return 0;
}

export fn ch_engine_favorites_remove(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return 0;
    const p = std.mem.span(path);
    var i: usize = 0;
    while (i < e.favorites.items.len) {
        if (std.mem.eql(u8, e.favorites.items[i], p)) {
            e.allocator.free(e.favorites.items[i]);
            _ = e.favorites.orderedRemove(i);
            return 0;
        }
        i += 1;
    }
    return 0;
}

export fn ch_engine_favorites_count(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return @intCast(e.favorites.items.len);
}

export fn ch_engine_favorites_path(self: ?*Engine, index: i32) [*c]const u8 {
    const e = self orelse return @ptrCast("");
    if (index < 0 or index >= @as(i32, @intCast(e.favorites.items.len))) return @ptrCast("");
    return @ptrCast(e.favorites.items[@intCast(index)].ptr);
}

/// Guarda los favoritos en un archivo de texto (una ruta por linea).
export fn ch_engine_favorites_save(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);
    for (e.favorites.items) |f| {
        buf.appendSlice(e.allocator, f) catch return -2;
        buf.append(e.allocator, '\n') catch return -2;
    }
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Carga los favoritos desde un archivo de texto.
export fn ch_engine_favorites_load(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var size: u64 = 0;
    const raw = ch_file_read_all(path, &size) orelse return -2;
    defer ch_file_free(raw);
    var it = std.mem.splitScalar(u8, raw[0..@intCast(size)], '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const copy = e.allocator.dupe(u8, line) catch continue;
        e.favorites.append(e.allocator, copy) catch {
            e.allocator.free(copy);
        };
    }
    return 0;
}

/// Exporta los favoritos a una playlist M3U.
export fn ch_engine_favorites_export_m3u(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);
    buf.appendSlice(e.allocator, "#EXTM3U\n") catch return -2;
    for (e.favorites.items) |f| {
        buf.appendSlice(e.allocator, f) catch return -2;
        buf.append(e.allocator, '\n') catch return -2;
    }
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Deja en la cola solo las pistas cuya ruta empieza por `dir`. Devuelve el
/// numero de entradas eliminadas.
export fn ch_engine_queue_filter_dir(self: ?*Engine, dir: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (dir == null) return -1;
    const d = std.mem.span(dir);
    var removed: i32 = 0;
    e.list_mutex.lock();
    var i: usize = 0;
    while (i < e.playlist.items.len) {
        if (!std.mem.startsWith(u8, e.playlist.items[i], d)) {
            e.allocator.free(e.playlist.items[i]);
            _ = e.playlist.orderedRemove(i);
            removed += 1;
        } else {
            i += 1;
        }
    }
    e.list_mutex.unlock();
    if (removed > 0) {
        e.pushEvent(EV_QUEUE, removed, 0, 0);
        e.order.clearRetainingCapacity();
        e.order_pos = 0;
    }
    return removed;
}

/// Elimina duplicados por contenido (tamano + hash FNV del archivo). Mas fuerte
/// que por ruta. Devuelve el numero eliminado.
export fn ch_engine_queue_dedup_hash(self: ?*Engine) i32 {
    const e = self orelse return -1;
    var removed: i32 = 0;
    e.list_mutex.lock();
    var i: usize = 0;
    while (i < e.playlist.items.len) {
        const info_i = fileHash(e.playlist.items[i]);
        var dup = false;
        if (info_i) |hi| {
            var j: usize = 0;
            while (j < i) : (j += 1) {
                if (fileHash(e.playlist.items[j])) |hj| {
                    if (hj.size == hi.size and hj.hash == hi.hash) {
                        dup = true;
                        break;
                    }
                }
            }
        }
        if (dup) {
            e.allocator.free(e.playlist.items[i]);
            _ = e.playlist.orderedRemove(i);
            removed += 1;
        } else {
            i += 1;
        }
    }
    e.list_mutex.unlock();
    if (removed > 0) {
        e.pushEvent(EV_QUEUE, removed, 0, 0);
        e.order.clearRetainingCapacity();
        e.order_pos = 0;
    }
    return removed;
}

const FileHash = struct { size: u64, hash: u64 };

/// Hash rapido del contenido (FNV-1a) + tamano. Devuelve null si no se puede leer.
fn fileHash(path: []const u8) ?FileHash {
    var size: u64 = 0;
    const raw = ch_file_read_all(path.ptr, &size) orelse return null;
    defer ch_file_free(raw);
    var h: u64 = 1469598103934665603;
    const data = raw[0..@intCast(size)];
    for (data) |b| {
        h ^= b;
        h *%= 1099511628211;
    }
    return .{ .size = size, .hash = h };
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

/// Salta `delta_s` segundos desde la posicion actual (puede ser negativo).
export fn ch_engine_seek_relative(self: ?*Engine, delta_s: f64) i32 {
    const e = self orelse return -1;
    const pos = ch_engine_position(e);
    if (pos < 0) return -2;
    var target = pos + delta_s;
    if (target < 0) target = 0;
    const dur = ch_engine_duration(e);
    if (dur > 0 and target > dur) target = dur;
    return ch_engine_seek(e, target);
}

/// Alterna entre reproducir y pausar. Devuelve 1 si queda reproduciendo.
export fn ch_engine_toggle_play(self: ?*Engine) i32 {
    const e = self orelse return -1;
    if (ch_engine_is_playing(e) != 0) {
        return ch_engine_pause(e);
    }
    return ch_engine_play(e);
}

/// Bucle A-B en segundos (A < B). Al llegar a B vuelve a A.
export fn ch_engine_set_ab_loop(self: ?*Engine, a_seconds: f64, b_seconds: f64) i32 {
    const e = self orelse return -1;
    if (!(a_seconds >= 0) or !(b_seconds > a_seconds)) return -2;
    const start: usize = @intFromFloat(a_seconds * SAMPLE_RATE);
    const end: usize = @intFromFloat(b_seconds * SAMPLE_RATE);
    @atomicStore(usize, &e.ab_start, start, .release);
    @atomicStore(usize, &e.ab_end, end, .release);
    return 0;
}

export fn ch_engine_clear_ab_loop(self: ?*Engine) i32 {
    const e = self orelse return -1;
    @atomicStore(usize, &e.ab_end, NO_SEEK, .release);
    @atomicStore(usize, &e.ab_start, NO_SEEK, .release);
    return 0;
}

/// Devuelve 1 si hay bucle A-B y escribe A y B (segundos).
export fn ch_engine_ab_loop(self: ?*Engine, a_seconds: ?*f64, b_seconds: ?*f64) i32 {
    const e = self orelse return 0;
    const end = @atomicLoad(usize, &e.ab_end, .acquire);
    if (end == NO_SEEK) return 0;
    if (a_seconds) |p| p.* = @as(f64, @floatFromInt(@atomicLoad(usize, &e.ab_start, .acquire))) / SAMPLE_RATE;
    if (b_seconds) |p| p.* = @as(f64, @floatFromInt(end)) / SAMPLE_RATE;
    return 1;
}

/// Crossfeed Bauer para auriculares: alimentacion cruzada con paso bajo de
/// 700 Hz y retardo de 250 us. `strength` 0..1 (0.5 = moderado).
export fn ch_engine_set_crossfeed(self: ?*Engine, enabled: i32, strength: f32) i32 {
    const e = self orelse return -1;
    e.dsp.crossfeed.set(enabled != 0, strength);
    return 0;
}

export fn ch_engine_crossfeed(self: ?*Engine, strength: ?*f32) i32 {
    const e = self orelse return 0;
    if (strength) |p| p.* = e.dsp.crossfeed.level();
    return if (e.dsp.crossfeed.isEnabled()) 1 else 0;
}

/// Modo noche: compresor suave que sube los pasajes flojos y doma los picos
/// (va antes del limitador). `amount` 0..1; devuelve 1 si esta encendido.
export fn ch_engine_set_night_mode(self: ?*Engine, enabled: i32, amount: f32) i32 {
    const e = self orelse return -1;
    e.dsp.night.set(enabled != 0, amount);
    return 0;
}

export fn ch_engine_night_mode(self: ?*Engine, amount: ?*f32) i32 {
    const e = self orelse return 0;
    if (amount) |p| p.* = e.dsp.night.amount();
    return if (e.dsp.night.isEnabled()) 1 else 0;
}

/// Salida S16 con dither TPDF (±1 LSB). Apagada por defecto: se entrega f32.
export fn ch_engine_set_s16_output(self: ?*Engine, enabled: i32) i32 {
    const e = self orelse return -1;
    e.s16_output = enabled != 0;
    if (e.audio) |audio| {
        return ch_audio_set_s16(audio, if (e.s16_output) 1 else 0);
    }
    return 0;
}

export fn ch_engine_s16_output(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return if (e.s16_output) 1 else 0;
}

/// Mono (1) o estereo (0).
export fn ch_engine_set_mono(self: ?*Engine, enabled: i32) i32 {
    const e = self orelse return -1;
    // Un solo mando para los canales: 0 estereo, 1 mono, 2 intercambiados.
    @atomicStore(u32, &e.chan_mode, if (enabled != 0) 1 else 0, .monotonic);
    return 0;
}

export fn ch_engine_mono(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return if (@atomicLoad(u32, &e.chan_mode, .monotonic) == 1) 1 else 0;
}

/// Balance: -1 solo izquierda, 0 centrado, +1 solo derecha.
export fn ch_engine_set_balance(self: ?*Engine, balance: f32) i32 {
    const e = self orelse return -1;
    @atomicStore(u32, &e.balance_bits, @bitCast(std.math.clamp(balance, -1, 1)), .monotonic);
    return 0;
}

export fn ch_engine_balance(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return @as(f32, @bitCast(@atomicLoad(u32, &e.balance_bits, .monotonic)));
}

/// Ganancia manual (dB) aplicada despues del volumen y ReplayGain. -24 .. +24.
export fn ch_engine_set_gain_db(self: ?*Engine, gain_db: f32) i32 {
    const e = self orelse return -1;
    const clamped = std.math.clamp(gain_db, -24, 24);
    @atomicStore(u32, &e.gain_db_bits, @bitCast(clamped), .monotonic);
    return 0;
}

export fn ch_engine_gain_db(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return @as(f32, @bitCast(@atomicLoad(u32, &e.gain_db_bits, .monotonic)));
}

/// Ancho estereo: 0 = mono, 1 = normal, 2 = amplio (matriz Mid/Side).
export fn ch_engine_set_stereo_width(self: ?*Engine, width: f32) i32 {
    const e = self orelse return -1;
    e.dsp.enhancer.setWidth(width);
    return 0;
}

export fn ch_engine_stereo_width(self: ?*Engine) f32 {
    const e = self orelse return 1;
    return e.dsp.enhancer.width();
}

/// Potenciador estereo: ancho (0..2) y punch de graves (0..1) de una vez.
export fn ch_engine_set_stereo_enhance(self: ?*Engine, width: f32, bass_punch: f32) i32 {
    const e = self orelse return -1;
    e.dsp.enhancer.set(width, bass_punch);
    return 0;
}

export fn ch_engine_bass_punch(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.dsp.enhancer.punch();
}

/// Audio 9D espacial: rotacion azimutal continua para auriculares.
/// `speed_hz` = vueltas por segundo (0.05..2) y `depth` 0..1.
export fn ch_engine_set_9d(self: ?*Engine, enabled: i32, speed_hz: f32, depth: f32) i32 {
    const e = self orelse return -1;
    e.dsp.spatial.set(enabled != 0, speed_hz, depth);
    if (enabled == 0) e.dsp.spatial.reset();
    return 0;
}

export fn ch_engine_9d_enabled(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return if (e.dsp.spatial.isEnabled()) 1 else 0;
}

export fn ch_engine_9d_speed(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.dsp.spatial.speed();
}

export fn ch_engine_9d_depth(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.dsp.spatial.depth();
}

/// Modo karaoke: atenuacion del centro por encima de ~130 Hz (0 = apagado).
export fn ch_engine_set_vocal_cut(self: ?*Engine, amount: f32) i32 {
    const e = self orelse return -1;
    e.dsp.vocal.set(amount);
    return 0;
}

export fn ch_engine_vocal_cut(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.dsp.vocal.amount();
}

/// Recorte automatico de silencio al abrir cada pista (dBFS).
export fn ch_engine_set_trim_silence(self: ?*Engine, enabled: i32, threshold_db: f32) i32 {
    const e = self orelse return -1;
    e.trim_enabled = enabled != 0;
    e.trim_threshold_db = std.math.clamp(threshold_db, -90, -20);
    return 0;
}

export fn ch_engine_trim_silence(self: ?*Engine, threshold_db: ?*f32) i32 {
    const e = self orelse return 0;
    if (threshold_db) |p| p.* = e.trim_threshold_db;
    return if (e.trim_enabled) 1 else 0;
}

/// Fundido de salida al llegar al final de la pista (segundos, 0 = corte).
export fn ch_engine_set_fade_out(self: ?*Engine, seconds: f32) i32 {
    const e = self orelse return -1;
    e.fade_out_s = std.math.clamp(seconds, 0, 30);
    return 0;
}

export fn ch_engine_fade_out(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.fade_out_s;
}

/// Fundido de entrada al abrir pista (segundos, 0 = 8 ms por defecto).
export fn ch_engine_set_fade_in(self: ?*Engine, seconds: f32) i32 {
    const e = self orelse return -1;
    e.fade_in_s = std.math.clamp(seconds, 0, 30);
    return 0;
}

export fn ch_engine_fade_in(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.fade_in_s;
}

/// Silencio entre pistas en segundos (0 = sin pausa, max 30).
export fn ch_engine_set_gap(self: ?*Engine, seconds: f32) i32 {
    const e = self orelse return -1;
    e.gap_s = std.math.clamp(seconds, 0, 30);
    if (e.gap_s == 0) e.gap_wait_frames = 0;
    return 0;
}

export fn ch_engine_gap(self: ?*Engine) f32 {
    const e = self orelse return 0;
    return e.gap_s;
}

/// Efecto 8D/espacial: auto-paneo giratorio. `speed` en vueltas/seg (0.05..2),
/// `depth` 0..1. `enabled != 0` lo activa.
export fn ch_engine_set_8d(self: ?*Engine, enabled: i32, speed: f32, depth: f32) i32 {
    const e = self orelse return -1;
    e.spatial_enabled = enabled != 0;
    @atomicStore(u32, &e.spatial_speed_bits, @bitCast(std.math.clamp(speed, 0.05, 2)), .monotonic);
    @atomicStore(u32, &e.spatial_depth_bits, @bitCast(std.math.clamp(depth, 0, 1)), .monotonic);
    return 0;
}

export fn ch_engine_8d(self: ?*Engine, speed: ?*f32, depth: ?*f32) i32 {
    const e = self orelse return 0;
    if (speed) |p| p.* = @as(f32, @bitCast(@atomicLoad(u32, &e.spatial_speed_bits, .monotonic)));
    if (depth) |p| p.* = @as(f32, @bitCast(@atomicLoad(u32, &e.spatial_depth_bits, .monotonic)));
    return if (e.spatial_enabled) 1 else 0;
}

/// Reverberacion esterea. `mix` 0..1 (0 = seco).
export fn ch_engine_set_reverb(self: ?*Engine, enabled: i32, mix: f32) i32 {
    const e = self orelse return -1;
    e.reverb_enabled = enabled != 0;
    @atomicStore(u32, &e.reverb_mix_bits, @bitCast(std.math.clamp(mix, 0, 1)), .monotonic);
    return 0;
}

export fn ch_engine_reverb(self: ?*Engine, mix: ?*f32) i32 {
    const e = self orelse return 0;
    if (mix) |p| p.* = @as(f32, @bitCast(@atomicLoad(u32, &e.reverb_mix_bits, .monotonic)));
    return if (e.reverb_enabled) 1 else 0;
}

/// Compresor dinamico. `threshold_db` (-60..0), `ratio` (1..20), attack/release
/// en segundos. `enabled != 0` lo activa.
export fn ch_engine_set_compressor(self: ?*Engine, enabled: i32, threshold_db: f32, ratio: f32, attack_s: f32, release_s: f32) i32 {
    const e = self orelse return -1;
    e.comp_enabled = enabled != 0;
    @atomicStore(u32, &e.comp_threshold_bits, @bitCast(std.math.clamp(threshold_db, -60, 0)), .monotonic);
    @atomicStore(u32, &e.comp_ratio_bits, @bitCast(std.math.clamp(ratio, 1, 20)), .monotonic);
    @atomicStore(u32, &e.comp_attack_bits, @bitCast(std.math.clamp(attack_s, 0.001, 1)), .monotonic);
    @atomicStore(u32, &e.comp_release_bits, @bitCast(std.math.clamp(release_s, 0.01, 2)), .monotonic);
    return 0;
}

export fn ch_engine_compressor(self: ?*Engine, threshold_db: ?*f32, ratio: ?*f32) i32 {
    const e = self orelse return 0;
    if (threshold_db) |p| p.* = @as(f32, @bitCast(@atomicLoad(u32, &e.comp_threshold_bits, .monotonic)));
    if (ratio) |p| p.* = @as(f32, @bitCast(@atomicLoad(u32, &e.comp_ratio_bits, .monotonic)));
    return if (e.comp_enabled) 1 else 0;
}

/// EQ parametrico de 4 bandas. `band` 0..3. `type`: 0 peaking, 1 low shelf,
/// 2 high shelf. `freq` Hz, `gain_db`, `q`.
export fn ch_engine_set_peq(self: ?*Engine, band: i32, enabled: i32, ptype: i32, freq: f32, gain_db: f32, q: f32) i32 {
    const e = self orelse return -1;
    if (band < 0 or band >= 4 or ptype < 0 or ptype > 2) return -2;
    const bi: usize = @intCast(band);
    var bp = e.peq[bi];
    bp.enabled = enabled != 0;
    bp.type = switch (ptype) {
        0 => .peaking,
        1 => .low_shelf,
        else => .high_shelf,
    };
    bp.freq = std.math.clamp(freq, 20, 20000);
    bp.gain_db = std.math.clamp(gain_db, -18, 18);
    bp.q = std.math.clamp(q, 0.1, 10);
    bp.recompute();
    e.peq[bi] = bp;
    e.peq_enabled = true;
    return 0;
}

export fn ch_engine_peq(self: ?*Engine, band: i32, ptype: ?*i32, freq: ?*f32, gain_db: ?*f32, q: ?*f32) i32 {
    const e = self orelse return 0;
    if (band < 0 or band >= 4) return -2;
    const bp = e.peq[@intCast(band)];
    if (ptype) |p| p.* = switch (bp.type) {
        .peaking => 0,
        .low_shelf => 1,
        .high_shelf => 2,
    };
    if (freq) |p| p.* = bp.freq;
    if (gain_db) |p| p.* = bp.gain_db;
    if (q) |p| p.* = bp.q;
    return if (bp.enabled) 1 else 0;
}

/// Localizacion binaural (HRTF simplificada). `angle`: -1 izquierda .. +1 derecha.
export fn ch_engine_set_hrtf(self: ?*Engine, enabled: i32, angle: f32) i32 {
    const e = self orelse return -1;
    e.hrtf_enabled = enabled != 0;
    @atomicStore(u32, &e.hrtf_angle_bits, @bitCast(std.math.clamp(angle, -1, 1)), .monotonic);
    return 0;
}

export fn ch_engine_hrtf(self: ?*Engine, angle: ?*f32) i32 {
    const e = self orelse return 0;
    if (angle) |p| p.* = @as(f32, @bitCast(@atomicLoad(u32, &e.hrtf_angle_bits, .monotonic)));
    return if (e.hrtf_enabled) 1 else 0;
}

/// Estadisticas de escucha: numero de reproducciones y segundos totales.
export fn ch_engine_stats(self: ?*Engine, play_count: ?*u64, listen_seconds: ?*f64) i32 {
    const e = self orelse return -1;
    e.stats_lock.lock();
    const pc = e.play_count;
    const frames = e.listen_frames;
    e.stats_lock.unlock();
    if (play_count) |p| p.* = pc;
    if (listen_seconds) |p| p.* = @as(f64, @floatFromInt(frames)) / @as(f64, @floatFromInt(SAMPLE_RATE));
    return 0;
}

/// Elige el escritor de etiquetas segun la extension del archivo.
fn tagWriterFor(span: []const u8) ?SetFn {
    if (std.mem.endsWith(u8, span, ".flac")) return ch_tags_set;
    if (std.mem.endsWith(u8, span, ".mp3")) return ch_tags_mp3_set;
    if (std.mem.endsWith(u8, span, ".aac")) return ch_tags_aac_set;
    if (std.mem.endsWith(u8, span, ".opus")) return ch_tags_opus_set;
    if (std.mem.endsWith(u8, span, ".ogg") or std.mem.endsWith(u8, span, ".oga")) {
        return ch_tags_ogg_set;
    }
    if (std.mem.endsWith(u8, span, ".m4a") or std.mem.endsWith(u8, span, ".m4b") or
        std.mem.endsWith(u8, span, ".m4p") or std.mem.endsWith(u8, span, ".m4v") or
        std.mem.endsWith(u8, span, ".mp4") or std.mem.endsWith(u8, span, ".alac"))
    {
        return ch_tags_mp4_set;
    }
    if (std.mem.endsWith(u8, span, ".aiff") or std.mem.endsWith(u8, span, ".aif") or
        std.mem.endsWith(u8, span, ".aifc"))
    {
        return ch_tags_aiff_set;
    }
    return null;
}

/// Escribe una etiqueta (key/value) en el archivo de la pista actual.
/// `value` NULL borra el campo. Devuelve 0 si ok.
export fn ch_engine_set_tag(self: ?*Engine, key: [*c]const u8, value: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (key == null) return -1;
    e.list_mutex.lock();
    const idx = e.queue_index;
    const path: ?[:0]u8 = if (idx < e.playlist.items.len) e.playlist.items[idx] else null;
    e.list_mutex.unlock();
    const p = path orelse return -2;
    const span: []const u8 = p;
    const w = tagWriterFor(span) orelse return -3;
    return w(p.ptr, key, value orelse @ptrCast(""));
}

/// Guarda la letra de la pista actual en un .lrc (0 si ok).
export fn ch_engine_save_lyrics(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    const p = @atomicLoad(usize, &e.played, .acquire);
    const pos = e.findSegment(p) orelse return -2;
    const ly = e.segments[pos].lyrics orelse return -2;
    return ch_lyrics_write_file(ly, path);
}

/// Desplaza la letra actual `delta_s` segundos y lo refleja en el offset.
export fn ch_engine_shift_lyrics(self: ?*Engine, delta_s: f64) i32 {
    const e = self orelse return -1;
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    const p = @atomicLoad(usize, &e.played, .acquire);
    const pos = e.findSegment(p) orelse return -2;
    const seg = &e.segments[pos];
    const ly = seg.lyrics orelse return -2;
    if (ch_lyrics_shift(ly, delta_s) != 0) return -3;
    seg.lyrics_offset += delta_s * 1000.0;
    return 0;
}

/// Desplazamiento actual de la letra en ms (lo que suma [offset:]).
export fn ch_engine_lyrics_offset_ms(self: ?*Engine) f64 {
    const e = self orelse return 0;
    return e.audibleLyricsOffset();
}

/// Carga una letra LRC desde `path` para la pista actual (0 si ok).
export fn ch_engine_load_lyrics(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    const lyrics = ch_lyrics_read_file(path) orelse return -2;
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    const p = @atomicLoad(usize, &e.played, .acquire);
    const pos = e.findSegment(p) orelse {
        e.seg_lock.unlock();
        ch_lyrics_free(lyrics);
        return -2;
    };
    if (e.segments[pos].lyrics) |old| ch_lyrics_free(old);
    e.segments[pos].lyrics = lyrics;
    e.segments[pos].lyrics_offset = parseLeadingFloat(std.mem.span(ch_lyrics_offset_ms(lyrics))) orelse 0;
    return 0;
}

/// Numero de caratulas de la pista actual.
export fn ch_engine_cover_count_current(self: ?*Engine) i32 {
    const e = self orelse return 0;
    const p = @atomicLoad(usize, &e.played, .acquire);
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    if (e.findSegment(p)) |pos| return @intCast(e.segments[pos].cover_count);
    return 0;
}

/// Guarda la caratula `index` de la pista actual en `path` (0 si ok).
export fn ch_engine_save_cover_current(self: ?*Engine, index: i32, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null or index < 0) return -1;
    const p = @atomicLoad(usize, &e.played, .acquire);
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    if (e.findSegment(p)) |pos| {
        const seg = &e.segments[pos];
        const i: usize = @intCast(index);
        if (i < seg.cover_count) {
            if (seg.covers[i]) |cover| return ch_file_write_atomic(path, cover.ptr, cover.len);
        }
        return -2;
    }
    return -2;
}

/// Exporta un fragmento de `src` a WAV PCM de 16 bits.
///
/// `start_s` y `dur_s` en segundos (dur_s <= 0 = hasta el final). `channels`
/// vale 1 (mono) o 2 (estereo) y se remuestrea a `rate` Hz si difiere del
/// original. No aplica DSP: es una copia del audio decodificado.
export fn ch_engine_export_wav(self: ?*Engine, src: [*c]const u8, dst: [*c]const u8, start_s: f64, dur_s: f64, rate: i32, channels: i32) i32 {
    const e = self orelse return -1;
    if (src == null or dst == null) return -1;
    if (rate < 8000 or rate > 192000) return -1;
    if (channels != 1 and channels != 2) return -1;
    if (!(start_s >= 0)) return -1;

    const out_ch: u32 = @intCast(channels);
    const out_rate: u32 = @intCast(rate);
    const d = ch_decode_open(src, out_rate, out_ch) orelse return -2;
    defer ch_decode_close(d);

    const total = ch_decode_duration(d);
    var start_f: u64 = 0;
    if (total > 0 and start_s >= total) return -3;
    if (start_s > 0) {
        start_f = @intFromFloat(start_s * @as(f64, @floatFromInt(out_rate)));
        if (ch_decode_seek_frame(d, @intCast(start_f)) != 0) return -4;
    }

    var frames: u64 = 0;
    if (dur_s > 0) frames = @intFromFloat(dur_s * @as(f64, @floatFromInt(out_rate)));

    // WAV: cabecera de 44 bytes + PCM16 little-endian.
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(e.allocator);
    out.appendSlice(e.allocator, &std.mem.zeroes([44]u8)) catch return -5;

    // El buffer cubre 4096 frames de 2 canales: el decodificador entrega
    // muestras entrelazadas, asi que con estereo hacen falta 8192 floats.
    var buf: [8192]f32 = undefined;
    var total_frames: u64 = 0;
    while (frames == 0 or total_frames < frames) {
        const want: u64 = if (frames == 0) 4096 else @min(@as(u64, 4096), frames - total_frames);
        const got = ch_decode_read(d, &buf, want);
        if (got == 0) break;
        var i: u64 = 0;
        while (i < got * out_ch) : (i += 1) {
            var v = buf[i];
            v = std.math.clamp(v, -1.0, 1.0);
            const s: i16 = @intFromFloat(v * 32767.0);
            const bytes: [2]u8 = .{ @truncate(@as(u16, @bitCast(s))), @truncate(@as(u16, @bitCast(s)) >> 8) };
            out.appendSlice(e.allocator, &bytes) catch return -5;
        }
        total_frames += got;
    }

    const data_len: u32 = @intCast(out.items.len - 44);
    const byte_rate: u32 = out_rate * out_ch * 2;
    const block_align: u16 = @intCast(out_ch * 2);
    // 16 = tamano del subchunk "fmt " (16 para PCM), 20 = formato (1 = PCM),
    // 22 = canales, 24 = rate, 28 = byte rate, 32 = block align,
    // 34 = bits por muestra, 36 = "data", 40 = tamano de datos.
    wr32(out.items[16..20], 16);
    wr16(out.items[20..22], 1);
    wr16(out.items[22..24], @intCast(out_ch));
    wr32(out.items[24..28], out_rate);
    wr32(out.items[28..32], byte_rate);
    wr16(out.items[32..34], block_align);
    wr16(out.items[34..36], 16);
    wr32(out.items[4..8], 36 + data_len);
    wr32(out.items[40..44], data_len);
    @memcpy(out.items[0..4], "RIFF");
    @memcpy(out.items[8..12], "WAVE");
    @memcpy(out.items[12..16], "fmt ");
    @memcpy(out.items[36..40], "data");

    return ch_file_write_atomic(dst, out.items.ptr, out.items.len);
}

fn wr16(b: []u8, v: u16) void {
    b[0] = @truncate(v);
    b[1] = @truncate(v >> 8);
}

fn wr32(b: []u8, v: u32) void {
    b[0] = @truncate(v);
    b[1] = @truncate(v >> 8);
    b[2] = @truncate(v >> 16);
    b[3] = @truncate(v >> 24);
}

/// Busca un preset de EQ por nombre (sin distinguir mayusculas). Devuelve su
/// indice o -1 si no existe.
export fn ch_engine_eq_preset_find(name: [*c]const u8) i32 {
    if (name == null) return -1;
    const span = std.mem.span(name);
    for (eq.PRESETS, 0..) |p, i| {
        if (std.ascii.eqlIgnoreCase(p.name, span)) return @intCast(i);
    }
    return -1;
}

/// Escribe el BPM detectado de `path` como tag (0 si ok).
export fn ch_engine_write_bpm(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var bpm: f64 = 0;
    if (ch_bpm_detect(path, &bpm) != 0) return -2;
    if (bpm < 20 or bpm > 400) return -3;
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrintSentinel(&buf, "{d:.0}", .{bpm}, 0) catch return -3;
    const path_span = std.mem.span(path);
    const w = tagWriterFor(path_span) orelse
        return e.fail("BPM solo soporta FLAC, MP3, M4A, AAC, AIFF, Ogg y Opus", -4);
    return w(path, "BPM", s.ptr);
}

/// Mide la sonoridad de la pista cargada (LUFS y pico de muestra).
export fn ch_engine_analyze_current(self: ?*Engine, lufs: ?*f64, peak_db: ?*f64) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const idx = e.queue_index;
    const path: ?[:0]u8 = if (idx < e.playlist.items.len) e.playlist.items[idx] else null;
    e.list_mutex.unlock();
    const p = path orelse return -2;

    var result: ChLoudness = undefined;
    if (ch_loudness_scan(p.ptr, &result) != 0) return -3;
    if (lufs) |out| out.* = result.integrated_lufs;
    if (peak_db) |out| out.* = result.sample_peak_dbfs;
    return 0;
}

/// Normaliza la pista cargada a `target_lufs` ajustando la ganancia manual.
/// Devuelve 0 y escribe en `applied_db` la ganancia aplicada.
export fn ch_engine_normalize_current(self: ?*Engine, target_lufs: f64, applied_db: ?*f64) i32 {
    const e = self orelse return -1;
    var lufs: f64 = 0;
    if (ch_engine_analyze_current(e, &lufs, null) != 0) return -2;
    const gain = std.math.clamp(target_lufs - lufs, -24, 24);
    _ = ch_engine_set_gain_db(e, @floatCast(gain));
    if (applied_db) |out| out.* = gain;
    return 0;
}

/// Calcula la sonoridad integrada de todo el album de la pista cargada
/// (promedio de LUFS de las pistas con el mismo album). Devuelve 0 y escribe
/// en `lufs_out`.
export fn ch_engine_album_loudness(self: ?*Engine, lufs_out: ?*f64) i32 {
    const e = self orelse return -1;
    e.list_mutex.lock();
    const count = e.playlist.items.len;
    e.list_mutex.unlock();
    if (count == 0) return -2;

    var sum: f64 = 0;
    var n: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var result: ChLoudness = undefined;
        if (ch_loudness_scan(e.playlist.items[i].ptr, &result) != 0) continue;
        sum += result.integrated_lufs;
        n += 1;
    }
    if (n == 0) return -3;
    const avg = sum / @as(f64, @floatFromInt(n));
    if (lufs_out) |out| out.* = avg;
    return 0;
}

/// Normaliza todo el album a `target_lufs` (aplica la ganancia manual a la
/// pista actual segun el promedio del album). Devuelve la ganancia aplicada.
export fn ch_engine_normalize_album(self: ?*Engine, target_lufs: f64, applied_db: ?*f64) i32 {
    const e = self orelse return -1;
    var lufs: f64 = 0;
    if (ch_engine_album_loudness(e, &lufs) != 0) return -2;
    const gain = std.math.clamp(target_lufs - lufs, -24, 24);
    _ = ch_engine_set_gain_db(e, @floatCast(gain));
    if (applied_db) |out| out.* = gain;
    return 0;
}

/// Guarda la caratula `index` de la pista audible en `path`. 0 si ok.
export fn ch_engine_save_cover(self: ?*Engine, index: i32, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null or index < 0) return -1;
    const p = @atomicLoad(usize, &e.played, .acquire);
    e.seg_lock.lock();
    defer e.seg_lock.unlock();
    if (e.findSegment(p)) |pos| {
        const seg = &e.segments[pos];
        const i: usize = @intCast(index);
        if (i < seg.cover_count) {
            if (seg.covers[i]) |cover| {
                return ch_file_write_atomic(path, cover.ptr, cover.len);
            }
        }
    }
    return -2;
}

/// Medidores desde la ultima llamada: picos por canal y RMS (dBFS).
export fn ch_engine_meter(self: ?*Engine, peak_l_db: ?*f32, peak_r_db: ?*f32, rms_db: ?*f32) i32 {
    const e = self orelse return -1;
    e.meter_lock.lock();
    const pl = e.meter_peak_l;
    const pr = e.meter_peak_r;
    const sum = e.meter_sum;
    const n = e.meter_frames;
    e.meter_peak_l = 0;
    e.meter_peak_r = 0;
    e.meter_sum = 0;
    e.meter_frames = 0;
    e.meter_lock.unlock();

    if (peak_l_db) |p| p.* = if (pl > 1e-7) 20.0 * std.math.log10(pl) else -120.0;
    if (peak_r_db) |p| p.* = if (pr > 1e-7) 20.0 * std.math.log10(pr) else -120.0;
    if (rms_db) |p| {
        const mean = if (n > 0) sum / @as(f64, @floatFromInt(n)) else 0;
        p.* = if (mean > 1e-12) @floatCast(10.0 * std.math.log10(mean)) else -120.0;
    }
    return 0;
}

export fn ch_engine_set_volume(self: ?*Engine, volume: f32) i32 {
    const e = self orelse return -1;
    const clamped = std.math.clamp(volume, 0, 1);
    @atomicStore(u32, &e.volume_bits, @bitCast(clamped), .monotonic);
    return 0;
}

export fn ch_engine_volume(self: ?*Engine) f32 {
    const e = self orelse return 1.0;
    return @as(f32, @bitCast(@atomicLoad(u32, &e.volume_bits, .monotonic)));
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

/// 0 = estereo, 1 = mono, 2 = intercambiados, 3 = solo izquierdo,
/// 4 = solo derecho, 5 = karaoke (cancela la voz centrada).
export fn ch_engine_set_channel_mode(self: ?*Engine, mode: i32) i32 {
    const e = self orelse return -1;
    if (mode < 0 or mode > 5) return e.fail("modo de canales inválido", -2);
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

fn jsonSkipValueSep(data: []const u8, pos: *usize) void {
    while (pos.* < data.len) : (pos.* += 1) {
        switch (data[pos.*]) {
            ' ', '\t', '\n', '\r', ':', ',' => {},
            else => return,
        }
    }
}

fn jsonNumber(data: []const u8, pos: *usize) ?f64 {
    while (pos.* < data.len) : (pos.* += 1) {
        const c = data[pos.*];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r' or
            c == ':' or c == ',' or c == '[' or c == ']') continue;
        break;
    }
    const start = pos.*;
    while (pos.* < data.len) : (pos.* += 1) {
        const c = data[pos.*];
        if ((c >= '0' and c <= '9') or c == '-' or c == '+' or c == '.' or c == 'e' or c == 'E') continue;
        break;
    }
    if (pos.* == start) return null;
    return std.fmt.parseFloat(f64, data[start..pos.*]) catch null;
}

/// Guarda el EQ actual (preamp + 36 bandas) en un JSON.
export fn ch_engine_save_eq_preset(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);
    buf.appendSlice(e.allocator, "{\"preamp\":") catch return -2;
    var tmp: [64]u8 = undefined;
    buf.appendSlice(e.allocator, std.fmt.bufPrint(&tmp, "{d:.2}", .{e.equalizer.preamp_db}) catch return -2) catch return -2;
    buf.appendSlice(e.allocator, ",\"gains\":[") catch return -2;
    for (e.eq_gains, 0..) |g, i| {
        if (i > 0) buf.append(e.allocator, ',') catch return -2;
        buf.appendSlice(e.allocator, std.fmt.bufPrint(&tmp, "{d:.2}", .{g}) catch return -2) catch return -2;
    }
    buf.appendSlice(e.allocator, "]}\n") catch return -2;
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Carga un preset de EQ desde un JSON guardado con ch_engine_save_eq_preset.
export fn ch_engine_load_eq_preset(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var size: u64 = 0;
    const raw = ch_file_read_all(path, &size) orelse return -2;
    defer ch_file_free(raw);
    const data = raw[0..@intCast(size)];

    var gains: [eq.BAND_COUNT]f32 = @splat(0);
    var pre: f32 = 0;
    if (std.mem.indexOf(u8, data, "\"preamp\"")) |pi| {
        var p = pi + "\"preamp\"".len;
        if (jsonNumber(data, &p)) |v| pre = @floatCast(v);
    }
    if (std.mem.indexOf(u8, data, "\"gains\"")) |gi| {
        var p = gi + "\"gains\"".len;
        while (p < data.len and data[p] != '[') p += 1;
        if (p < data.len) p += 1;
        var i: usize = 0;
        while (i < eq.BAND_COUNT) : (i += 1) {
            const v = jsonNumber(data, &p) orelse break;
            gains[i] = std.math.clamp(@as(f32, @floatCast(v)), -eq.MAX_GAIN_DB, eq.MAX_GAIN_DB);
        }
    }
    e.eq_gains = gains;
    e.equalizer.setGains(&gains);
    e.equalizer.setPreamp(pre);
    return 0;
}

/// Calcula ReplayGain (referencia -18 LUFS) y lo escribe como tags en `path`.
/// Soporta FLAC (Vorbis) y MP3 (ID3v2). No altera la reproduccion actual.
export fn ch_engine_write_replaygain(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var r: ChLoudness = undefined;
    if (ch_loudness_scan(path, &r) != 0) return -2;
    const gain = -18.0 - r.integrated_lufs;
    const peak = std.math.pow(f64, 10.0, r.sample_peak_dbfs / 20.0);
    var gbuf: [64]u8 = undefined;
    var pbuf: [64]u8 = undefined;
    // printSentinel: los escritores de tags hablan C y esperan terminador nulo.
    const gs = std.fmt.bufPrintSentinel(&gbuf, "{d:.2} dB", .{gain}, 0) catch return -3;
    const ps = std.fmt.bufPrintSentinel(&pbuf, "{d:.6}", .{peak}, 0) catch return -3;
    const span = std.mem.span(path);

    const w = tagWriterFor(span) orelse
        return e.fail("ReplayGain solo soporta FLAC, MP3, M4A, AAC, AIFF, Ogg y Opus", -4);
    const ok = w(path, "REPLAYGAIN_TRACK_GAIN", gs.ptr) == 0 and
        w(path, "REPLAYGAIN_TRACK_PEAK", ps.ptr) == 0;
    if (!ok) return e.fail("no se pudieron escribir las etiquetas", -4);
    return 0;
}

/// Exporta el espectro actual a CSV (banda,valor) con `points` bandas.
export fn ch_engine_export_spectrum_csv(self: ?*Engine, path: [*c]const u8, points: i32) i32 {
    const e = self orelse return -1;
    if (path == null or points <= 0) return -1;
    const n: usize = @min(@as(usize, @intCast(points)), 4096);
    const arr = e.allocator.alloc(f32, n) catch return -2;
    defer e.allocator.free(arr);
    if (ch_engine_spectrum(e, arr.ptr, @intCast(n)) != 0) return -3;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);
    buf.appendSlice(e.allocator, "band,value\n") catch return -2;
    var tmp: [64]u8 = undefined;
    for (arr, 0..) |v, i| {
        const line = std.fmt.bufPrint(&tmp, "{d},{d:.5}\n", .{ i, v }) catch continue;
        buf.appendSlice(e.allocator, line) catch return -2;
    }
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// BPM estimado de la pista en `path` (0 si falla).
export fn ch_bpm_detect_path(path: [*c]const u8) f64 {
    if (path == null) return 0;
    var bpm: f64 = 0;
    if (ch_bpm_detect(path, &bpm) != 0) return 0;
    return bpm;
}

/// BPM de la pista actual (0 si no hay pista o falla).
export fn ch_engine_bpm(self: ?*Engine) f64 {
    const e = self orelse return 0;
    e.list_mutex.lock();
    const cur: ?[:0]u8 = if (e.queue_index < e.playlist.items.len) e.playlist.items[e.queue_index] else null;
    e.list_mutex.unlock();
    const p = cur orelse return 0;
    var bpm: f64 = 0;
    if (ch_bpm_detect(p.ptr, &bpm) != 0) return 0;
    return bpm;
}

/// Cuenta los tramos de silencio de `path` (pico < threshold_db, >= min_s).
/// Si `out` no es null se rellenan hasta `max_segments` pares (inicio, fin).
export fn ch_engine_count_silences(self: ?*Engine, path: [*c]const u8, threshold_db: f32, min_s: f64, out: [*c]f64, max_segments: i32) i32 {
    _ = self;
    if (path == null) return -1;
    if (out == null or max_segments <= 0) {
        // Sin buffer solo se puede contar si cabe en uno pequeno.
        var tmp: [256]f64 = undefined;
        return ch_silence_segments(path, threshold_db, min_s, &tmp, 256);
    }
    return ch_silence_segments(path, threshold_db, min_s, out, max_segments);
}

/// Elimina los silencios largos de `src` y escribe `dst` como WAV mono.
export fn ch_engine_strip_silence(self: ?*Engine, src: [*c]const u8, dst: [*c]const u8, threshold_db: f32, min_s: f64, gap_s: f64, rate: i32) i32 {
    _ = self;
    if (src == null or dst == null) return -1;
    return ch_strip_silence(src, dst, threshold_db, min_s, gap_s, rate);
}

/// Une `srcs` (lista de rutas) en un solo WAV PCM16 mono a `rate`.
/// `count` es el numero de rutas de `srcs`. Devuelve 0 si ok.
export fn ch_engine_concat_wav(self: ?*Engine, srcs: [*c]const [*c]const u8, count: i32, dst: [*c]const u8, rate: i32) i32 {
    const e = self orelse return -1;
    if (srcs == null or dst == null or count <= 0) return -1;
    if (rate < 8000 or rate > 192000) return -1;
    const n: usize = @intCast(count);

    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(e.allocator);
    out.appendSlice(e.allocator, &std.mem.zeroes([44]u8)) catch return -2;

    var buf: [8192]f32 = undefined;
    var total: u64 = 0;
    var opened: i32 = 0;
    var failed: i32 = 0;

    for (srcs[0..n]) |sp| {
        if (sp == null) {
            failed += 1;
            continue;
        }
        const d = ch_decode_open(sp, @intCast(rate), 1) orelse {
            failed += 1;
            continue;
        };
        opened += 1;
        while (true) {
            const got = ch_decode_read(d, &buf, 4096);
            if (got == 0) break;
            var i: u64 = 0;
            while (i < got) : (i += 1) {
                const v = std.math.clamp(buf[i], -1.0, 1.0);
                const sc: i16 = @intFromFloat(v * 32767.0);
                const bytes: [2]u8 = .{ @truncate(@as(u16, @bitCast(sc))), @truncate(@as(u16, @bitCast(sc)) >> 8) };
                out.appendSlice(e.allocator, &bytes) catch {
                    ch_decode_close(d);
                    out.deinit(e.allocator);
                    return -2;
                };
            }
            total += got;
        }
        ch_decode_close(d);
    }

    if (opened == 0) {
        out.deinit(e.allocator);
        return e.fail("no se pudo abrir ningun archivo", -3);
    }

    const data_len: u32 = @intCast(out.items.len - 44);
    const rate32: u32 = @intCast(rate);
    wr32(out.items[16..20], 16);
    wr16(out.items[20..22], 1);
    wr16(out.items[22..24], 1);
    wr32(out.items[24..28], rate32);
    wr32(out.items[28..32], rate32 * 2);
    wr16(out.items[32..34], 2);
    wr16(out.items[34..36], 16);
    wr32(out.items[4..8], 36 + data_len);
    wr32(out.items[40..44], data_len);
    @memcpy(out.items[0..4], "RIFF");
    @memcpy(out.items[8..12], "WAVE");
    @memcpy(out.items[12..16], "fmt ");
    @memcpy(out.items[36..40], "data");

    const rc = ch_file_write_atomic(dst, out.items.ptr, out.items.len);
    if (failed > 0 and opened == 0) return -4;
    return rc;
}

/// Divide `src` en un WAV por cada tramo de silencio (los silencios se
/// descartan). `prefix` es el prefijo de salida y se anade _01, _02...
/// Devuelve el numero de pistas escritas, o negativo si error.
export fn ch_engine_split_by_silence(self: ?*Engine, src: [*c]const u8, prefix: [*c]const u8, threshold_db: f32, min_s: f64, rate: i32) i32 {
    const e = self orelse return -1;
    if (src == null or prefix == null) return -1;
    if (rate < 8000 or rate > 192000) return -1;

    var segs_storage: [512]f64 = undefined;
    const nseg = ch_silence_segments(src, threshold_db, min_s, &segs_storage, 512);
    if (nseg < 0) return -2;

    // Los tramos de audio son el complemento de los silencios.
    const d = ch_decode_open(src, @intCast(rate), 1) orelse return -3;
    const total_dur = ch_decode_duration(d);
    ch_decode_close(d);
    if (total_dur <= 0) return -4;

    var ranges: std.ArrayListUnmanaged(struct { a: f64, b: f64 }) = .empty;
    defer ranges.deinit(e.allocator);
    var cursor: f64 = 0;
    for (0..@intCast(nseg)) |i| {
        const a = segs_storage[i * 2];
        const b = segs_storage[i * 2 + 1];
        if (a > cursor + 0.05) {
            ranges.append(e.allocator, .{ .a = cursor, .b = a }) catch return -2;
        }
        cursor = @max(cursor, b);
    }
    if (total_dur > cursor + 0.05) {
        ranges.append(e.allocator, .{ .a = cursor, .b = total_dur }) catch return -2;
    }
    if (ranges.items.len == 0) return 0;

    var written: i32 = 0;
    for (ranges.items, 0..) |r, i| {
        var path_buf: [1024]u8 = undefined;
        const path = std.fmt.bufPrintSentinel(&path_buf, "{s}_{d:0>2}.wav", .{ std.mem.span(prefix), i + 1 }, 0) catch continue;
        const rc = ch_engine_export_wav(e, src, path.ptr, r.a, r.b - r.a, rate, 1);
        if (rc == 0) written += 1;
    }
    return written;
}

/// Espectrograma de `src` como PNG: eje X = tiempo, eje Y = frecuencia
/// (escala logaritmica de 20 Hz a 20 kHz), color = energia.
///
/// `width`/`height` son el tamano de la imagen; `buckets` no se usa y se deja
/// por compatibilidad. Se decodifica a mono 22050 Hz para abaratar el calculo.
export fn ch_engine_spectrogram_png(self: ?*Engine, src: [*c]const u8, dst: [*c]const u8, width: i32, height: i32) i32 {
    const e = self orelse return -1;
    if (src == null or dst == null or width < 16 or height < 16) return -1;
    const w: usize = @min(@as(usize, @intCast(width)), 4096);
    const h: usize = @min(@as(usize, @intCast(height)), 2048);

    const rate: u32 = 22050;
    const N: usize = 1024;
    const d = ch_decode_open(src, rate, 1) orelse return -2;
    defer ch_decode_close(d);

    // Columnas de la imagen: una ventana de N muestras por columna.
    var re: [N]f32 = undefined;
    var im: [N]f32 = undefined;
    var canvas = png.Canvas.create(e.allocator, w, h) catch return -3;
    defer e.allocator.free(canvas.pixels);
    canvas.fillRect(0, w, 0, h, 0, 0, 0);

    // Frecuencias de las filas (log) y bins FFT correspondientes.
    const max_bin: usize = N / 2;
    var row_bin: [2048]usize = undefined;
    const rows: usize = @min(h, row_bin.len);
    for (0..rows) |y| {
        // y=0 abajo (20 Hz), y=rows-1 arriba (20 kHz).
        const t = 1.0 - @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(rows - 1));
        const f = 20.0 * std.math.pow(f32, 1000.0, @as(f32, @floatCast(t * 3.0)));
        const bin = @as(usize, @intFromFloat(f * @as(f32, @floatFromInt(N)) / @as(f32, @floatFromInt(rate))));
        row_bin[y] = @min(@max(bin, 1), max_bin - 1);
    }

    var col: usize = 0;
    var wrote_any = false;
    while (col < w) {
        var got: usize = 0;
        while (got < N) {
            const g = ch_decode_read(d, re[got..].ptr, N - got);
            if (g == 0) break;
            got += @intCast(g);
        }
        if (got == 0) break;
        // Rellenar con ceros si la ultima ventana es corta.
        for (got..N) |i| re[i] = 0;
        for (0..N) |i| {
            const phase = 2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(N));
            im[i] = 0;
            re[i] *= 0.5 - 0.5 * @cos(phase);
        }
        fft.fft(&re, &im);

        for (0..rows) |y| {
            const bin = row_bin[y];
            const power = re[bin] * re[bin] + im[bin] * im[bin];
            const db = 10.0 * std.math.log10(power + 1e-20);
            // -90..-10 dB -> 0..1
            const v = std.math.clamp((db + 90.0) / 80.0, 0.0, 1.0);
            // Mapa de calor simple: azul -> cian -> amarillo -> rojo.
            const chan = struct {
                fn f(x: f32) u8 {
                    const c = std.math.clamp(x, 0.0, 1.0) * 255.0;
                    return @intFromFloat(c);
                }
            }.f;
            const r: u8 = chan(v * 3.0 - 1.0);
            const g: u8 = chan((v * 3.0 - 2.0) * 0.5 + v);
            const b: u8 = chan(1.0 - v * 2.0);
            canvas.set(col, y, r, @min(@as(u8, 255), g), b);
        }
        col += 1;
        wrote_any = true;
        if (got < N) break;
    }
    if (!wrote_any) {
        canvas.destroy(e.allocator);
        return e.fail("no se pudo leer el audio", -4);
    }
    _ = png.write(e.allocator, std.mem.span(dst), canvas);
    return 0;
}

/// Escribe ReplayGain en todos los FLAC/MP3/Ogg/Opus de un directorio.
/// `dir` puede ser una ruta o "" para el directorio de la pista actual.
/// Devuelve el numero de archivos actualizados, o negativo si error.
export fn ch_engine_write_replaygain_dir(self: ?*Engine, dir: [*c]const u8) i32 {
    const e = self orelse return -1;

    var target: []const u8 = "";
    if (dir != null) target = std.mem.span(dir);
    if (target.len == 0) {
        e.list_mutex.lock();
        if (e.queue_index >= e.playlist.items.len) {
            e.list_mutex.unlock();
            return -2;
        }
        const cur: []const u8 = e.playlist.items[e.queue_index];
        const slash = std.mem.lastIndexOfScalar(u8, cur, '/');
        target = if (slash) |i| cur[0 .. i + 1] else cur[0..0];
        e.list_mutex.unlock();
    }
    if (target.len == 0) return -2;

    const exts = [_]?[*:0]const u8{ ".flac", ".mp3", ".ogg", ".opus", null };
    var count: i32 = 0;
    const raw = ch_dir_list_audio(target.ptr, @ptrCast(&exts), &count) orelse return -3;
    defer ch_file_free(raw);

    var updated: i32 = 0;
    var fail_count: i32 = 0;
    var it = std.mem.splitScalar(u8, raw[0..@intCast(std.mem.len(raw))], '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        // Cada linea necesita su propio terminador: el buffer trae todas las
        // rutas juntas y span() leeria hasta el final del buffer.
        const z = e.allocator.dupeSentinel(u8, line, 0) catch continue;
        defer e.allocator.free(z);
        if (ch_engine_write_replaygain(e, z.ptr) == 0) {
            updated += 1;
        } else {
            fail_count += 1;
        }
    }
    if (updated == 0 and fail_count > 0) return -4;
    return updated;
}

/// Escribe ReplayGain en toda la cola (devuelve cuantos se actualizaron).
export fn ch_engine_write_replaygain_queue(self: ?*Engine) i32 {
    const e = self orelse return -1;
    var updated: i32 = 0;
    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    for (e.playlist.items) |item| {
        if (ch_engine_write_replaygain(e, item.ptr) == 0) updated += 1;
    }
    return updated;
}

/// Tonalidad de `path` ("C major", "A minor"...). `confidence` recibe la
/// correlacion [-1,1] si no es null. Devuelve 0 si ok.
export fn ch_engine_detect_key(self: ?*Engine, path: [*c]const u8, out: [*c]u8, out_size: u32, confidence: [*c]f64) i32 {
    _ = self;
    if (path == null or out == null or out_size == 0) return -1;
    return ch_key_detect(path, out, out_size, confidence);
}

/// Tonalidad de la pista actual.
export fn ch_engine_key_current(self: ?*Engine, out: [*c]u8, out_size: u32, confidence: [*c]f64) i32 {
    const e = self orelse return -1;
    if (out == null or out_size == 0) return -1;
    e.list_mutex.lock();
    const cur: ?[:0]u8 = if (e.queue_index < e.playlist.items.len) e.playlist.items[e.queue_index] else null;
    e.list_mutex.unlock();
    const p = cur orelse return -2;
    return ch_key_detect(p.ptr, out, out_size, confidence);
}

/// Rango dinamico DR de la pista en `path` (0 si falla).
export fn ch_dr_measure_path(path: [*c]const u8, out_blocks: [*c]u32) f64 {
    if (path == null) return 0;
    var dr: f64 = 0;
    var blocks: u32 = 0;
    if (ch_dr_measure(path, &dr, &blocks) != 0) return 0;
    if (out_blocks != null) out_blocks[0] = blocks;
    return dr;
}

/// Rango dinamico DR de la pista actual.
export fn ch_engine_dr(self: ?*Engine, out_blocks: [*c]u32) f64 {
    const e = self orelse return 0;
    e.list_mutex.lock();
    const cur: ?[:0]u8 = if (e.queue_index < e.playlist.items.len) e.playlist.items[e.queue_index] else null;
    e.list_mutex.unlock();
    const p = cur orelse return 0;
    var dr: f64 = 0;
    var blocks: u32 = 0;
    if (ch_dr_measure(p.ptr, &dr, &blocks) != 0) return 0;
    if (out_blocks != null) out_blocks[0] = blocks;
    return dr;
}

/// Exporta los picos de forma de onda de la pista actual a CSV.
export fn ch_engine_export_waveform_csv(self: ?*Engine, path: [*c]const u8, buckets: i32) i32 {
    const e = self orelse return -1;
    if (path == null or buckets <= 0) return -1;
    const n: usize = @min(@as(usize, @intCast(buckets)), 100000);
    e.list_mutex.lock();
    const cur: ?[:0]u8 = if (e.queue_index < e.playlist.items.len) e.playlist.items[e.queue_index] else null;
    e.list_mutex.unlock();
    const p = cur orelse return -2;
    const arr = e.allocator.alloc(f32, n) catch return -3;
    defer e.allocator.free(arr);
    if (ch_waveform_peaks(p.ptr, @intCast(n), arr.ptr) != 0) return -4;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);
    buf.appendSlice(e.allocator, "bucket,peak\n") catch return -3;
    var tmp: [64]u8 = undefined;
    for (arr, 0..) |v, i| {
        const line = std.fmt.bufPrint(&tmp, "{d},{d:.5}\n", .{ i, v }) catch continue;
        buf.appendSlice(e.allocator, line) catch return -3;
    }
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Numero de presets de EQ incluidos en el nucleo.
export fn ch_engine_eq_preset_count() i32 {
    return @intCast(eq.PRESET_COUNT);
}

/// Nombre del preset `index` ("" si no existe).
export fn ch_engine_eq_preset_name(index: i32, out: [*c]u8, out_len: i32) i32 {
    if (index < 0 or index >= eq.PRESET_COUNT or out == null or out_len <= 0) return -1;
    const name = eq.PRESETS[@intCast(index)].name;
    const n: usize = @min(name.len, @as(usize, @intCast(out_len)) - 1);
    @memcpy(out[0..n], name[0..n]);
    out[n] = 0;
    return @intCast(n);
}

/// Aplica el preset `index`. Devuelve 0 si ok.
export fn ch_engine_apply_eq_preset(self: ?*Engine, index: i32) i32 {
    const e = self orelse return -1;
    if (index < 0 or index >= eq.PRESET_COUNT) return e.fail("preset de EQ inexistente", -2);
    var gains: [eq.BAND_COUNT]f32 = undefined;
    if (!eq.presetGains(@intCast(index), &gains)) return -2;
    e.eq_gains = gains;
    e.equalizer.setGains(&gains);
    return 0;
}

/// Exporta la forma de onda de la pista actual como PNG (RGB, fondo oscuro).
export fn ch_engine_export_waveform_png(self: ?*Engine, path: [*c]const u8, width: i32, height: i32) i32 {
    const e = self orelse return -1;
    if (path == null or width < 16 or height < 16) return -1;
    const w: usize = @min(@as(usize, @intCast(width)), 4096);
    const h: usize = @min(@as(usize, @intCast(height)), 2048);

    e.list_mutex.lock();
    const cur: ?[:0]u8 = if (e.queue_index < e.playlist.items.len) e.playlist.items[e.queue_index] else null;
    e.list_mutex.unlock();
    const p = cur orelse return -2;

    const peaks = e.allocator.alloc(f32, w) catch return -3;
    defer e.allocator.free(peaks);
    if (ch_waveform_peaks(p.ptr, @intCast(w), peaks.ptr) != 0) return -4;

    var canvas = png.Canvas.create(e.allocator, w, h) catch return -3;
    defer e.allocator.free(canvas.pixels);
    canvas.fillRect(0, w, 0, h, 16, 18, 24);
    const mid = h / 2;
    canvas.fillRect(0, w, mid, mid + 1, 60, 66, 80);
    for (peaks, 0..) |v, x| {
        const amp = @as(usize, @intFromFloat(std.math.clamp(v, 0, 1) * @as(f32, @floatFromInt(mid))));
        const top = mid -| amp;
        const bot = mid + @max(amp, 1);
        canvas.fillRect(x, x + 1, top, bot, 80, 220, 220);
    }
    _ = png.write(e.allocator, std.mem.span(path), canvas);
    return 0;
}

/// Exporta el espectro actual como PNG de barras.
export fn ch_engine_export_spectrum_png(self: ?*Engine, path: [*c]const u8, width: i32, height: i32, bands: i32) i32 {
    const e = self orelse return -1;
    if (path == null or width < 16 or height < 16 or bands <= 0) return -1;
    const w: usize = @min(@as(usize, @intCast(width)), 4096);
    const h: usize = @min(@as(usize, @intCast(height)), 2048);
    const n: usize = @min(@as(usize, @intCast(bands)), w);

    const vals = e.allocator.alloc(f32, n) catch return -3;
    defer e.allocator.free(vals);
    if (ch_engine_spectrum(e, vals.ptr, @intCast(n)) != 0) return -4;

    var canvas = png.Canvas.create(e.allocator, w, h) catch return -3;
    defer e.allocator.free(canvas.pixels);
    canvas.fillRect(0, w, 0, h, 16, 18, 24);

    var b: usize = 0;
    while (b < n) : (b += 1) {
        const x0 = b * w / n;
        const x1 = @max(x0 + 1, (b + 1) * w / n);
        const bh: usize = @intFromFloat(std.math.clamp(vals[b], 0, 1) * @as(f32, @floatFromInt(h)));
        const r: u8 = @intCast(@min(@as(usize, 255), 60 + bh * 200 / @max(h, 1)));
        const g: u8 = @intCast(@min(@as(usize, 255), 180 + bh * 75 / @max(h, 1)));
        canvas.fillRect(x0, x1, h -| bh, h, r, g, 230);
    }
    _ = png.write(e.allocator, std.mem.span(path), canvas);
    return 0;
}

/// Copia las etiquetas de `src` a `dst` (FLAC o MP3). Devuelve el numero de
/// campos copiados, 0 si no habia nada que copiar, negativo si fallo.
export fn ch_engine_copy_tags(src: [*c]const u8, dst: [*c]const u8) i32 {
    if (src == null or dst == null) return -1;
    const d = ch_decode_open(src, 8000, 1) orelse return -1;
    defer ch_decode_close(d);

    const dst_span = std.mem.span(dst);
    const dst_z = e_dupZ(dst_span) orelse return -2;
    defer std.heap.c_allocator.free(dst_z);
    const w = tagWriterFor(dst_span) orelse ch_tags_set;

    const keys = [_][]const u8{ "TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "GENRE", "DATE", "TRACK", "DISC", "COMPOSER", "REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK" };
    var copied: i32 = 0;
    for (keys) |k| {
        const z = e_dupZ(k) orelse continue;
        defer std.heap.c_allocator.free(z);
        const v = ch_decode_tag(d, z.ptr);
        if (v == null) continue;
        const text = std.mem.span(v);
        if (text.len == 0) continue;
        const text_z = e_dupZ(text) orelse continue;
        defer std.heap.c_allocator.free(text_z);
        const rc = w(dst_z.ptr, z.ptr, text_z.ptr);
        if (rc == 0) copied += 1;
    }
    return copied;
}

fn e_dupZ(s: []const u8) ?[:0]u8 {
    const z = std.heap.c_allocator.allocSentinel(u8, s.len, 0) catch return null;
    @memcpy(z, s);
    return z;
}

/// Exporta la cola actual a CSV (indice,ruta,titulo,artista,album,duracion).
export fn ch_engine_export_queue_csv(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    defer out.deinit(e.allocator);
    out.appendSlice(e.allocator, "index,path,title,artist,album,duration\n") catch return -2;
    var line: std.ArrayListUnmanaged(u8) = .empty;
    defer line.deinit(e.allocator);

    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    for (e.playlist.items, 0..) |item, i| {
        const path_s: []const u8 = item;
        var meta = readFileMeta(e.allocator, item) orelse FileMeta{ .title = &.{}, .artist = &.{}, .album = &.{}, .duration = 0 };
        defer meta.deinit(e.allocator);
        const title: []const u8 = meta.title;
        const artist: []const u8 = meta.artist;
        const album: []const u8 = meta.album;
        const dur: f64 = meta.duration;
        line.clearRetainingCapacity();
        line.appendSlice(e.allocator, tryFmt("{d}", .{i}) orelse "0") catch return -2;
        line.append(e.allocator, ',') catch return -2;
        csvField(e.allocator, &line, path_s) catch return -2;
        line.append(e.allocator, ',') catch return -2;
        csvField(e.allocator, &line, title) catch return -2;
        line.append(e.allocator, ',') catch return -2;
        csvField(e.allocator, &line, artist) catch return -2;
        line.append(e.allocator, ',') catch return -2;
        csvField(e.allocator, &line, album) catch return -2;
        line.append(e.allocator, ',') catch return -2;
        line.appendSlice(e.allocator, tryFmt("{d:.1}", .{dur}) orelse "0") catch return -2;
        line.append(e.allocator, '\n') catch return -2;
        out.appendSlice(e.allocator, line.items) catch return -2;
    }
    return ch_file_write_atomic(path, out.items.ptr, out.items.len);
}

/// Metadatos de un archivo con memoria propia (el decodificador los libera al
/// cerrarse, asi que hay que copiarlos antes de ch_decode_close).
const FileMeta = struct {
    title: []u8,
    artist: []u8,
    album: []u8,
    duration: f64,

    fn deinit(self: *FileMeta, a: Allocator) void {
        a.free(self.title);
        a.free(self.artist);
        a.free(self.album);
    }
};

fn readFileMeta(a: Allocator, path: []const u8) ?FileMeta {
    const d = ch_decode_open(path.ptr, 8000, 1) orelse return null;
    defer ch_decode_close(d);
    const t = std.mem.span(ch_decode_title(d));
    const ar = std.mem.span(ch_decode_artist(d));
    const al = std.mem.span(ch_decode_album(d));
    const dup = struct {
        fn f(aa: Allocator, src: []const u8) []u8 {
            const c = aa.dupe(u8, src) catch return aa.alloc(u8, 0) catch &.{};
            return c;
        }
    }.f;
    return .{
        .title = dup(a, t),
        .artist = dup(a, ar),
        .album = dup(a, al),
        .duration = ch_decode_duration(d),
    };
}

/// Copia un tag de `path` a memoria propia ("" si no existe o no se puede leer).
fn readTagDup(a: Allocator, path: []const u8, key: []const u8) []u8 {
    const d = ch_decode_open(path.ptr, 8000, 1) orelse return a.alloc(u8, 0) catch &.{};
    defer ch_decode_close(d);
    const key_z = a.dupeSentinel(u8, key, 0) catch return a.alloc(u8, 0) catch &.{};
    defer a.free(key_z);
    const v = ch_decode_tag(d, key_z.ptr);
    const copy = a.dupe(u8, std.mem.span(v)) catch return a.alloc(u8, 0) catch &.{};
    return copy;
}

/// Buffer temporal para formatear un numero sin arriesgar el asignador.
fn tryFmt(comptime fmt: []const u8, args: anytype) ?[]const u8 {
    const S = struct {
        var buf: [128]u8 = undefined;
    };
    return std.fmt.bufPrint(&S.buf, fmt, args) catch null;
}

/// Anade un campo CSV escapado (entrecomillas si contiene , " o salto).
fn csvField(allocator: Allocator, out: *std.ArrayListUnmanaged(u8), s: []const u8) !void {
    var needs = false;
    for (s) |c| {
        if (c == ',' or c == '"' or c == '\n' or c == '\r') {
            needs = true;
            break;
        }
    }
    if (!needs) return out.appendSlice(allocator, s);
    try out.append(allocator, '"');
    for (s) |c| {
        if (c == '"') try out.append(allocator, '"');
        try out.append(allocator, c);
    }
    try out.append(allocator, '"');
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

/// Busca rutas que contengan `needle` (case-insensitive). Devuelve un buffer con
/// los indices encontrados y escribe el total en `count_out`; el buffer se libera
/// con `ch_file_free`. Devuelve null si no hay coincidencias.
export fn ch_library_search(lib: ?*const ch_library, needle: [*c]const u8, count_out: ?*i32) ?[*]i32 {
    if (lib == null or needle == null) return null;
    var n: i32 = 0;
    const ptr = c_lib_search(lib, needle, &n);
    if (count_out) |out| out.* = n;
    return ptr;
}

/// Elimina una ruta de la biblioteca. Devuelve 1 si se elimino, 0 si no estaba.
export fn ch_library_remove(lib: ?*ch_library, path: [*c]const u8) i32 {
    if (lib == null or path == null) return 0;
    return @intCast(c_lib_remove(lib, path));
}

export fn ch_library_path(lib: ?*const ch_library, index: i32) [*c]const u8 {
    if (index < 0) return @ptrCast("");
    const p = c_lib_path(lib, index);
    return if (p == null) @ptrCast("") else p;
}

export fn ch_library_removed(lib: ?*const ch_library) i32 {
    return @intCast(c_lib_removed(lib));
}

/// Exporta la biblioteca a un archivo JSON. Devuelve 0 si ok.
export fn ch_library_export_json(lib: ?*const ch_library, path: [*c]const u8) i32 {
    if (lib == null or path == null) return -1;
    const alloc = std.heap.c_allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);
    buf.appendSlice(alloc, "{\n  \"tracks\": [\n") catch return -2;
    const n = c_lib_count(lib);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const p: [*c]const u8 = c_lib_path(lib, i) orelse @ptrCast("");
        buf.appendSlice(alloc, "    \"") catch return -2;
        appendJsonString(&buf, alloc, std.mem.span(p)) catch return -2;
        buf.appendSlice(alloc, "\"") catch return -2;
        if (i + 1 < n) buf.append(alloc, ',') catch return -2;
        buf.append(alloc, '\n') catch return -2;
    }
    buf.appendSlice(alloc, "  ],\n  \"count\": ") catch return -2;
    var tmp: [32]u8 = undefined;
    const num = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch return -2;
    buf.appendSlice(alloc, num) catch return -2;
    buf.appendSlice(alloc, "\n}\n") catch return -2;
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Exporta la biblioteca a un archivo CSV (path;filename). Devuelve 0 si ok.
export fn ch_library_export_csv(lib: ?*const ch_library, path: [*c]const u8) i32 {
    if (lib == null or path == null) return -1;
    const alloc = std.heap.c_allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);
    buf.appendSlice(alloc, "path;filename\n") catch return -2;
    const n = c_lib_count(lib);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const p: [*c]const u8 = c_lib_path(lib, i) orelse @ptrCast("");
        const span = std.mem.span(p);
        buf.appendSlice(alloc, span) catch return -2;
        buf.append(alloc, ';') catch return -2;
        if (std.mem.lastIndexOfScalar(u8, span, '/')) |slash| {
            buf.appendSlice(alloc, span[slash + 1 ..]) catch return -2;
        } else {
            buf.appendSlice(alloc, span) catch return -2;
        }
        buf.append(alloc, '\n') catch return -2;
    }
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Exporta la biblioteca a un archivo JSON con metadatos por pista
/// (titulo, artista, album, duracion). Devuelve 0 si ok.
export fn ch_library_export_json_meta(lib: ?*const ch_library, path: [*c]const u8) i32 {
    if (lib == null or path == null) return -1;
    const alloc = std.heap.c_allocator;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);
    buf.appendSlice(alloc, "{\n  \"tracks\": [\n") catch return -2;
    const n = c_lib_count(lib);
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const p: [*c]const u8 = c_lib_path(lib, i) orelse @ptrCast("");
        const span = std.mem.span(p);
        buf.appendSlice(alloc, "    {\"path\": \"") catch return -2;
        appendJsonString(&buf, alloc, span) catch return -2;
        buf.appendSlice(alloc, "\", \"title\": \"") catch return -2;

        var meta = readFileMeta(alloc, span) orelse FileMeta{ .title = &.{}, .artist = &.{}, .album = &.{}, .duration = 0 };
        defer meta.deinit(alloc);
        const title: []const u8 = meta.title;
        const artist: []const u8 = meta.artist;
        const album: []const u8 = meta.album;
        const dur: f64 = meta.duration;
        appendJsonString(&buf, alloc, title) catch return -2;
        buf.appendSlice(alloc, "\", \"artist\": \"") catch return -2;
        appendJsonString(&buf, alloc, artist) catch return -2;
        buf.appendSlice(alloc, "\", \"album\": \"") catch return -2;
        appendJsonString(&buf, alloc, album) catch return -2;
        var tmp: [64]u8 = undefined;
        const ds = std.fmt.bufPrint(&tmp, "\", \"duration\": {d:.2}}}", .{dur}) catch return -2;
        buf.appendSlice(alloc, ds) catch return -2;
        if (i + 1 < n) buf.append(alloc, ',') catch return -2;
        buf.append(alloc, '\n') catch return -2;
    }
    buf.appendSlice(alloc, "  ],\n  \"count\": ") catch return -2;
    var tmp2: [32]u8 = undefined;
    const num = std.fmt.bufPrint(&tmp2, "{d}", .{n}) catch return -2;
    buf.appendSlice(alloc, num) catch return -2;
    buf.appendSlice(alloc, "\n}\n") catch return -2;
    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Añade a la cola todas las pistas de la biblioteca cuya ruta contenga
/// `needle` (vacio = todas). Devuelve el numero anadido, o negativo si error.
export fn ch_engine_queue_add_library(self: ?*Engine, lib: ?*const ch_library, needle: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (lib == null) return -1;
    const n = c_lib_count(lib);
    const span: []const u8 = if (needle == null) "" else std.mem.span(needle);

    var added: i32 = 0;
    e.list_mutex.lock();
    defer e.list_mutex.unlock();
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const p: [*c]const u8 = c_lib_path(lib, i) orelse continue;
        const path = std.mem.span(p);
        if (span.len > 0 and std.mem.indexOf(u8, path, span) == null) continue;
        const z = e.allocator.dupeSentinel(u8, path, 0) catch continue;
        e.playlist.append(e.allocator, z) catch {
            e.allocator.free(z);
            continue;
        };
        added += 1;
    }
    if (added == 0) return 0;
    e.order.clearRetainingCapacity();
    e.order_pos = 0;
    _ = e.pushEvent(EV_QUEUE, added, 0, 0);
    return added;
}

/// Activa/desactiva "evitar repetir pista reciente" (shuffle con recencia).
export fn ch_engine_set_avoid_recent(self: ?*Engine, enabled: i32) i32 {
    const e = self orelse return -1;
    e.avoid_recent = enabled != 0;
    if (!e.avoid_recent) {
        for (e.recent.items) |r| e.allocator.free(r);
        e.recent.clearRetainingCapacity();
    }
    return 0;
}

export fn ch_engine_avoid_recent(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return if (e.avoid_recent) 1 else 0;
}

/// Numero de pistas en el historial reciente.
export fn ch_engine_recent_count(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return @intCast(e.recent.items.len);
}

/// Limpia el historial reciente.
export fn ch_engine_recent_clear(self: ?*Engine) i32 {
    const e = self orelse return -1;
    for (e.recent.items) |r| e.allocator.free(r);
    e.recent.clearRetainingCapacity();
    return 0;
}

/// Pausa automaticamente al terminar una carpeta (cuando la siguiente pista
/// esta en otro directorio).
export fn ch_engine_set_pause_at_dir_end(self: ?*Engine, enabled: i32) i32 {
    const e = self orelse return -1;
    e.pause_at_dir_end = enabled != 0;
    return 0;
}

export fn ch_engine_pause_at_dir_end(self: ?*Engine) i32 {
    const e = self orelse return 0;
    return if (e.pause_at_dir_end) 1 else 0;
}

/// Ganancia automatica al abrir cada pista: mide LUFS y ajusta la ganancia
/// manual para alcanzar `target_lufs` (por defecto -14).
export fn ch_engine_set_auto_gain(self: ?*Engine, enabled: i32, target_lufs: f64) i32 {
    const e = self orelse return -1;
    e.auto_gain = enabled != 0;
    e.auto_gain_target = std.math.clamp(target_lufs, -30, -5);
    return 0;
}

export fn ch_engine_auto_gain(self: ?*Engine, target_lufs: ?*f64) i32 {
    const e = self orelse return 0;
    if (target_lufs) |p| p.* = e.auto_gain_target;
    return if (e.auto_gain) 1 else 0;
}

// ---- Estado de reproduccion persistente ----

fn appendEscaped(buf: *std.ArrayListUnmanaged(u8), alloc: Allocator, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '\\' => try buf.appendSlice(alloc, "\\\\"),
            '\t' => try buf.appendSlice(alloc, "\\t"),
            '\n' => try buf.appendSlice(alloc, "\\n"),
            '\r' => try buf.appendSlice(alloc, "\\r"),
            else => try buf.append(alloc, c),
        }
    }
}

fn unescapeAlloc(alloc: Allocator, s: []const u8) ![]u8 {
    var out = try alloc.alloc(u8, s.len);
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\' and i + 1 < s.len) {
            i += 1;
            out[n] = switch (s[i]) {
                't' => '\t',
                'n' => '\n',
                'r' => '\r',
                else => s[i],
            };
        } else {
            out[n] = s[i];
        }
        n += 1;
    }
    return out[0..n];
}

fn appendNum(buf: *std.ArrayListUnmanaged(u8), alloc: Allocator, value: f64) !void {
    var tmp: [64]u8 = undefined;
    const text = try std.fmt.bufPrint(&tmp, "{d:.6}", .{value});
    try buf.appendSlice(alloc, text);
}

/// Guarda cola, posicion, pista actual y ajustes en un archivo de texto.
export fn ch_engine_save_state(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);
    buf.appendSlice(e.allocator, "CHSTATE\t1\n") catch return -2;

    e.list_mutex.lock();
    for (e.playlist.items, 0..) |item, i| {
        if (i == e.queue_index) {
            buf.appendSlice(e.allocator, "current\t") catch {};
        } else {
            buf.appendSlice(e.allocator, "queue\t") catch {};
        }
        appendEscaped(&buf, e.allocator, item) catch {};
        buf.append(e.allocator, '\n') catch {};
    }
    e.list_mutex.unlock();

    const p = @atomicLoad(usize, &e.played, .acquire);
    var seg_start: usize = 0;
    e.seg_lock.lock();
    if (e.findSegment(p)) |pos| seg_start = e.segments[pos].start;
    e.seg_lock.unlock();
    const position = @as(f64, @floatFromInt(p -| seg_start)) / SAMPLE_RATE;

    var tmp: [128]u8 = undefined;
    const posline = std.fmt.bufPrint(&tmp, "pos\t{d:.6}\n", .{position}) catch "";
    buf.appendSlice(e.allocator, posline) catch {};

    const volume = @as(f32, @bitCast(@atomicLoad(u32, &e.volume_bits, .monotonic)));
    const speed = e.speedValue();
    const pitch = @as(f32, @bitCast(@atomicLoad(u32, &e.pitch_bits, .monotonic)));
    const balance = @as(f32, @bitCast(@atomicLoad(u32, &e.balance_bits, .monotonic)));
    const cf_strength = e.dsp.crossfeed.level();
    const xfade = @as(f32, @bitCast(@atomicLoad(u32, &e.xfade_bits, .monotonic)));

    const lines = [_]struct { key: []const u8, a: f64, b: f64 }{
        .{ .key = "volume", .a = volume, .b = 0 },
        .{ .key = "speed", .a = speed, .b = 0 },
        .{ .key = "pitch", .a = pitch, .b = 0 },
        .{ .key = "xfade", .a = xfade, .b = 0 },
        .{ .key = "balance", .a = balance, .b = 0 },
        .{ .key = "gain", .a = @as(f32, @bitCast(@atomicLoad(u32, &e.gain_db_bits, .monotonic))), .b = 0 },
        .{ .key = "repeat", .a = @floatFromInt(e.repeat_mode), .b = 0 },
        .{ .key = "shuffle", .a = if (@atomicLoad(bool, &e.shuffle, .monotonic)) 1 else 0, .b = 0 },
        .{ .key = "rg", .a = if (@atomicLoad(bool, &e.rg_enabled, .monotonic)) 1 else 0, .b = 0 },
        .{ .key = "limiter", .a = if (e.limit_enabled) 1 else 0, .b = e.limit_ceiling },
        .{ .key = "mono", .a = if (@atomicLoad(u32, &e.chan_mode, .monotonic) == 1) 1 else 0, .b = 0 },
        .{ .key = "chan_mode", .a = @floatFromInt(@atomicLoad(u32, &e.chan_mode, .monotonic)), .b = 0 },
        .{ .key = "width", .a = e.dsp.enhancer.width(), .b = 0 },
        .{ .key = "trim", .a = if (e.trim_enabled) 1 else 0, .b = e.trim_threshold_db },
        .{ .key = "crossfeed", .a = if (e.dsp.crossfeed.isEnabled()) 1 else 0, .b = cf_strength },
    };
    for (lines) |line| {
        buf.appendSlice(e.allocator, line.key) catch {};
        buf.append(e.allocator, '\t') catch {};
        appendNum(&buf, e.allocator, line.a) catch {};
        const has_second = std.mem.eql(u8, line.key, "limiter") or
            std.mem.eql(u8, line.key, "crossfeed") or
            std.mem.eql(u8, line.key, "trim");
        if (has_second) {
            buf.append(e.allocator, '\t') catch {};
            appendNum(&buf, e.allocator, line.b) catch {};
        }
        buf.append(e.allocator, '\n') catch {};
    }

    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Exporta cola, pista actual, posicion y ajustes a un archivo JSON.
/// Devuelve 0 si ok.
export fn ch_engine_export_json(self: ?*Engine, path: [*c]const u8) i32 {
    const e = self orelse return -1;
    if (path == null) return -1;

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(e.allocator);

    buf.appendSlice(e.allocator, "{\n  \"queue\": [\n") catch return -2;

    e.list_mutex.lock();
    for (e.playlist.items, 0..) |item, i| {
        if (i == e.queue_index) {
            buf.appendSlice(e.allocator, "    { \"current\": true, \"path\": \"") catch {};
        } else {
            buf.appendSlice(e.allocator, "    { \"current\": false, \"path\": \"") catch {};
        }
        appendJsonString(&buf, e.allocator, item) catch {};
        buf.appendSlice(e.allocator, "\" }") catch {};
        if (i + 1 < e.playlist.items.len) buf.append(e.allocator, ',') catch {};
        buf.append(e.allocator, '\n') catch {};
    }
    e.list_mutex.unlock();

    buf.appendSlice(e.allocator, "  ],\n  \"settings\": {\n") catch {};

    const p = @atomicLoad(usize, &e.played, .acquire);
    var seg_start: usize = 0;
    e.seg_lock.lock();
    if (e.findSegment(p)) |pos| seg_start = e.segments[pos].start;
    e.seg_lock.unlock();
    const position = @as(f64, @floatFromInt(p -| seg_start)) / SAMPLE_RATE;

    const volume = @as(f32, @bitCast(@atomicLoad(u32, &e.volume_bits, .monotonic)));
    const speed = e.speedValue();
    const pitch = @as(f32, @bitCast(@atomicLoad(u32, &e.pitch_bits, .monotonic)));
    const balance = @as(f32, @bitCast(@atomicLoad(u32, &e.balance_bits, .monotonic)));
    const gain_db = @as(f32, @bitCast(@atomicLoad(u32, &e.gain_db_bits, .monotonic)));
    const xfade = @as(f32, @bitCast(@atomicLoad(u32, &e.xfade_bits, .monotonic)));
    const width = @as(f32, @bitCast(@atomicLoad(u32, &e.width_bits, .monotonic)));

    var line_buf: [1024]u8 = undefined;
    var w: usize = 0;
    var tmp: [256]u8 = undefined;
    const add = struct {
        fn f(dst: []u8, w2: *usize, key: []const u8, val: []const u8, comma: bool) void {
            if (comma and w2.* > 0) {
                dst[w2.*] = ',';
                w2.* += 1;
            }
            const s = std.fmt.bufPrint(dst[w2.*..], "\n    \"{s}\": {s}", .{ key, val }) catch return;
            w2.* += s.len;
        }
    }.f;

    add(&line_buf, &w, "position", std.fmt.bufPrint(&tmp, "{d:.3}", .{position}) catch "0", false);
    add(&line_buf, &w, "volume", std.fmt.bufPrint(&tmp, "{d:.4}", .{volume}) catch "0", true);
    add(&line_buf, &w, "speed", std.fmt.bufPrint(&tmp, "{d:.4}", .{speed}) catch "1", true);
    add(&line_buf, &w, "pitch", std.fmt.bufPrint(&tmp, "{d:.3}", .{pitch}) catch "0", true);
    add(&line_buf, &w, "xfade", std.fmt.bufPrint(&tmp, "{d:.3}", .{xfade}) catch "0", true);
    add(&line_buf, &w, "balance", std.fmt.bufPrint(&tmp, "{d:.4}", .{balance}) catch "0", true);
    add(&line_buf, &w, "gain_db", std.fmt.bufPrint(&tmp, "{d:.3}", .{gain_db}) catch "0", true);
    add(&line_buf, &w, "width", std.fmt.bufPrint(&tmp, "{d:.3}", .{width}) catch "1", true);
    add(&line_buf, &w, "repeat", std.fmt.bufPrint(&tmp, "{d}", .{e.repeat_mode}) catch "0", true);
    add(&line_buf, &w, "shuffle", if (@atomicLoad(bool, &e.shuffle, .monotonic)) "true" else "false", true);
    add(&line_buf, &w, "replaygain", if (@atomicLoad(bool, &e.rg_enabled, .monotonic)) "true" else "false", true);
    add(&line_buf, &w, "limiter", if (e.limit_enabled) "true" else "false", true);
    add(&line_buf, &w, "channel_mode", std.fmt.bufPrint(&tmp, "{d}", .{@atomicLoad(u32, &e.chan_mode, .monotonic)}) catch "0", true);
    add(&line_buf, &w, "trim", if (e.trim_enabled) "true" else "false", true);
    add(&line_buf, &w, "fade_out", std.fmt.bufPrint(&tmp, "{d:.2}", .{e.fade_out_s}) catch "0", true);

    buf.appendSlice(e.allocator, line_buf[0..w]) catch {};
    buf.appendSlice(e.allocator, "\n  }\n}\n") catch {};

    return ch_file_write_atomic(path, buf.items.ptr, buf.items.len);
}

/// Escapa un string para JSON (comillas, backslash, control).
fn appendJsonString(buf: *std.ArrayListUnmanaged(u8), alloc: Allocator, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(alloc, "\\\""),
            '\\' => try buf.appendSlice(alloc, "\\\\"),
            '\n' => try buf.appendSlice(alloc, "\\n"),
            '\r' => try buf.appendSlice(alloc, "\\r"),
            '\t' => try buf.appendSlice(alloc, "\\t"),
            else => {
                if (c < 0x20) {
                    var tmp: [6]u8 = undefined;
                    const txt = try std.fmt.bufPrint(&tmp, "\\u{X:0>4}", .{c});
                    try buf.appendSlice(alloc, txt);
                } else {
                    try buf.append(alloc, c);
                }
            },
        }
    }
}

/// Carga el estado guardado. Deja la pista cargada y en pausa; escribe en
/// `position_out` la posicion (segundos) a la que saltar. 0 si ok.
export fn ch_engine_load_state(self: ?*Engine, path: [*c]const u8, position_out: ?*f64) i32 {
    const e = self orelse return -1;
    if (position_out) |p| p.* = 0;
    if (path == null) return -1;

    var size: u64 = 0;
    const raw = ch_file_read_all(path, &size);
    if (raw == null) return -2;
    defer ch_file_free(raw);
    const data = raw[0..@intCast(size)];

    var paths: std.ArrayListUnmanaged([:0]u8) = .empty;
    defer {
        for (paths.items) |p| e.allocator.free(p);
        paths.deinit(e.allocator);
    }

    var current: usize = 0;
    var position: f64 = 0;
    var volume: f32 = -1;
    var speed: f32 = -1;
    var pitch: f32 = -999;
    var xfade: f32 = -1;
    var balance: f32 = -999;
    var gain_db: f32 = -999;
    var repeat_mode: i32 = -1;
    var shuffle: i32 = -1;
    var rg: i32 = -1;
    var limiter: i32 = -1;
    var limiter_ceiling: f32 = 0;
    var mono: i32 = -1;
    var chan_mode: i32 = -1;
    var width: f32 = -1;
    var trim: i32 = -1;
    var trim_threshold: f32 = -60;
    var crossfeed: i32 = -1;
    var cf_strength: f32 = 0.5;

    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const key = line[0..tab];
        const rest = line[tab + 1 ..];

        if (std.mem.eql(u8, key, "CHSTATE")) continue;
        if (std.mem.eql(u8, key, "queue") or std.mem.eql(u8, key, "current")) {
            const decoded = unescapeAlloc(e.allocator, rest) catch return -2;
            const sentinel = e.allocator.dupeSentinel(u8, decoded, 0) catch {
                e.allocator.free(decoded);
                return -2;
            };
            e.allocator.free(decoded);
            if (std.mem.eql(u8, key, "current")) current = paths.items.len;
            paths.append(e.allocator, sentinel) catch {
                e.allocator.free(sentinel);
                return -2;
            };
            continue;
        }

        const second = std.mem.indexOfScalar(u8, rest, '\t');
        const first_txt = if (second) |s| rest[0..s] else rest;
        const second_txt = if (second) |s| rest[s + 1 ..] else "";
        const value = std.fmt.parseFloat(f64, first_txt) catch continue;
        const extra = std.fmt.parseFloat(f64, second_txt) catch 0;

        if (std.mem.eql(u8, key, "pos")) position = value else if (std.mem.eql(u8, key, "volume")) volume = @floatCast(value) else if (std.mem.eql(u8, key, "speed")) speed = @floatCast(value) else if (std.mem.eql(u8, key, "pitch")) pitch = @floatCast(value) else if (std.mem.eql(u8, key, "xfade")) xfade = @floatCast(value) else if (std.mem.eql(u8, key, "balance")) balance = @floatCast(value) else if (std.mem.eql(u8, key, "gain")) gain_db = @floatCast(value) else if (std.mem.eql(u8, key, "repeat")) repeat_mode = @intFromFloat(value) else if (std.mem.eql(u8, key, "shuffle")) shuffle = @intFromFloat(value) else if (std.mem.eql(u8, key, "rg")) rg = @intFromFloat(value) else if (std.mem.eql(u8, key, "limiter")) {
            limiter = @intFromFloat(value);
            limiter_ceiling = @floatCast(extra);
        } else if (std.mem.eql(u8, key, "mono")) mono = @intFromFloat(value) else if (std.mem.eql(u8, key, "chan_mode")) chan_mode = @intFromFloat(value) else if (std.mem.eql(u8, key, "width")) width = @floatCast(value) else if (std.mem.eql(u8, key, "trim")) {
            trim = @intFromFloat(value);
            trim_threshold = @floatCast(extra);
        } else if (std.mem.eql(u8, key, "crossfeed")) {
            crossfeed = @intFromFloat(value);
            cf_strength = @floatCast(extra);
        }
    }

    if (paths.items.len == 0) return -3;
    if (current >= paths.items.len) current = 0;

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
    for (paths.items) |p| {
        e.playlist.append(e.allocator, p) catch {};
    }
    paths.clearRetainingCapacity();
    e.queue_index = current;
    e.list_mutex.unlock();
    e.resetSegments();
    @atomicStore(usize, &e.played, 0, .release);
    @atomicStore(bool, &e.eof, true, .release);

    if (volume >= 0) _ = ch_engine_set_volume(e, volume);
    if (speed > 0) _ = ch_engine_set_speed(e, speed);
    if (pitch > -900) _ = ch_engine_set_pitch(e, pitch);
    if (xfade >= 0) _ = ch_engine_set_crossfade(e, xfade);
    if (balance > -900) _ = ch_engine_set_balance(e, balance);
    if (gain_db > -900) _ = ch_engine_set_gain_db(e, gain_db);
    if (repeat_mode >= 0) _ = ch_engine_set_repeat(e, repeat_mode);
    if (shuffle >= 0) _ = ch_engine_set_shuffle(e, shuffle);
    if (rg >= 0) _ = ch_engine_set_replaygain(e, rg);
    if (limiter >= 0) _ = ch_engine_set_limiter(e, limiter, limiter_ceiling);
    if (chan_mode >= 0) {
        _ = ch_engine_set_channel_mode(e, chan_mode);
    } else if (mono >= 0) {
        _ = ch_engine_set_mono(e, mono);
    }
    if (width >= 0) _ = ch_engine_set_stereo_width(e, width);
    if (trim >= 0) _ = ch_engine_set_trim_silence(e, trim, trim_threshold);
    if (crossfeed >= 0) _ = ch_engine_set_crossfeed(e, crossfeed, cf_strength);

    _ = e.beginAt(current);
    if (position > 0) {
        @atomicStore(usize, &e.seek_req, @intFromFloat(position * SAMPLE_RATE), .release);
    }
    if (position_out) |p| p.* = position;
    return 0;
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

// ---- Paisajes sonoros, deteccion de BPM y exportador WAV (fase 3) ----

/// Enciende un paisaje bajo la musica. `preset`: 0 apagado, 1 lluvia,
/// 2 ruido marron, 3 vinilo. `level` 0..1 (se recorta). Devuelve 1 si quedo
/// encendido y 0 si no (p. ej. nivel 0). -1 si el motor es nulo.
export fn ch_engine_set_soundscape(self: ?*Engine, preset: i32, level: f32) i32 {
    const e = self orelse return -1;
    const p: u32 = if (preset <= 0) 0 else @intCast(preset);
    e.soundscape.set(p, level);
    return if (e.soundscape.isIdle()) 0 else 1;
}

/// Preset activo (0 apagado) y, si `level` no es nulo, su nivel.
export fn ch_engine_soundscape(self: ?*Engine, level: ?*f32) i32 {
    const e = self orelse return -1;
    if (level) |p| p.* = e.soundscape.level();
    return @intCast(e.soundscape.presetValue());
}

const BPM_ANALYSIS_SECONDS: usize = 30;

/// Detecta el pulso de un fichero. Devuelve 0 si no hay pulso creible.
/// Analiza como mucho los primeros 30 s (suficiente y rapido).
export fn ch_engine_detect_bpm(path: [*c]const u8) f64 {
    if (path == null or path[0] == 0) return 0;
    const dec = ch_decode_open(path, SAMPLE_RATE, CHANNELS) orelse return 0;
    defer ch_decode_close(dec);

    const alloc = std.heap.c_allocator;
    const cap = SAMPLE_RATE * BPM_ANALYSIS_SECONDS;
    const mono = alloc.alloc(f32, cap) catch return 0;
    defer alloc.free(mono);

    var scratch: [4096 * CHANNELS]f32 = undefined;
    var filled: usize = 0;
    while (filled < cap) {
        const want: usize = @min(4096, cap - filled);
        const got = ch_decode_read(dec, &scratch, want);
        if (got == 0) break;
        const frames: usize = @intCast(got);
        var i: usize = 0;
        while (i < frames) : (i += 1) {
            mono[filled + i] = (scratch[i * CHANNELS] + scratch[i * CHANNELS + 1]) * 0.5;
        }
        filled += frames;
    }
    return bpm_mod.detect(mono[0..filled], @floatFromInt(SAMPLE_RATE));
}

const EXPORT_CHUNK_FRAMES: usize = 4096;
const WAV_HEADER_BYTES: u64 = 44;

/// Cabecera RIFF/WAVE PCM 16 bits entrelazado. 48 kHz estereo por contrato
/// (sin remuestrear: el decodificador ya entrega 48 kHz).
fn wavHeader(data_bytes: u64) [44]u8 {
    var h: [44]u8 = undefined;
    @memcpy(h[0..4], "RIFF");
    std.mem.writeInt(u32, h[4..][0..4], @intCast(36 + data_bytes), .little);
    @memcpy(h[8..12], "WAVE");
    @memcpy(h[12..16], "fmt ");
    std.mem.writeInt(u32, h[16..][0..4], 16, .little);
    std.mem.writeInt(u16, h[20..][0..2], 1, .little); // PCM
    std.mem.writeInt(u16, h[22..][0..2], @intCast(CHANNELS), .little);
    std.mem.writeInt(u32, h[24..][0..4], SAMPLE_RATE, .little);
    std.mem.writeInt(u32, h[28..][0..4], SAMPLE_RATE * CHANNELS * 2, .little);
    std.mem.writeInt(u16, h[32..][0..2], @intCast(CHANNELS * 2), .little);
    std.mem.writeInt(u16, h[34..][0..2], 16, .little);
    @memcpy(h[36..40], "data");
    std.mem.writeInt(u32, h[40..][0..4], @intCast(data_bytes), .little);
    return h;
}

/// Cabecera RIFF/WAVE. `bits` = 16/24/32 y `is_float` selecciona PCM (1) o
/// IEEE float (3). El contrato sigue siendo 48 kHz estereo entrelazado.
fn wavHeaderBits(data_bytes: u64, bits: u16, is_float: bool) [44]u8 {
    var h: [44]u8 = undefined;
    const block_align: u16 = @intCast(CHANNELS * (bits / 8));
    @memcpy(h[0..4], "RIFF");
    std.mem.writeInt(u32, h[4..][0..4], @intCast(36 + data_bytes), .little);
    @memcpy(h[8..12], "WAVE");
    @memcpy(h[12..16], "fmt ");
    std.mem.writeInt(u32, h[16..][0..4], 16, .little);
    std.mem.writeInt(u16, h[20..][0..2], if (is_float) 3 else 1, .little);
    std.mem.writeInt(u16, h[22..][0..2], @intCast(CHANNELS), .little);
    std.mem.writeInt(u32, h[24..][0..4], SAMPLE_RATE, .little);
    std.mem.writeInt(u32, h[28..][0..4], SAMPLE_RATE * @as(u32, block_align), .little);
    std.mem.writeInt(u16, h[32..][0..2], block_align, .little);
    std.mem.writeInt(u16, h[34..][0..2], bits, .little);
    @memcpy(h[36..40], "data");
    std.mem.writeInt(u32, h[40..][0..4], @intCast(data_bytes), .little);
    return h;
}

/// Cabecera AIFF (big-endian) PCM 16 bits. 54 bytes antes del audio. La tasa de
/// muestreo va en formato extendido de 80 bits; 48000 Hz es constante por
/// contrato, asi que se escribe su representacion exacta (0x400EBB80...).
fn aiffHeader(data_bytes: u64) [54]u8 {
    var h: [54]u8 = undefined;
    @memset(&h, 0);
    const frames: u32 = @intCast(data_bytes / (CHANNELS * 2));
    @memcpy(h[0..4], "FORM");
    std.mem.writeInt(u32, h[4..][0..4], @intCast(46 + data_bytes), .big);
    @memcpy(h[8..12], "AIFF");
    @memcpy(h[12..16], "COMM");
    std.mem.writeInt(u32, h[16..][0..4], 18, .big);
    std.mem.writeInt(u16, h[20..][0..2], @intCast(CHANNELS), .big);
    std.mem.writeInt(u32, h[22..][0..4], frames, .big);
    std.mem.writeInt(u16, h[26..][0..2], 16, .big);
    // 48000 Hz en extendido 80-bit: exponente 0x400E, mantisa 0xBB80...
    h[36] = 0x40;
    h[37] = 0x0E;
    h[38] = 0xBB;
    h[39] = 0x80;
    @memcpy(h[40..44], "SSND");
    std.mem.writeInt(u32, h[44..][0..4], @intCast(8 + data_bytes), .big);
    // offset (48) y blockSize (50) quedan a 0.
    return h;
}

/// Escribe todo el bloque o falla. `std.c` en vez de `std.fs`: en Zig 0.17 el
/// sistema de ficheros pide un contexto `std.Io` y aqui no hay ninguno (esto se
/// llama desde Dart por FFI).
fn writeAll(stream: *std.c.FILE, bytes: []const u8) bool {
    if (bytes.len == 0) return true;
    return std.c.fwrite(bytes.ptr, 1, bytes.len, stream) == bytes.len;
}

/// Ganancia ReplayGain de las etiquetas ("-7.20 dB"), en dB y recortada.
fn replayGainDb(dec: *ch_decoder) f32 {
    const keys = [_][*c]const u8{ "REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_ALBUM_GAIN" };
    for (keys) |key| {
        const raw = ch_decode_tag(dec, key);
        if (raw == null) continue;
        const txt = std.mem.span(raw);
        if (txt.len == 0) continue;
        const end = std.mem.indexOfAny(u8, txt, " dD") orelse txt.len;
        const db = std.fmt.parseFloat(f32, txt[0..end]) catch continue;
        if (std.math.isFinite(db)) return std.math.clamp(db, -24, 12);
    }
    return 0;
}

/// Cadena de procesado del exportador: mismos bloques que `render()` y en el
/// mismo orden (EQ 36 bandas -> karaoke/9D/ancho/crossfeed/noche -> paisaje ->
/// balance -> limitador), pero con estado nuevo.
const ExportChain = struct {
    equalizer: eq.Equalizer = .{},
    dsp: dsp.Dsp = .{},
    soundscape: ambient.Soundscape = .{},
    balance: f32 = 0,
    gain: f32 = 1,
    limiting: bool = true,
    ceiling: f32 = 0.891,
    limit_gain: f32 = 1,
    dither: [CHANNELS]u32 = .{ 0x9E3779B9, 0x85EBCA6B },

    fn init(engine: ?*Engine) ExportChain {
        var c: ExportChain = .{};
        const e = engine orelse return c;
        c.equalizer.setPreamp(e.equalizer.preamp_db);
        c.equalizer.setGains(&e.eq_gains);
        c.dsp.applySettings(e.dsp.settings());
        c.soundscape.set(e.soundscape.presetValue(), e.soundscape.level());
        c.balance = @bitCast(@atomicLoad(u32, &e.balance_bits, .monotonic));
        c.limiting = e.limit_enabled;
        c.ceiling = e.limit_ceiling;
        return c;
    }

    fn process(self: *ExportChain, buf: []f32, frames: usize) void {
        self.equalizer.process(buf, frames);
        const release: f32 = 1.0 - @exp(-1.0 / (0.2 * @as(f32, @floatFromInt(SAMPLE_RATE))));
        const gain_l: f32 = 1 - @max(self.balance, 0);
        const gain_r: f32 = 1 + @min(self.balance, 0);
        var i: usize = 0;
        while (i < frames) : (i += 1) {
            var l = buf[i * CHANNELS];
            var r = buf[i * CHANNELS + 1];
            if (!self.dsp.isIdle()) {
                const shaped = self.dsp.process(l, r);
                l = shaped[0];
                r = shaped[1];
            }
            if (!self.soundscape.isIdle()) {
                const sc = self.soundscape.process();
                l += sc[0];
                r += sc[1];
            }
            if (self.balance != 0) {
                l *= gain_l;
                r *= gain_r;
            }
            l *= self.gain;
            r *= self.gain;
            if (self.limiting) {
                const peak = @max(@abs(l), @abs(r));
                var desired = self.limit_gain;
                if (peak > self.ceiling and peak > 0) desired = self.ceiling / peak;
                if (desired < self.limit_gain) {
                    self.limit_gain = desired; // ataque inmediato
                } else {
                    self.limit_gain += (desired - self.limit_gain) * release;
                }
                l *= self.limit_gain;
                r *= self.limit_gain;
            }
            buf[i * CHANNELS] = l;
            buf[i * CHANNELS + 1] = r;
        }
    }
};

/// Cuantos frames hay que escribir. Si el decodificador no sabe la duracion se
/// cuenta leyendo y se vuelve al punto de partida (doble pasada).
fn framesToWrite(dec: *ch_decoder, start_frame: u64, limit: u64, seekable: *bool) u64 {
    const rate: f64 = @floatFromInt(SAMPLE_RATE);
    const dur = ch_decode_duration(dec);
    if (dur > 0) {
        const total: u64 = @intFromFloat(dur * rate);
        if (total <= start_frame) return 0;
        return @min(limit, total - start_frame);
    }
    var counted: u64 = 0;
    var chunk: [EXPORT_CHUNK_FRAMES * CHANNELS]f32 = undefined;
    while (counted < limit) {
        const want: usize = @intCast(@min(@as(u64, EXPORT_CHUNK_FRAMES), limit - counted));
        const got = ch_decode_read(dec, &chunk, want);
        if (got == 0) break;
        counted += got;
    }
    seekable.* = ch_decode_seek_frame(dec, start_frame) == 0;
    return counted;
}

const ExportFmt = enum { s16, s24, f32, aiff16 };

fn renderWav(
    engine: ?*Engine,
    src: [*c]const u8,
    dst: [*c]const u8,
    start_sec: f64,
    end_sec: f64,
    fmt: ExportFmt,
) i32 {
    if (src == null or src[0] == 0 or dst == null or dst[0] == 0) return -1;
    if (!std.math.isFinite(start_sec) or !std.math.isFinite(end_sec)) return -1;
    if (start_sec < 0) return -1;
    if (end_sec > 0 and end_sec <= start_sec) return -1;

    const dec = ch_decode_open(src, SAMPLE_RATE, CHANNELS) orelse return -2;
    defer ch_decode_close(dec);

    const rate: f64 = @floatFromInt(SAMPLE_RATE);
    const start_frame: u64 = @intFromFloat(start_sec * rate);
    if (start_frame > 0 and ch_decode_seek_frame(dec, start_frame) != 0) return -2;

    var limit: u64 = std.math.maxInt(u64);
    if (end_sec > 0) limit = @intFromFloat((end_sec - start_sec) * rate);

    var seekable = true;
    const expected = framesToWrite(dec, start_frame, limit, &seekable);
    if (!seekable) return -2;
    const bytes_per_sample: u64 = switch (fmt) {
        .s16, .aiff16 => 2,
        .s24 => 3,
        .f32 => 4,
    };
    if (expected > (std.math.maxInt(u32) - 36) / (CHANNELS * bytes_per_sample)) return -5;

    var chain = ExportChain.init(engine);
    chain.gain = std.math.pow(f32, 10, replayGainDb(dec) / 20);

    const path: [*:0]const u8 = @ptrCast(dst);
    const stream = std.c.fopen(path, "wb") orelse return -3;
    defer _ = std.c.fclose(stream);

    const data_bytes = expected * CHANNELS * bytes_per_sample;
    switch (fmt) {
        .s16 => if (!writeAll(stream, &wavHeader(data_bytes))) return -4,
        .s24 => if (!writeAll(stream, &wavHeaderBits(data_bytes, 24, false))) return -4,
        .f32 => if (!writeAll(stream, &wavHeaderBits(data_bytes, 32, true))) return -4,
        .aiff16 => if (!writeAll(stream, &aiffHeader(data_bytes))) return -4,
    }

    var buf: [EXPORT_CHUNK_FRAMES * CHANNELS]f32 = undefined;
    var s16: [EXPORT_CHUNK_FRAMES * CHANNELS]i16 = undefined;
    // Buffer de bytes (máx 4 por muestra) para 24-bit / float / AIFF.
    var raw: [EXPORT_CHUNK_FRAMES * CHANNELS * 4]u8 = undefined;
    var written: u64 = 0;
    while (written < expected) {
        const want: usize = @intCast(@min(@as(u64, EXPORT_CHUNK_FRAMES), expected - written));
        const got = ch_decode_read(dec, &buf, want);
        if (got == 0) return -6; // el fichero se acabo antes de lo que decia
        const frames: usize = @intCast(got);
        const samples = frames * CHANNELS;
        chain.process(buf[0..samples], frames);
        switch (fmt) {
            .s16 => {
                var i: usize = 0;
                while (i < samples) : (i += 1) {
                    s16[i] = ch_audio_quantize_s16(buf[i], &chain.dither[i % CHANNELS]);
                }
                if (!writeAll(stream, std.mem.sliceAsBytes(s16[0..samples]))) return -4;
            },
            .s24 => {
                var i: usize = 0;
                while (i < samples) : (i += 1) {
                    const v: i32 = @intFromFloat(std.math.clamp(buf[i], -1, 1) * 8388607.0);
                    const u: u32 = @bitCast(v);
                    raw[i * 3] = @truncate(u);
                    raw[i * 3 + 1] = @truncate(u >> 8);
                    raw[i * 3 + 2] = @truncate(u >> 16);
                }
                if (!writeAll(stream, raw[0 .. samples * 3])) return -4;
            },
            .f32 => {
                var i: usize = 0;
                while (i < samples) : (i += 1) {
                    const bits: u32 = @bitCast(buf[i]);
                    raw[i * 4] = @truncate(bits);
                    raw[i * 4 + 1] = @truncate(bits >> 8);
                    raw[i * 4 + 2] = @truncate(bits >> 16);
                    raw[i * 4 + 3] = @truncate(bits >> 24);
                }
                if (!writeAll(stream, raw[0 .. samples * 4])) return -4;
            },
            .aiff16 => {
                var i: usize = 0;
                while (i < samples) : (i += 1) {
                    const v: i16 = ch_audio_quantize_s16(buf[i], &chain.dither[i % CHANNELS]);
                    const u: u16 = @bitCast(v);
                    raw[i * 2] = @truncate(u >> 8); // big-endian
                    raw[i * 2 + 1] = @truncate(u);
                }
                if (!writeAll(stream, raw[0 .. samples * 2])) return -4;
            },
        }
        written += got;
    }
    return 0;
}

/// Exporta [start_sec, end_sec) a un WAV 48 kHz estereo S16 con dither TPDF.
/// `end_sec <= 0` significa "hasta el final". La ganancia ReplayGain de las
/// etiquetas se aplica tal cual y un limitador de seguridad (-1 dBFS) evita el
/// recorte. Codigos: 0 bien, -1 argumentos, -2 origen (no abre o no busca),
/// -3 destino, -4 escritura, -5 demasiado largo, -6 origen truncado.
export fn ch_engine_render_wav(src: [*c]const u8, dst: [*c]const u8, start_sec: f64, end_sec: f64) i32 {
    return renderWav(null, src, dst, start_sec, end_sec, .s16);
}

/// Lo mismo, pero con el DSP del motor: EQ de 36 bandas, 9D, ancho/punch,
/// crossfeed, modo noche, paisaje, balance y limitador tal como estan puestos
/// ahora mismo ("exportar con mi sonido").
export fn ch_engine_render_wav_ex(
    self: ?*Engine,
    src: [*c]const u8,
    dst: [*c]const u8,
    start_sec: f64,
    end_sec: f64,
) i32 {
    return renderWav(self, src, dst, start_sec, end_sec, .s16);
}

/// Exporta a WAV PCM 24 bits (48 kHz estereo) con el DSP del motor.
export fn ch_engine_render_wav24(
    self: ?*Engine,
    src: [*c]const u8,
    dst: [*c]const u8,
    start_sec: f64,
    end_sec: f64,
) i32 {
    return renderWav(self, src, dst, start_sec, end_sec, .s24);
}

/// Exporta a WAV IEEE float 32 bits (48 kHz estereo) con el DSP del motor.
export fn ch_engine_render_wav_f32(
    self: ?*Engine,
    src: [*c]const u8,
    dst: [*c]const u8,
    start_sec: f64,
    end_sec: f64,
) i32 {
    return renderWav(self, src, dst, start_sec, end_sec, .f32);
}

/// Exporta a AIFF PCM 16 bits (48 kHz estereo) con el DSP del motor.
export fn ch_engine_render_aiff(
    self: ?*Engine,
    src: [*c]const u8,
    dst: [*c]const u8,
    start_sec: f64,
    end_sec: f64,
) i32 {
    return renderWav(self, src, dst, start_sec, end_sec, .aiff16);
}

test "paisaje: se enciende, se apaga y no rompe con punteros nulos" {
    const e = ch_engine_create() orelse return error.SinMotor;
    defer ch_engine_destroy(e);

    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_soundscape(null, 1, 1));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_soundscape(null, null));

    var level: f32 = -1;
    try std.testing.expectEqual(@as(i32, 0), ch_engine_soundscape(e, &level));
    try std.testing.expectEqual(@as(f32, 0), level);

    try std.testing.expectEqual(@as(i32, 1), ch_engine_set_soundscape(e, 1, 0.5));
    try std.testing.expectEqual(@as(i32, ambient.PRESET_RAIN), ch_engine_soundscape(e, &level));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), level, 1e-6);

    // Nivel 0 no suena aunque el preset siga puesto; preset raro -> apagado.
    try std.testing.expectEqual(@as(i32, 0), ch_engine_set_soundscape(e, 1, 0));
    try std.testing.expectEqual(@as(i32, 0), ch_engine_set_soundscape(e, 9, 1));
    try std.testing.expectEqual(@as(i32, ambient.PRESET_OFF), ch_engine_soundscape(e, null));
    try std.testing.expectEqual(@as(i32, 0), ch_engine_set_soundscape(e, 0, 1));
}

// ---- Utilidades de fichero para los tests (std.c, sin std.Io) ----

fn tmpDir() []const u8 {
    if (std.c.getenv("TMPDIR")) |p| {
        const s = std.mem.span(p);
        if (s.len > 0) return s;
    }
    if (std.c.getenv("TEMP")) |p| {
        const s = std.mem.span(p);
        if (s.len > 0) return s;
    }
    return "/tmp";
}

fn tmpPath(alloc: std.mem.Allocator, name: []const u8) ![:0]u8 {
    return std.fmt.allocPrintSentinel(alloc, "{s}/{s}", .{ tmpDir(), name }, 0);
}

fn readWhole(alloc: std.mem.Allocator, path: [:0]const u8) ![]u8 {
    const stream = std.c.fopen(path, "rb") orelse return error.NoAbre;
    defer _ = std.c.fclose(stream);
    var list: std.ArrayListUnmanaged(u8) = .empty;
    errdefer list.deinit(alloc);
    var chunk: [8192]u8 = undefined;
    while (true) {
        const got = std.c.fread(&chunk, 1, chunk.len, stream);
        if (got == 0) break;
        try list.appendSlice(alloc, chunk[0..got]);
    }
    return list.toOwnedSlice(alloc);
}

/// WAV S16 estereo 48 kHz de `seconds` con un click cada `period` segundos.
fn writeClickWav(path: [:0]const u8, seconds: f64, period: f64) !void {
    const rate: usize = SAMPLE_RATE;
    const frames: usize = @intFromFloat(seconds * @as(f64, @floatFromInt(rate)));
    const stream = std.c.fopen(path, "wb") orelse return error.NoCrea;
    defer _ = std.c.fclose(stream);
    if (!writeAll(stream, &wavHeader(@as(u64, frames) * CHANNELS * 2))) return error.NoEscribe;

    var chunk: [EXPORT_CHUNK_FRAMES * CHANNELS]i16 = undefined;
    var f: usize = 0;
    while (f < frames) {
        const n = @min(EXPORT_CHUNK_FRAMES, frames - f);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const t: f64 = @as(f64, @floatFromInt(f + i)) / @as(f64, @floatFromInt(rate));
            const frac = t / period - @floor(t / period);
            // Golpe de 8 ms con decaimiento exponencial.
            const s: f32 = if (frac * period < 0.008)
                @floatCast(0.8 * @exp(-frac * period / 0.002))
            else
                0;
            const v: i16 = @intFromFloat(std.math.clamp(s, -1, 1) * 32000);
            chunk[i * CHANNELS] = v;
            chunk[i * CHANNELS + 1] = v;
        }
        if (!writeAll(stream, std.mem.sliceAsBytes(chunk[0 .. n * CHANNELS]))) return error.NoEscribe;
        f += n;
    }
}

test "bpm: sin fichero devuelve 0" {
    try std.testing.expectEqual(@as(f64, 0), ch_engine_detect_bpm(null));
    try std.testing.expectEqual(@as(f64, 0), ch_engine_detect_bpm(""));
    try std.testing.expectEqual(@as(f64, 0), ch_engine_detect_bpm("/no/existe/chx.wav"));
}

test "exportador: escribe un WAV coherente y respeta el recorte" {
    const alloc = std.testing.allocator;
    const src = tmpPath(alloc, "chx_export_src.wav") catch return error.SkipZigTest;
    defer alloc.free(src);
    const dst = tmpPath(alloc, "chx_export_dst.wav") catch return error.SkipZigTest;
    defer alloc.free(dst);
    const dst2 = tmpPath(alloc, "chx_export_cut.wav") catch return error.SkipZigTest;
    defer alloc.free(dst2);
    defer _ = std.c.unlink(src);
    defer _ = std.c.unlink(dst);
    defer _ = std.c.unlink(dst2);

    writeClickWav(src, 2.0, 0.5) catch return error.SkipZigTest;
    // Sin decodificador (build sin miniaudio ni ffmpeg) el test no aplica.
    if (ch_decode_open(src, SAMPLE_RATE, CHANNELS)) |d| ch_decode_close(d) else return error.SkipZigTest;

    try std.testing.expectEqual(@as(i32, 0), ch_engine_render_wav(src, dst, 0, 0));
    const whole = try readWhole(alloc, dst);
    defer alloc.free(whole);
    try std.testing.expect(whole.len > 44);
    try std.testing.expectEqualStrings("RIFF", whole[0..4]);
    try std.testing.expectEqualStrings("WAVE", whole[8..12]);
    try std.testing.expectEqual(@as(u32, SAMPLE_RATE), std.mem.readInt(u32, whole[24..][0..4], .little));
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, whole[22..][0..2], .little));
    try std.testing.expectEqual(@as(u16, 16), std.mem.readInt(u16, whole[34..][0..2], .little));
    const data_bytes = std.mem.readInt(u32, whole[40..][0..4], .little);
    try std.testing.expectEqual(@as(u32, @intCast(whole.len)) - 44, data_bytes);
    try std.testing.expectEqual(@as(u32, @intCast(whole.len)) - 8, std.mem.readInt(u32, whole[4..][0..4], .little));
    // Dos segundos de audio, no vacio y sin recortes.
    try std.testing.expectEqual(@as(u32, 2 * SAMPLE_RATE * 4), data_bytes);
    var peak: u32 = 0;
    var nonzero: usize = 0;
    var k: usize = 44;
    while (k + 1 < whole.len) : (k += 2) {
        const v = std.mem.readInt(i16, whole[k..][0..2], .little);
        peak = @max(peak, @abs(@as(i32, v)));
        if (v != 0) nonzero += 1;
    }
    try std.testing.expect(nonzero > data_bytes / 200);
    try std.testing.expect(peak <= 32767);
    try std.testing.expect(peak > 3000);

    // Rango parcial: 0.05..0.15 s = 4800 frames.
    try std.testing.expectEqual(@as(i32, 0), ch_engine_render_wav(src, dst2, 0.05, 0.15));
    const cut = try readWhole(alloc, dst2);
    defer alloc.free(cut);
    try std.testing.expectEqual(@as(u32, 4800 * 4), std.mem.readInt(u32, cut[40..][0..4], .little));
    try std.testing.expectEqual(@as(usize, 44 + 4800 * 4), cut.len);
}

test "exportador: WAV 24-bit, WAV float32 y AIFF salen coherentes" {
    const alloc = std.testing.allocator;
    const src = tmpPath(alloc, "chx_fmt_src.wav") catch return error.SkipZigTest;
    defer alloc.free(src);
    const d24 = tmpPath(alloc, "chx_fmt_24.wav") catch return error.SkipZigTest;
    defer alloc.free(d24);
    const df32 = tmpPath(alloc, "chx_fmt_f32.wav") catch return error.SkipZigTest;
    defer alloc.free(df32);
    const daiff = tmpPath(alloc, "chx_fmt_aiff.aiff") catch return error.SkipZigTest;
    defer alloc.free(daiff);
    defer _ = std.c.unlink(src);
    defer _ = std.c.unlink(d24);
    defer _ = std.c.unlink(df32);
    defer _ = std.c.unlink(daiff);

    writeClickWav(src, 1.0, 0.25) catch return error.SkipZigTest;
    if (ch_decode_open(src, SAMPLE_RATE, CHANNELS)) |d| ch_decode_close(d) else return error.SkipZigTest;

    // --- WAV 24 bits: PCM (1), 24 bits, 3 bytes/muestra ---
    try std.testing.expectEqual(@as(i32, 0), ch_engine_render_wav24(null, src, d24, 0, 0));
    const w24 = try readWhole(alloc, d24);
    defer alloc.free(w24);
    try std.testing.expectEqualStrings("RIFF", w24[0..4]);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, w24[20..][0..2], .little));
    try std.testing.expectEqual(@as(u16, 24), std.mem.readInt(u16, w24[34..][0..2], .little));
    try std.testing.expectEqual(@as(u16, 6), std.mem.readInt(u16, w24[32..][0..2], .little));
    const data24 = std.mem.readInt(u32, w24[40..][0..4], .little);
    try std.testing.expectEqual(@as(u32, SAMPLE_RATE * 6), data24);
    try std.testing.expectEqual(@as(usize, 44 + @as(usize, data24)), w24.len);

    // --- WAV float32: formato IEEE (3), 32 bits ---
    try std.testing.expectEqual(@as(i32, 0), ch_engine_render_wav_f32(null, src, df32, 0, 0));
    const wf = try readWhole(alloc, df32);
    defer alloc.free(wf);
    try std.testing.expectEqualStrings("RIFF", wf[0..4]);
    try std.testing.expectEqual(@as(u16, 3), std.mem.readInt(u16, wf[20..][0..2], .little));
    try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(u16, wf[34..][0..2], .little));
    const dataf = std.mem.readInt(u32, wf[40..][0..4], .little);
    try std.testing.expectEqual(@as(u32, SAMPLE_RATE * 8), dataf);
    // El pico del click (0.8) debe existir como float finito en [-1,1].
    var peakf: f32 = 0;
    var kf: usize = 44;
    while (kf + 3 < wf.len) : (kf += 4) {
        const v = std.mem.readInt(u32, wf[kf..][0..4], .little);
        const fv: f32 = @bitCast(v);
        if (std.math.isFinite(fv)) peakf = @max(peakf, @abs(fv));
    }
    try std.testing.expect(peakf > 0.5);
    try std.testing.expect(peakf <= 1.0);

    // --- AIFF: FORM/AIFF big-endian, 16 bits, 54 bytes de cabecera ---
    try std.testing.expectEqual(@as(i32, 0), ch_engine_render_aiff(null, src, daiff, 0, 0));
    const wa = try readWhole(alloc, daiff);
    defer alloc.free(wa);
    try std.testing.expectEqualStrings("FORM", wa[0..4]);
    try std.testing.expectEqualStrings("AIFF", wa[8..12]);
    try std.testing.expectEqualStrings("COMM", wa[12..16]);
    try std.testing.expectEqualStrings("SSND", wa[40..44]);
    try std.testing.expectEqual(@as(u16, 16), std.mem.readInt(u16, wa[26..][0..2], .big));
    // 48000 Hz en extendido 80-bit.
    try std.testing.expectEqual(@as(u8, 0x40), wa[36]);
    try std.testing.expectEqual(@as(u8, 0x0E), wa[37]);
    // 1 s estereo S16 = SAMPLE_RATE*4 bytes de audio + 54 de cabecera.
    try std.testing.expectEqual(@as(usize, 54 + SAMPLE_RATE * 4), wa.len);
}

test "exportador: argumentos invalidos devuelven error sin crear nada" {
    try std.testing.expectEqual(@as(i32, -1), ch_engine_render_wav(null, "/tmp/x.wav", 0, 0));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_render_wav("", "/tmp/x.wav", 0, 0));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_render_wav("/tmp/x.wav", null, 0, 0));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_render_wav("/tmp/x.wav", "/tmp/x.wav", -1, 0));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_render_wav("/tmp/x.wav", "/tmp/x.wav", 5, 5));
    try std.testing.expectEqual(@as(i32, -2), ch_engine_render_wav("/no/existe.wav", "/tmp/x.wav", 0, 0));
    const nan_start = std.math.nan(f64);
    try std.testing.expectEqual(@as(i32, -1), ch_engine_render_wav("/no/existe.wav", "/tmp/x.wav", nan_start, 0));
}

test "exportador con DSP: el paisaje y el 9D cambian la salida" {
    const alloc = std.testing.allocator;
    const src = tmpPath(alloc, "chx_dsp_src.wav") catch return error.SkipZigTest;
    defer alloc.free(src);
    const flat = tmpPath(alloc, "chx_dsp_flat.wav") catch return error.SkipZigTest;
    defer alloc.free(flat);
    const wet = tmpPath(alloc, "chx_dsp_wet.wav") catch return error.SkipZigTest;
    defer alloc.free(wet);
    defer _ = std.c.unlink(src);
    defer _ = std.c.unlink(flat);
    defer _ = std.c.unlink(wet);

    writeClickWav(src, 1.0, 0.5) catch return error.SkipZigTest;
    if (ch_decode_open(src, SAMPLE_RATE, CHANNELS)) |d| ch_decode_close(d) else return error.SkipZigTest;

    const e = ch_engine_create() orelse return error.SinMotor;
    defer ch_engine_destroy(e);

    try std.testing.expectEqual(@as(i32, 0), ch_engine_render_wav_ex(e, src, flat, 0, 0));

    _ = ch_engine_set_soundscape(e, ambient.PRESET_RAIN, 1);
    _ = ch_engine_set_9d(e, 1, 0.3, 0.8);
    try std.testing.expectEqual(@as(i32, 0), ch_engine_render_wav_ex(e, src, wet, 0, 0));

    const a = try readWhole(alloc, flat);
    defer alloc.free(a);
    const b = try readWhole(alloc, wet);
    defer alloc.free(b);
    try std.testing.expectEqual(a.len, b.len);
    var diff: usize = 0;
    var i: usize = 44;
    while (i + 1 < a.len) : (i += 2) {
        if (a[i] != b[i]) diff += 1;
    }
    // Con paisaje y 9D la mayoria de las muestras tienen que cambiar.
    try std.testing.expect(diff > (a.len - 44) / 4);
}

test "bpm: el pulso de un WAV de clicks se detecta" {
    const alloc = std.testing.allocator;
    const src = tmpPath(alloc, "chx_bpm.wav") catch return error.SkipZigTest;
    defer alloc.free(src);
    defer _ = std.c.unlink(src);
    writeClickWav(src, 8.0, 0.5) catch return error.SkipZigTest; // 120 BPM
    const got = ch_engine_detect_bpm(src);
    if (got == 0) return error.SkipZigTest; // sin decodificador en este entorno
    try std.testing.expectApproxEqAbs(@as(f64, 120), got, 2.5);
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
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_9d(null, 1, 0.2, 0.5));
    try std.testing.expectEqual(@as(i32, 0), ch_engine_9d_enabled(null));
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_9d_speed(null));
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_9d_depth(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_stereo_enhance(null, 1.5, 0.5));
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_bass_punch(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_vocal_cut(null, 0.5));
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_vocal_cut(null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_night_mode(null, 1, 0.5));
    try std.testing.expectEqual(@as(i32, 0), ch_engine_night_mode(null, null));
    try std.testing.expectEqual(@as(i32, -1), ch_engine_set_s16_output(null, 1));
    try std.testing.expectEqual(@as(i32, 0), ch_engine_s16_output(null));
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

test "fase 2: los mandos DSP van y vuelven por la API C" {
    const e = ch_engine_create() orelse return error.SinMotor;
    defer ch_engine_destroy(e);

    try std.testing.expectEqual(@as(i32, 0), ch_engine_set_9d(e, 1, 0.5, 0.8));
    try std.testing.expectEqual(@as(i32, 1), ch_engine_9d_enabled(e));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), ch_engine_9d_speed(e), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), ch_engine_9d_depth(e), 1e-6);

    try std.testing.expectEqual(@as(i32, 0), ch_engine_set_stereo_enhance(e, 1.6, 0.7));
    try std.testing.expectApproxEqAbs(@as(f32, 1.6), ch_engine_stereo_width(e), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), ch_engine_bass_punch(e), 1e-6);

    try std.testing.expectEqual(@as(i32, 0), ch_engine_set_vocal_cut(e, 0.9));
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), ch_engine_vocal_cut(e), 1e-6);

    // La API recorta: velocidad y profundidad tienen rango, el karaoke 0..1.
    _ = ch_engine_set_9d(e, 1, 99, 9);
    try std.testing.expectEqual(dsp.MAX_SPEED_HZ, ch_engine_9d_speed(e));
    try std.testing.expectEqual(@as(f32, 1.0), ch_engine_9d_depth(e));
    _ = ch_engine_set_vocal_cut(e, -3);
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_vocal_cut(e));

    // El ancho historico sigue funcionando y comparte mando con el potenciador.
    _ = ch_engine_set_stereo_width(e, 0.0);
    try std.testing.expectEqual(@as(f32, 0.0), ch_engine_stereo_width(e));
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), ch_engine_bass_punch(e), 1e-6);

    // Al apagar el 9D no queda estado: volver a encenderlo arranca del centro.
    _ = ch_engine_set_9d(e, 0, 0.5, 0.8);
    try std.testing.expectEqual(@as(i32, 0), ch_engine_9d_enabled(e));

    // Crossfeed Bauer y modo noche.
    _ = ch_engine_set_crossfeed(e, 1, 0.35);
    var cf_level: f32 = 0;
    try std.testing.expectEqual(@as(i32, 1), ch_engine_crossfeed(e, &cf_level));
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), cf_level, 1e-6);

    _ = ch_engine_set_night_mode(e, 1, 0.6);
    var night_amount: f32 = 0;
    try std.testing.expectEqual(@as(i32, 1), ch_engine_night_mode(e, &night_amount));
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), night_amount, 1e-6);
    _ = ch_engine_set_night_mode(e, 0, 0.6);
    try std.testing.expectEqual(@as(i32, 0), ch_engine_night_mode(e, null));

    // Salida S16: el mando se recuerda aunque no haya dispositivo.
    _ = ch_engine_set_s16_output(e, 1);
    try std.testing.expectEqual(@as(i32, 1), ch_engine_s16_output(e));
    _ = ch_engine_set_s16_output(e, 0);
    try std.testing.expectEqual(@as(i32, 0), ch_engine_s16_output(e));
}

test "dither: TPDF de +-1 LSB, insesgado y reproducible" {
    // El error medio tiene que ser cero: eso es lo que hace el dither, meter
    // ruido a cambio de que la cuantizacion no sesgue el sonido.
    var state: u32 = 0x12345678;
    var sum: f64 = 0;
    var min_q: i16 = 32767;
    var max_q: i16 = -32768;
    const samples: usize = 20000;
    var i: usize = 0;
    while (i < samples) : (i += 1) {
        // Muestra constante: con dither la salida no es siempre el mismo entero.
        const q = ch_audio_quantize_s16(0.5, &state);
        sum += @as(f64, @floatFromInt(q)) - 0.5 * 32767.0;
        min_q = @min(min_q, q);
        max_q = @max(max_q, q);
    }
    const mean_error = sum / 20000.0;
    try std.testing.expect(@abs(mean_error) < 0.05); // sesgo practicamente nulo
    try std.testing.expectEqual(@as(i16, 16383), min_q);
    try std.testing.expectEqual(@as(i16, 16384), max_q);

    // Ruido triangular: la desviacion tipica baja, pero distinta de cero.
    var variance: f64 = 0;
    var s2: u32 = 0x12345678;
    i = 0;
    while (i < samples) : (i += 1) {
        const q = ch_audio_quantize_s16(0.5, &s2);
        const e = @as(f64, @floatFromInt(q)) - 0.5 * 32767.0;
        variance += e * e;
    }
    variance /= 20000.0;
    try std.testing.expect(variance > 0.02);
    try std.testing.expect(variance < 1.0);

    // Mismo estado inicial, misma secuencia: reproducible en los tests.
    var a: u32 = 42;
    var b: u32 = 42;
    try std.testing.expectEqual(ch_audio_quantize_s16(0.25, &a), ch_audio_quantize_s16(0.25, &b));
    try std.testing.expectEqual(ch_audio_quantize_s16(0.25, &a), ch_audio_quantize_s16(0.25, &b));

    // Recorte en los extremos y estado nulo admitido.
    var st: u32 = 7;
    try std.testing.expectEqual(@as(i16, 32767), ch_audio_quantize_s16(4.0, &st));
    try std.testing.expectEqual(@as(i16, -32768), ch_audio_quantize_s16(-4.0, &st));
    // Sin estado (NULL) tambien funciona: usa una semilla local y el dither
    // sigue siendo de +-1 LSB como mucho.
    const zero_a = ch_audio_quantize_s16(0.0, null);
    const zero_b = ch_audio_quantize_s16(0.0, null);
    try std.testing.expect(@abs(@as(i32, zero_a)) <= 1);
    try std.testing.expect(@abs(@as(i32, zero_b)) <= 1);
}
