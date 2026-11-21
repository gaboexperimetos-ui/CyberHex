const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const is_android = target.result.os.tag == .linux and target.result.abi.isAndroid();

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mod.addIncludePath(b.path("vendor"));
    mod.addIncludePath(b.path("src"));

    if (is_android) {
        // Android: miniaudio decodifica los formatos que soporta nativamente.
        mod.addCSourceFiles(.{
            .files = &.{ "src/audio.c", "src/decode_miniaudio.c" },
            .flags = &.{ "-std=c23", "-O2" },
        });
    } else {
        // Escritorio: FFmpeg cubre prácticamente todos los formatos de audio.
        mod.addCSourceFiles(.{
            .files = &.{ "src/audio.c", "src/decode_ffmpeg.c" },
            .flags = &.{ "-std=c23", "-O2" },
        });
        mod.linkSystemLibrary("avformat", .{});
        mod.linkSystemLibrary("avcodec", .{});
        mod.linkSystemLibrary("avutil", .{});
        mod.linkSystemLibrary("swresample", .{});
    }

    if (target.result.os.tag == .linux and !is_android) {
        mod.linkSystemLibrary("m", .{});
        mod.linkSystemLibrary("dl", .{});
        mod.linkSystemLibrary("pthread", .{});
    }

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "cyberhex_core",
        .root_module = mod,
    });
    b.installArtifact(lib);
    b.installFile("include/cyberhex_core.h", "include/cyberhex_core.h");

    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Ejecuta los tests del núcleo");
    test_step.dependOn(&run_tests.step);
}
