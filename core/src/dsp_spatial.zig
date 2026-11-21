//! Procesadores DSP del nucleo, en tiempo real y sin candados.
//!
//! Todo lo que suena aqui se ejecuta dentro del callback de audio: no se
//! reserva memoria, no se bloquea y todos los parametros viven en atomics
//! (`std.atomic.Value`) que la UI escribe desde otro hilo. Un parametro a medio
//! escribir nunca parte una muestra: los flotantes viajan como bits en un u32.
//!
//!  * `Spatial9D`: rotacion azimutal continua con ITD (retardo interaural de
//!    hasta 0.75 ms), ILD (diferencia de nivel) y sombra craneal (pasa-bajos en
//!    el oido que se aleja). Pensado para auriculares.
//!  * `StereoEnhancer`: matriz Mid/Side para el ancho (0 mono .. 2 ultra) y
//!    realce armonico de graves (`bass punch`) antes del limitador.
//!  * `VocalCut`: karaoke Mid/Side que atenua el centro por encima de ~130 Hz
//!    y deja intactos los subgraves, para no matar el ritmo.
//!
//! Mantiene el contrato §8.2: 48 kHz estereo fijos, nada de remuestrear.

const std = @import("std");

/// Frecuencia de trabajo del motor (§8.2: fija, no se negocia).
pub const SAMPLE_RATE: f32 = 48000;

/// Retardo interaural maximo: 0.75 ms a 48 kHz.
pub const ITD_MAX_FRAMES: usize = 36;

/// Corte del pasa-bajos de sombra craneal (oido opuesto).
pub const SHADOW_HZ: f32 = 3000;

/// Corte del separador del karaoke: por encima se atenua el centro.
pub const VOCAL_CUT_HZ: f32 = 130;

/// Banda del realce de graves.
pub const BASS_HZ: f32 = 120;
pub const BASS_HP_HZ: f32 = 35;

pub const MIN_SPEED_HZ: f32 = 0.05;
pub const MAX_SPEED_HZ: f32 = 2.0;

inline fn onePole(hz: f32) f32 {
    return 1.0 - @exp(-2.0 * std.math.pi * hz / SAMPLE_RATE);
}

inline fn fbits(value: f32) u32 {
    return @bitCast(value);
}

inline fn toFloat(bits: u32) f32 {
    return @bitCast(bits);
}

fn clampf(value: f32, lo: f32, hi: f32) f32 {
    if (!(value > lo)) return lo;
    if (value > hi) return hi;
    return value;
}

