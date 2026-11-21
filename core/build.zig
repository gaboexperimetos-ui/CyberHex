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
        // Android: si FFmpeg está compilado para esta ABI, se enlaza estático
        // (cobertura total). Si no, miniaudio cubre WAV/FLAC/MP3/Vorbis.
        const abi_name: ?[]const u8 = switch (target.result.cpu.arch) {
            .aarch64 => "arm64-v8a",
            .arm => "armeabi-v7a",
            .x86_64 => "x86_64",
            .x86 => "x86",
            else => null,
        };
        const use_ffmpeg = b.option(bool, "android-ffmpeg", "Enlazar FFmpeg estático en Android") orelse true;
        if (use_ffmpeg and abi_name != null) {
            const abi = abi_name.?;
            mod.addIncludePath(b.path(b.pathJoin(&.{ "third_party", "ffmpeg-android", abi, "include" })));
            mod.addLibraryPath(b.path(b.pathJoin(&.{ "third_party", "ffmpeg-android", abi, "lib" })));
            mod.addCSourceFiles(.{
                .files = &.{ "src/audio.c", "src/decode_ffmpeg.c", "src/playlist.c", "src/lyrics.c", "src/library.c", "src/markers.c", "src/cue.c", "src/fileio.c" },
                .flags = &.{ "-std=c23", "-O2" },
            });
            mod.linkSystemLibrary("avformat", .{});
            mod.linkSystemLibrary("avcodec", .{});
            mod.linkSystemLibrary("avutil", .{});
            mod.linkSystemLibrary("swresample", .{});
            mod.linkSystemLibrary("m", .{});
            mod.linkSystemLibrary("dl", .{});
        } else {
            mod.addCSourceFiles(.{
                .files = &.{ "src/audio.c", "src/decode_miniaudio.c", "src/playlist.c", "src/lyrics.c", "src/library.c", "src/markers.c", "src/cue.c", "src/fileio.c" },
                .flags = &.{ "-std=c23", "-O2" },
            });
        }
    } else {
        // Escritorio: FFmpeg cubre prácticamente todos los formatos de audio.
        mod.addCSourceFiles(.{
            .files = &.{ "src/audio.c", "src/decode_ffmpeg.c", "src/playlist.c", "src/lyrics.c", "src/library.c", "src/markers.c", "src/cue.c", "src/fileio.c" },
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
