const std = @import("std");

/// Decodificador de audio del núcleo.
pub const Decoder = enum {
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
fn haveFfmpegAndroid(b: *std.Build, source_dir: []const u8, abi: []const u8) bool {
    return probe(b, &.{
        "sh", "-c", b.fmt("test -f {s}/third_party/ffmpeg-android/{s}/lib/libavformat.a", .{ source_dir, abi }),
    });
}

/// Resultado de construir el núcleo.
pub const Core = struct {
    /// Módulo Zig/C ya configurado (fuente `root.zig` + srcs).
    module: *std.Build.Module,
    /// Librería dinámica `libcyberhex_core.{so,dll,dylib}`.
    lib: *std.Build.Step.Compile,
};

/// Construye el módulo del núcleo y la librería dinámica. Lo usa tanto el
/// `build()` de este archivo (build de `core/` aislado) como el `build.zig` del
/// root, que necesita el mismo núcleo dentro de un bundle mayor (runner Flutter,
/// assets, etc.) sin duplicar la lógica de decodificador.
///
/// `source_dir` es la ruta relativa (desde la raíz del build) donde vive el
/// directorio `core/` — cadena vacía si se construye desde `core/build.zig`.
pub fn addCore(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    decoder: Decoder,
    source_dir: []const u8,
) Core {
    const is_android = target.result.os.tag == .linux and target.result.abi.isAndroid();

    const mod = b.createModule(.{
        .root_source_file = b.path(joined(b, source_dir, "src/root.zig")),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mod.addIncludePath(b.path(joined(b, source_dir, "vendor")));
    mod.addIncludePath(b.path(joined(b, source_dir, "src")));
    mod.addIncludePath(b.path(joined(b, source_dir, "include")));

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
        const ready = if (abi_name) |abi| haveFfmpegAndroid(b, source_dir, abi) else false;
        use_ffmpeg = decoder != .miniaudio and ready;
        if (use_ffmpeg) {
            ffmpeg_abi = abi_name.?;
        } else if (decoder != .miniaudio) {
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
                return .{ .module = mod, .lib = undefined };
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
    // `root` ancla los fuentes al directorio `core/` tanto si se construye desde
    // aquí como desde el `build.zig` del root (donde la raíz es el proyecto).
    const src_root: ?std.Build.LazyPath = if (source_dir.len == 0) null else b.path(source_dir);
    mod.addCSourceFiles(.{
        .root = src_root,
        .files = &.{
            "src/audio.c",
            "src/error.c",
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
            const rel_inc = b.fmt("third_party/ffmpeg-android/{s}/include", .{ffmpeg_abi});
            const rel_lib = b.fmt("third_party/ffmpeg-android/{s}/lib", .{ffmpeg_abi});
            mod.addIncludePath(b.path(joined(b, source_dir, rel_inc)));
            mod.addLibraryPath(b.path(joined(b, source_dir, rel_lib)));
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
    b.installFile(joined(b, source_dir, "include/cyberhex_core.h"), "include/cyberhex_core.h");

    return .{ .module = mod, .lib = lib };
}

/// Une `prefix` (opcional) con `rest` (ruta relativa, puede contener '/') de
/// forma portable. Si `prefix` está vacío devuelve solo `rest` (caso de
/// `core/build.zig` aislado, donde la raíz del build ya es `core/`).
fn joined(b: *std.Build, prefix: []const u8, rest: []const u8) []const u8 {
    if (prefix.len == 0) return rest;
    return b.pathJoin(&.{ prefix, rest });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const decoder = b.option(
        Decoder,
        "decoder",
        "Decodificador: auto (por defecto), ffmpeg o miniaudio",
    ) orelse .auto;

    const core = addCore(b, target, optimize, decoder, "");

    const tests = b.addTest(.{ .root_module = core.module });
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
    smoke_mod.linkLibrary(core.lib);
    const smoke_exe = b.addExecutable(.{ .name = "cyberhex_smoke", .root_module = smoke_mod });

    const run_smoke = b.addRunArtifact(smoke_exe);
    if (b.option([]const u8, "smoke-dir", "Carpeta donde escribir el WAV de la prueba de humo")) |dir| {
        run_smoke.addArg(dir);
    }
const smoke_step = b.step("smoke", "Prueba de humo con audio real (necesita salida de audio)");
    smoke_step.dependOn(&run_smoke.step);
    b.installArtifact(smoke_exe);

    // Unit tests per module (linked against core.lib)
    addUnitTest(b, target, optimize, core.lib, "tags", "tests/test_tags.c");
    addUnitTest(b, target, optimize, core.lib, "cue", "tests/test_cue.c");
    addUnitTest(b, target, optimize, core.lib, "analysis", "tests/test_analysis.c");
    addUnitTest(b, target, optimize, core.lib, "markers", "tests/test_markers.c");
    addUnitTest(b, target, optimize, core.lib, "library", "tests/test_library.c");
    addUnitTest(b, target, optimize, core.lib, "playlist", "tests/test_playlist.c");
    addUnitTest(b, target, optimize, core.lib, "fileio", "tests/test_fileio.c");
    addUnitTest(b, target, optimize, core.lib, "dirlist", "tests/test_dirlist.c");
    addUnitTest(b, target, optimize, core.lib, "lyrics", "tests/test_lyrics.c");
    addUnitTest(b, target, optimize, core.lib, "ogg_tags", "tests/test_ogg_tags.c");
}

fn addUnitTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib: *std.Build.Step.Compile,
    comptime name: []const u8,
    src: []const u8,
) void {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addCSourceFile(.{ .file = b.path(src), .flags = &.{ "-std=c23" } });
    mod.addIncludePath(b.path("include"));
    mod.addIncludePath(b.path("src"));
    mod.linkLibrary(lib);
    const exe = b.addExecutable(.{ .name = "test_" ++ name, .root_module = mod });
    const run = b.addRunArtifact(exe);
    const step = b.step("test-" ++ name, "Test unitario: " ++ name);
    step.dependOn(&run.step);
    b.installArtifact(exe);
}