/// Rotacion 9D: el frente gira en azimut a `speed_hz` vueltas por segundo.
///
/// Por muestra:
///  1. avanza la fase y calcula `pan = sin(fase) * depth`, entre -1 y 1;
///  2. el frente (mono) pasa por una linea de retardo de la que se leen dos
///     puntos simetricos: el oido lejano recibe la señal hasta 0.75 ms despues;
///  3. se aplica ILD con ganancias de potencia constante (centro = sin cambio);
///  4. el oido que se aleja se filtra con un pasa-bajos (sombra de la cabeza);
///  5. el lateral vuelve sin retardo, algo mas estrecho al girar.
pub const Spatial9D = struct {
    enabled: std.atomic.Value(bool) = .init(false),
    speed_bits: std.atomic.Value(u32) = .init(fbits(0.15)),
    depth_bits: std.atomic.Value(u32) = .init(fbits(0.65)),

    /// Linea de retardo del frente; 2 muestras de margen sobre el ITD maximo.
    delay: [ITD_MAX_FRAMES + 2]f32 = @splat(0),
    pos: usize = 0,
    phase: f32 = 0,
    shadow_l: f32 = 0,
    shadow_r: f32 = 0,

    pub fn set(self: *Spatial9D, on: bool, speed_hz: f32, depth_amount: f32) void {
        self.enabled.store(on, .monotonic);
        self.speed_bits.store(fbits(clampf(speed_hz, MIN_SPEED_HZ, MAX_SPEED_HZ)), .monotonic);
        self.depth_bits.store(fbits(clampf(depth_amount, 0, 1)), .monotonic);
    }

    pub fn isEnabled(self: *const Spatial9D) bool {
        return self.enabled.load(.monotonic);
    }

    pub fn speed(self: *const Spatial9D) f32 {
        return toFloat(self.speed_bits.load(.monotonic));
    }

    pub fn depth(self: *const Spatial9D) f32 {
        return toFloat(self.depth_bits.load(.monotonic));
    }

    /// Vuelve al centro y olvida el estado (al apagar, al cambiar de pista).
    pub fn reset(self: *Spatial9D) void {
        @memset(&self.delay, 0);
        self.pos = 0;
        self.phase = 0;
        self.shadow_l = 0;
        self.shadow_r = 0;
    }

    fn read(self: *const Spatial9D, back: isize) f32 {
        const len: isize = @intCast(self.delay.len);
        const idx = @mod(@as(isize, @intCast(self.pos)) - back, len);
        return self.delay[@intCast(idx)];
    }

    pub fn process(self: *Spatial9D, in_l: f32, in_r: f32) [2]f32 {
        if (!self.enabled.load(.monotonic)) return .{ in_l, in_r };
        const amount = clampf(self.depth(), 0, 1);
        if (amount <= 0) return .{ in_l, in_r };
        const revolutions = clampf(self.speed(), MIN_SPEED_HZ, MAX_SPEED_HZ);

        self.phase += revolutions / SAMPLE_RATE;
        if (self.phase >= 1.0) self.phase -= @floor(self.phase);
        const pan = @sin(self.phase * 2.0 * std.math.pi) * amount;

        const mid = (in_l + in_r) * 0.5;
        const side = (in_l - in_r) * 0.5;

        // ITD: se escribe el frente y se leen dos puntos alrededor del centro.
        self.pos = (self.pos + 1) % self.delay.len;
        self.delay[self.pos] = mid;
        const centre: f32 = @floatFromInt(ITD_MAX_FRAMES / 2);
        const shift: isize = @intFromFloat(@round(pan * centre));
        const mid_l = self.read(@as(isize, @intCast(ITD_MAX_FRAMES / 2)) + shift);
        const mid_r = self.read(@as(isize, @intCast(ITD_MAX_FRAMES / 2)) - shift);

        // ILD de potencia constante: en el centro gl = gr = 1 (sin caida).
        const gl = @sqrt(@max(1.0 - pan, 0.0));
        const gr = @sqrt(@max(1.0 + pan, 0.0));

        // Sombra craneal solo en el oido que se aleja (alpha 1 = sin filtrar).
        const shadow_alpha = onePole(SHADOW_HZ);
        const a_l = 1.0 + (shadow_alpha - 1.0) * clampf(pan, 0, 1);
        const a_r = 1.0 + (shadow_alpha - 1.0) * clampf(-pan, 0, 1);
        self.shadow_l += (mid_l - self.shadow_l) * a_l;
        self.shadow_r += (mid_r - self.shadow_r) * a_r;

        // Al girar, el lateral se estrecha un poco para no sonar roto.
        const side_gain = 1.0 - 0.25 * amount;
        return .{
            self.shadow_l * gl + side * side_gain,
            self.shadow_r * gr - side * side_gain,
        };
    }
};

