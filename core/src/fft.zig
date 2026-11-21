const std = @import("std");

/// FFT radix-2 en sitio. `re` e `im` deben tener la misma longitud,
/// potencia de dos.
pub fn fft(re: []f32, im: []f32) void {
    const n = re.len;
    std.debug.assert(im.len == n and std.math.isPowerOfTwo(n));
    if (n <= 1) return;

    var j: usize = 0;
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var bit = n >> 1;
        while (j & bit != 0) : (bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            const tr = re[i];
            re[i] = re[j];
            re[j] = tr;
            const ti = im[i];
            im[i] = im[j];
            im[j] = ti;
        }
    }

    var len: usize = 2;
    while (len <= n) : (len <<= 1) {
        const half = len / 2;
        const ang = -2.0 * std.math.pi / @as(f32, @floatFromInt(len));
        const wlen_re = @cos(ang);
        const wlen_im = @sin(ang);
        var start: usize = 0;
        while (start < n) : (start += len) {
            var w_re: f32 = 1;
            var w_im: f32 = 0;
            var k: usize = 0;
            while (k < half) : (k += 1) {
                const a = start + k;
                const b = a + half;
                const v_re = re[b] * w_re - im[b] * w_im;
                const v_im = re[b] * w_im + im[b] * w_re;
                re[b] = re[a] - v_re;
                im[b] = im[a] - v_im;
                re[a] += v_re;
                im[a] += v_im;
                const nw_re = w_re * wlen_re - w_im * wlen_im;
                w_im = w_re * wlen_im + w_im * wlen_re;
                w_re = nw_re;
            }
        }
    }
}

test "fft detecta la frecuencia de un tono" {
    const n = 2048;
    const sr: f32 = 48000;
    var re: [n]f32 = undefined;
    var im: [n]f32 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / sr;
        const w = 0.5 - 0.5 * @cos(2.0 * std.math.pi * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1)));
        re[i] = @sin(2.0 * std.math.pi * 1000.0 * t) * w;
        im[i] = 0;
    }
    fft(&re, &im);

    var best: usize = 1;
    var best_mag: f32 = 0;
    var k: usize = 1;
    while (k < n / 2) : (k += 1) {
        const mag = @sqrt(re[k] * re[k] + im[k] * im[k]);
        if (mag > best_mag) {
            best_mag = mag;
            best = k;
        }
    }
    const freq = @as(f32, @floatFromInt(best)) * sr / @as(f32, @floatFromInt(n));
    try std.testing.expect(@abs(freq - 1000.0) < 30.0);
}
