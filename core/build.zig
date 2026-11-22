const std = @import("std");

/// Decodificador de audio del núcleo.
const Decoder = enum {
    /// FFmpeg si se puede enlazar; si no, miniaudio (WAV/FLAC/MP3/Vorbis).
    auto,
    /// Exige FFmpeg (cobertura total: AAC, ALAC, WMA, ...).
    ffmpeg,
    /// Solo miniaudio/dr_*: sin dependencias externas.
    miniaudio,
};

/// Ejecuta un comando en tiempo de configuración y dice si salió bien.
/// Se usa para decidir el decodificador sin exigir nada al usuario.
fn probe(b: *std.Build, argv: []const []const u8) bool {
    switch (b.runFallible(argv, .{})) {
        .success => return true,
        else => return false,
    }
}

/// ¿Hay FFmpeg de desarrollo en el sistema? (pkg-config es lo canónico)
fn haveFfmpegSystem(b: *std.Build) bool {
    return probe(b, &.{ "pkg-config", "--exists", "libavcodec", "libavformat" });
}

/// ¿Están compiladas las librerías FFmpeg para esta ABI de Android?
fn haveFfmpegAndroid(b: *std.Build, abi: []const u8) bool {
    return probe(b, &.{
        "sh", "-c", b.fmt("test -f third_party/ffmpeg-android/{s}/lib/libavformat.a", .{abi}),
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const is_android = target.result.os.tag == .linux and target.result.abi.isAndroid();
    const decoder = b.option(
        Decoder,
        "decoder",
        "Decodificador: auto (por defecto), ffmpeg o miniaudio",
    ) orelse .auto;

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mod.addIncludePath(b.path("vendor"));
    mod.addIncludePath(b.path("src"));
    mod.addIncludePath(b.path("include"));

    // Un solo bloque decide el decodificador para las dos plataformas: escritorio
    // (FFmpeg del sistema, con vuelta a miniaudio si no está) y Android (FFmpeg
    // estático por ABI si se compiló con build_ffmpeg_android.sh).
    var use_ffmpeg = false;
    var ffmpeg_abi: []const u8 = "";

    if (is_android) {
        const abi_name: ?[]const u8 = switch (target.result.cpu.arch) {
            .aarch64 => "arm64-v8a",
            .arm => "armeabi-v7a",
            .x86_64 => "x86_64",
            .x86 => "x86",
            else => null,
        };
        const requested = b.option(
            bool,
            "android-ffmpeg",
            "Enlazar FFmpeg estático en Android si está compilado",
        ) orelse true;
        const ready = if (abi_name) |abi| haveFfmpegAndroid(b, abi) else false;
        use_ffmpeg = requested and decoder != .miniaudio and ready;
        if (use_ffmpeg) {
            ffmpeg_abi = abi_name.?;
        } else if (requested and decoder != .miniaudio) {
            std.debug.print(
                "aviso: sin FFmpeg para {s}; se compila con miniaudio " ++
                    "(WAV/FLAC/MP3/Vorbis). Ejecuta ./build_ffmpeg_android.sh para tener cobertura total.\n",
                .{abi_name orelse "esta ABI"},
            );
        }
    } else {
        const headers = haveFfmpegSystem(b);
        switch (decoder) {
            .ffmpeg => if (!headers) {
                // Falla el build con un mensaje claro (y sin traza de pila).
                b.getInstallStep().dependOn(&b.addFail(
                    "no encuentro FFmpeg: instala libavcodec-dev/libavformat-dev " ++
                        "(Arch: pacman -S ffmpeg; Debian: apt install libavcodec-dev libavformat-dev) " ++
                        "o compila con -Ddecoder=miniaudio",
                ).step);
                return;
            },
            .auto => use_ffmpeg = headers,
            .miniaudio => use_ffmpeg = false,
        }
        if (!headers and decoder == .auto) {
            std.debug.print(
                "aviso: sin FFmpeg en este sistema; se compila con miniaudio " ++
                    "(WAV/FLAC/MP3/Vorbis). Instala libav*-dev para cobertura total.\n",
                .{},
            );
        }
    }

    const decoder_source = if (use_ffmpeg) "src/decode_ffmpeg.c" else "src/decode_miniaudio.c";
    mod.addCSourceFiles(.{
        .files = &.{
            "src/audio.c",
            decoder_source,
            "src/playlist.c",
            "src/lyrics.c",
            "src/library.c",
            "src/markers.c",
            // Nuevas del núcleo de main: R128/picos, hojas CUE y guardado de carátula.
            "src/cue.c",
            "src/fileio.c",
            "src/analysis.c",
            "src/tags.c",
            "src/ogg_tags.c",
            "src/dirlist.c",
        },
        .flags = &.{ "-std=c23", "-O2" },
    });

    if (use_ffmpeg) {
        if (is_android) {
            mod.addIncludePath(b.path(b.pathJoin(&.{ "third_party", "ffmpeg-android", ffmpeg_abi, "include" })));
            mod.addLibraryPath(b.path(b.pathJoin(&.{ "third_party", "ffmpeg-android", ffmpeg_abi, "lib" })));
        }
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

    // Prueba de humo contra el motor de verdad: sintetiza un WAV, reproduce,
    // mide niveles, pausa, loop A-B y los ajustes nuevos. Sirve igual en el PC
    // (`zig build smoke`) y en el teléfono (adb push + adb shell).
    const smoke_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    smoke_mod.addCSourceFile(.{ .file = b.path("tests/smoke.c"), .flags = &.{ "-std=c23" } });
    smoke_mod.addIncludePath(b.path("include"));
    smoke_mod.linkLibrary(lib);
    const smoke_exe = b.addExecutable(.{ .name = "cyberhex_smoke", .root_module = smoke_mod });

    const run_smoke = b.addRunArtifact(smoke_exe);
    if (b.option([]const u8, "smoke-dir", "Carpeta donde escribir el WAV de la prueba de humo")) |dir| {
        run_smoke.addArg(dir);
    }
    const smoke_step = b.step("smoke", "Prueba de humo con audio real (necesita salida de audio)");
    smoke_step.dependOn(&run_smoke.step);
    b.installArtifact(smoke_exe);
}