/// Potenciador estereo: ancho Mid/Side y realce armonico de graves.
///
/// El ancho reutiliza el mando historico `ch_engine_set_stereo_width`
/// (0 = mono, 1 = natural, 2 = ultra ancho). El `punch` aisla la banda grave,
/// la satura con `tanh` y devuelve solo los armonicos que aparecen: sube la
/// pegada sin inflar el nivel ni comerse el limitador.
pub const StereoEnhancer = struct {
    width_bits: std.atomic.Value(u32) = .init(fbits(1.0)),
    punch_bits: std.atomic.Value(u32) = .init(fbits(0.0)),

    bass_lp: f32 = 0,
    bass_hp: f32 = 0,

    pub fn set(self: *StereoEnhancer, new_width: f32, new_punch: f32) void {
        self.width_bits.store(fbits(clampf(new_width, 0, 2)), .monotonic);
        self.punch_bits.store(fbits(clampf(new_punch, 0, 1)), .monotonic);
    }

    pub fn setWidth(self: *StereoEnhancer, new_width: f32) void {
        self.width_bits.store(fbits(clampf(new_width, 0, 2)), .monotonic);
    }

    pub fn width(self: *const StereoEnhancer) f32 {
        return toFloat(self.width_bits.load(.monotonic));
    }

    pub fn punch(self: *const StereoEnhancer) f32 {
        return toFloat(self.punch_bits.load(.monotonic));
    }

    /// Armonicos del grave aislado (sin DC) que se suman al centro.
    fn punchExtra(self: *StereoEnhancer, mid: f32, drive_amount: f32) f32 {
        self.bass_lp += (mid - self.bass_lp) * onePole(BASS_HZ);
        self.bass_hp += (self.bass_lp - self.bass_hp) * onePole(BASS_HP_HZ);
        const bass = self.bass_lp - self.bass_hp;
        if (bass == 0) return 0;
        // tanh comprime y genera armonicos impares; el residuo es lo que se oye.
        const driven = bass * (1.0 + 4.0 * drive_amount);
        const harmonic = std.math.tanh(driven) - bass;
        return harmonic * 0.35 * drive_amount;
    }

    pub fn process(self: *StereoEnhancer, in_l: f32, in_r: f32) [2]f32 {
        const w = clampf(self.width(), 0, 2);
        const pk = clampf(self.punch(), 0, 1);
        if (w == 1.0 and pk <= 0) return .{ in_l, in_r };

        var mid = (in_l + in_r) * 0.5;
        const side = (in_l - in_r) * 0.5 * w;
        if (pk > 0) mid += self.punchExtra(mid, pk);
        return .{ mid + side, mid - side };
    }
};

/// Modo karaoke: quita el centro (voz) y conserva los subgraves.
///
/// El centro se separa con un pasa-bajos de dos polos a 130 Hz: lo que queda
/// por debajo se deja pasar entero (el bombo y el bajo no se tocan) y lo de
/// arriba se atenua segun `amount`. Se compensa la perdida del filtro para que
/// el grave no baje de nivel al subir `amount`.
pub const VocalCut = struct {
    amount_bits: std.atomic.Value(u32) = .init(fbits(0.0)),

    low1: f32 = 0,
    low2: f32 = 0,

    pub fn set(self: *VocalCut, new_amount: f32) void {
        self.amount_bits.store(fbits(clampf(new_amount, 0, 1)), .monotonic);
    }

    pub fn amount(self: *const VocalCut) f32 {
        return toFloat(self.amount_bits.load(.monotonic));
    }

    pub fn process(self: *VocalCut, in_l: f32, in_r: f32) [2]f32 {
        const level = clampf(self.amount(), 0, 1);
        if (level <= 0) return .{ in_l, in_r };

        const mid = (in_l + in_r) * 0.5;
        const side = (in_l - in_r) * 0.5;

        const alpha = onePole(VOCAL_CUT_HZ);
        self.low1 += (mid - self.low1) * alpha;
        self.low2 += (self.low1 - self.low2) * alpha;

        // Dos polos: |H| = (|H1|)^2, de ahi la compensacion del grave.
        const low = self.low2 * (1.0 + 0.22 * level);
        const high = mid - self.low2;
        const cut_mid = low + high * (1.0 - level);
        return .{ cut_mid + side, cut_mid - side };
    }
};

