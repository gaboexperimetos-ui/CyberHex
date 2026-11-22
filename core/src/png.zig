//! Escritura de PNG sin dependencias externas.
//!
//! Zig no trae un codificador de PNG y no queremos arrastrar libpng al nucleo
//! (ni a Android), asi que se emite un PNG valido a mano: deflate con bloques
//! "stored" (sin comprimir, BTYPE=00) mas adler32, y CRC32 por chunk. Sirve
//! para graficas de forma de onda y esceptro, donde el coste de no comprimir
//! es aceptable.

const std = @import("std");

fn crcTable() [256]u32 {
    @setEvalBranchQuota(10000);
    var t: [256]u32 = undefined;
    for (0..256) |i| {
        var c: u32 = @intCast(i);
        var k: usize = 0;
        while (k < 8) : (k += 1) {
            c = if (c & 1 != 0) 0xEDB88320 ^ (c >> 1) else c >> 1;
        }
        t[i] = c;
    }
    return t;
}

const CRC_TABLE = crcTable();

fn crc32(bytes: []const u8, seed: u32) u32 {
    var c = seed;
    for (bytes) |b| c = CRC_TABLE[@as(usize, @as(u8, @truncate(c)) ^ b)] ^ (c >> 8);
    return c;
}

fn adler32(bytes: []const u8) u32 {
    var a: u32 = 1;
    var b: u32 = 0;
    for (bytes) |byte| {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    return (b << 16) | a;
}

fn be32(out: []u8, v: u32) void {
    out[0] = @truncate(v >> 24);
    out[1] = @truncate(v >> 16);
    out[2] = @truncate(v >> 8);
    out[3] = @truncate(v);
}

/// Lienzo RGB de 8 bits por canal.
pub const Canvas = struct {
    width: usize,
    height: usize,
    pixels: []u8, // width*height*3

    pub fn create(allocator: std.mem.Allocator, width: usize, height: usize) !Canvas {
        if (width == 0 or height == 0) return error.InvalidSize;
        const px = try allocator.alloc(u8, width * height * 3);
        @memset(px, 0);
        return .{ .width = width, .height = height, .pixels = px };
    }

    pub fn set(self: *Canvas, x: usize, y: usize, r: u8, g: u8, b: u8) void {
        if (x >= self.width or y >= self.height) return;
        const i = (y * self.width + x) * 3;
        self.pixels[i] = r;
        self.pixels[i + 1] = g;
        self.pixels[i + 2] = b;
    }

    /// Rellena el rectangulo [x0,x1) x [y0,y1) con recorte al lienzo.
    pub fn fillRect(self: *Canvas, x0: usize, x1: usize, y0: usize, y1: usize, r: u8, g: u8, b: u8) void {
        const xa = @min(x0, self.width);
        const xb = @min(x1, self.width);
        const ya = @min(y0, self.height);
        const yb = @min(y1, self.height);
        var y = ya;
        while (y < yb) : (y += 1) {
            var x = xa;
            while (x < xb) : (x += 1) self.set(x, y, r, g, b);
        }
    }
};

/// Escribe `canvas` como PNG RGB en `path` usando la E/S en C del nucleo.
/// Devuelve 0 si ok.
pub fn write(allocator: std.mem.Allocator, path: []const u8, canvas: Canvas) i32 {
    const row_bytes = canvas.width * 3;
    const raw = allocator.alloc(u8, (row_bytes + 1) * canvas.height) catch return -1;
    defer allocator.free(raw);

    // Filtro 0 (None) al principio de cada scanline.
    var o: usize = 0;
    var y: usize = 0;
    while (y < canvas.height) : (y += 1) {
        raw[o] = 0;
        o += 1;
        @memcpy(raw[o .. o + row_bytes], canvas.pixels[y * row_bytes .. (y + 1) * row_bytes]);
        o += row_bytes;
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    out.appendSlice(allocator, &[_]u8{ 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A }) catch return -1;

    // IHDR
    var ihdr: [13]u8 = undefined;
    be32(ihdr[0..4], @intCast(canvas.width));
    be32(ihdr[4..8], @intCast(canvas.height));
    ihdr[8] = 8; // bit depth
    ihdr[9] = 2; // color type RGB
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    writeChunk(allocator, &out, "IHDR", &ihdr) catch return -2;

    // IDAT: zlib (0x78 0x01) + deflate "stored" + adler32.
    var z: std.ArrayList(u8) = .empty;
    defer z.deinit(allocator);
    z.appendSlice(allocator, &[_]u8{ 0x78, 0x01 }) catch return -1;
    var pos: usize = 0;
    while (pos < raw.len) {
        const n = @min(raw.len - pos, 65535);
        const last: u8 = if (pos + n >= raw.len) 1 else 0;
        z.append(allocator, last) catch return -1;
        const len: u16 = @intCast(n);
        z.append(allocator, @truncate(len)) catch return -1;
        z.append(allocator, @truncate(len >> 8)) catch return -1;
        z.append(allocator, @truncate(~len)) catch return -1;
        z.append(allocator, @truncate(~len >> 8)) catch return -1;
        z.appendSlice(allocator, raw[pos .. pos + n]) catch return -1;
        pos += n;
    }
    var ad: [4]u8 = undefined;
    be32(&ad, adler32(raw));
    z.appendSlice(allocator, &ad) catch return -1;
    writeChunk(allocator, &out, "IDAT", z.items) catch return -2;

    writeChunk(allocator, &out, "IEND", "") catch return -2;

    const ch_file_write_atomic = @extern(*const fn ([*:0]const u8, [*]const u8, u64) callconv(.c) i32, .{ .name = "ch_file_write_atomic" });
    const path_z = allocator.allocSentinel(u8, path.len, 0) catch return -1;
    defer allocator.free(path_z);
    @memcpy(path_z, path);
    return ch_file_write_atomic(path_z.ptr, out.items.ptr, out.items.len);
}

fn writeChunk(allocator: std.mem.Allocator, out: *std.ArrayList(u8), kind: *const [4]u8, data: []const u8) !void {
    var hdr: [8]u8 = undefined;
    be32(hdr[0..4], @intCast(data.len));
    @memcpy(hdr[4..8], kind);
    try out.appendSlice(allocator, &hdr);
    try out.appendSlice(allocator, data);
    var c = crc32(kind, 0xFFFFFFFF);
    c = crc32(data, c);
    var crcb: [4]u8 = undefined;
    be32(&crcb, c ^ 0xFFFFFFFF);
    try out.appendSlice(allocator, &crcb);
}

test "el lienzo coloca pixeles y recorta lo que se sale" {
    const allocator = std.testing.allocator;
    var c = try Canvas.create(allocator, 4, 3);
    defer allocator.free(c.pixels);
    c.set(1, 1, 255, 128, 0);
    try std.testing.expectEqual(@as(u8, 255), c.pixels[(1 * 4 + 1) * 3]);
    try std.testing.expectEqual(@as(u8, 128), c.pixels[(1 * 4 + 1) * 3 + 1]);
    c.fillRect(0, 99, 0, 1, 1, 2, 3);
    try std.testing.expectEqual(@as(u8, 1), c.pixels[0]);
    try std.testing.expectEqual(@as(u8, 2), c.pixels[1]);
    try std.testing.expectEqual(@as(u8, 3), c.pixels[2]);
}

test "el PNG escrito tiene firma, IHDR y CRC correctos" {
    const allocator = std.testing.allocator;
    var c = try Canvas.create(allocator, 2, 2);
    defer allocator.free(c.pixels);
    c.set(0, 0, 10, 20, 30);

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    // Redirigimos la escritura a memoria comprobando el codificador de chunks.
    try writeChunk(allocator, &buf, "IHDR", &[_]u8{ 0, 0, 0, 1 });
    try std.testing.expectEqual(@as(usize, 16), buf.items.len); // 8 (len+tipo) + 4 datos + 4 CRC
    const kind = buf.items[4..8];
    try std.testing.expectEqualSlices(u8, "IHDR", kind);
    const len = std.mem.readInt(u32, buf.items[0..4], .big);
    try std.testing.expectEqual(@as(u32, 4), len);
    const crc = std.mem.readInt(u32, buf.items[buf.items.len - 4 ..][0..4], .big);
    var c2 = crc32("IHDR", 0xFFFFFFFF);
    c2 = crc32(buf.items[8 .. 8 + 4], c2);
    try std.testing.expectEqual(crc, c2 ^ 0xFFFFFFFF);
}