/// Cadena completa en el orden en que suena.
pub const Dsp = struct {
    vocal: VocalCut = .{},
    spatial: Spatial9D = .{},
    enhancer: StereoEnhancer = .{},

    pub fn process(self: *Dsp, in_l: f32, in_r: f32) [2]f32 {
        const cut = self.vocal.process(in_l, in_r);
        const space = self.spatial.process(cut[0], cut[1]);
        return self.enhancer.process(space[0], space[1]);
    }

    /// ¿Hay algo encendido? Evita recorrer la cadena cuando no hace falta.
    pub fn isIdle(self: *const Dsp) bool {
        return !self.spatial.isEnabled() and
            self.vocal.amount() <= 0 and
            self.enhancer.punch() <= 0 and
            self.enhancer.width() == 1.0;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Amplitud estimada de una sinusoide por proyeccion en cuadratura.
fn amplitude(samples: []const f32, freq: f32) f64 {
    const w = 2.0 * std.math.pi * freq / SAMPLE_RATE;
    var re: f64 = 0;
    var im: f64 = 0;
    for (samples, 0..) |x, i| {
        const phase = w * @as(f64, @floatFromInt(i));
        re += @as(f64, x) * @cos(phase);
        im += @as(f64, x) * @sin(phase);
    }
    const n: f64 = @floatFromInt(@max(samples.len, 1));
    return @sqrt(re * re + im * im) * 2.0 / n;
}

fn sineInto(buffer: []f32, freq: f32, gain: f32) void {
    for (buffer, 0..) |*slot, i| {
        const t = @as(f32, @floatFromInt(i)) / SAMPLE_RATE;
        slot.* += gain * @sin(2.0 * std.math.pi * freq * t);
    }
}

test "9d: apagado es identidad exacta" {
    var spatial: Spatial9D = .{};
    const out = spatial.process(0.3, -0.2);
    try std.testing.expectEqual(@as(f32, 0.3), out[0]);
    try std.testing.expectEqual(@as(f32, -0.2), out[1]);
}

test "9d: profundidad cero no toca la señal" {
    var spatial: Spatial9D = .{};
    spatial.set(true, 0.5, 0);
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        const x = @sin(2.0 * std.math.pi * 220.0 * @as(f32, @floatFromInt(i)) / SAMPLE_RATE);
        const out = spatial.process(x, x);
        try std.testing.expectApproxEqAbs(x, out[0], 1e-6);
        try std.testing.expectApproxEqAbs(x, out[1], 1e-6);
    }
}

test "9d: la rotacion separa los canales (ITD + ILD + sombra)" {
    var spatial: Spatial9D = .{};
    spatial.set(true, 1.0, 1.0);

    var diff_sum: f64 = 0;
    var right_louder: usize = 0;
    const frames = 48000; // una vuelta completa a 1 Hz
    var i: usize = 0;
    while (i < frames) : (i += 1) {
        const x = 0.5 * @sin(2.0 * std.math.pi * 440.0 * @as(f32, @floatFromInt(i)) / SAMPLE_RATE);
        const out = spatial.process(x, x); // señal mono: todo el efecto es del motor
        diff_sum += @abs(out[0] - out[1]);
        if (out[1] > out[0] + 0.01) right_louder += 1;
    }
    const mean_diff = diff_sum / @as(f64, frames);
    // Sin 9D, un tono mono da canales identicos (diferencia 0).
    try std.testing.expect(mean_diff > 0.02);
    // La imagen gira: hay tramos en los que manda la derecha y tramos la izquierda.
    try std.testing.expect(right_louder > 1000);
}

test "9d: la fase no se escapa y el retardo no pasa de 0.75 ms" {
    var spatial: Spatial9D = .{};
    spatial.set(true, 2.0, 1.0);
    var i: usize = 0;
    while (i < 200000) : (i += 1) {
        _ = spatial.process(0.1, 0.1);
    }
    try std.testing.expect(spatial.phase >= 0 and spatial.phase < 1.0);
    // 36 frames a 48 kHz son 0.75 ms exactos (el maximo del contrato).
    try std.testing.expect(@as(f32, @floatFromInt(ITD_MAX_FRAMES)) / SAMPLE_RATE <= 0.00075);
}

test "9d: parametros fuera de rango se recortan" {
    var spatial: Spatial9D = .{};
    spatial.set(true, 99, 3);
    try std.testing.expectEqual(@as(f32, MAX_SPEED_HZ), spatial.speed());
    try std.testing.expectEqual(@as(f32, 1.0), spatial.depth());
    spatial.set(true, -1, -1);
    try std.testing.expectEqual(@as(f32, MIN_SPEED_HZ), spatial.speed());
    try std.testing.expectEqual(@as(f32, 0.0), spatial.depth());
}

test "estereo: ancho 0 colapsa a mono y ancho 2 duplica el lateral" {
    var enhancer: StereoEnhancer = .{};
    enhancer.set(0, 0);
    const mono = enhancer.process(0.8, 0.2);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), mono[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), mono[1], 1e-6);

    enhancer.set(2, 0);
    const wide = enhancer.process(0.8, 0.2);
    try std.testing.expectApproxEqAbs(@as(f32, 1.1), wide[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, -0.1), wide[1], 1e-6);
}

test "estereo: ancho 1 sin punch es identidad" {
    var enhancer: StereoEnhancer = .{};
    enhancer.set(1, 0);
    const out = enhancer.process(0.3, -0.7);
    try std.testing.expectEqual(@as(f32, 0.3), out[0]);
    try std.testing.expectEqual(@as(f32, -0.7), out[1]);
}

test "estereo: el punch de graves genera armonicos sin perder el fundamental" {
    var enhancer: StereoEnhancer = .{};
    enhancer.set(1, 0);

    const frames = 4800;
    var clean: [frames]f32 = @splat(0);
    var punched: [frames]f32 = @splat(0);
    sineInto(&clean, 60, 0.45);

    // Se procesa la señal por la cadena, muestra a muestra.
    enhancer.set(1, 1);
    var i: usize = 0;
    while (i < frames) : (i += 1) {
        const out = enhancer.process(clean[i], clean[i]);
        punched[i] = out[0];
    }

    const fundamental = amplitude(&punched, 60);
    const harmonic = amplitude(&punched, 180);
    // El fundamental sigue ahi (no es un filtro) y aparece un 3er armonico.
    try std.testing.expect(fundamental > 0.30);
    try std.testing.expect(harmonic > 0.01);
    try std.testing.expect(harmonic < fundamental);
}

test "karaoke: corta el centro agudo y conserva los subgraves" {
    var vocal: VocalCut = .{};
    vocal.set(1);

    const frames = 9600;
    var source: [frames]f32 = @splat(0);
    sineInto(&source, 60, 0.4); // bombo/bajo por el centro
    sineInto(&source, 1000, 0.4); // voz por el centro
    var out: [frames]f32 = @splat(0);

    var i: usize = 0;
    while (i < frames) : (i += 1) {
        const r = vocal.process(source[i], source[i]);
        out[i] = r[0];
    }

    const bass = amplitude(&out, 60);
    const voice = amplitude(&out, 1000);
    // El grave se queda practicamente igual...
    try std.testing.expect(bass > 0.4 * 0.85);
    // ...y la voz desaparece.
    try std.testing.expect(voice < 0.4 * 0.12);
    try std.testing.expect(voice < bass * 0.3);
}

test "karaoke: sin amount no filtra nada" {
    var vocal: VocalCut = .{};
    const out = vocal.process(0.25, -0.5);
    try std.testing.expectEqual(@as(f32, 0.25), out[0]);
    try std.testing.expectEqual(@as(f32, -0.5), out[1]);
}

test "cadena: con todo apagado es la identidad" {
    var dsp: Dsp = .{};
    try std.testing.expect(dsp.isIdle());
    const out = dsp.process(0.11, -0.42);
    try std.testing.expectEqual(@as(f32, 0.11), out[0]);
    try std.testing.expectEqual(@as(f32, -0.42), out[1]);
}
