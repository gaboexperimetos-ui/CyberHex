const std = @import("std");

const core = @import("core/build.zig");

/// Modo de empaquetado del runner Flutter.
const BundleMode = enum {
    /// AOT (libapp.so) + flutter_assets + runner, listo para distribuir.
    release,
    /// Sin AOT; el bundle no incluye libapp.so (solo útil para pruebas locales).
    debug,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });

    const decoder = b.option(
        core.Decoder,
        "decoder",
        "Decodificador del núcleo: auto (por defecto), ffmpeg o miniaudio",
    ) orelse .auto;

    // Ruta al binario `flutter`. Si no se pasa, se usa el de PATH.
    const flutter_opt = b.option(
        []const u8,
        "flutter",
        "Ruta al binario `flutter` (por defecto: el de PATH)",
    );

    // Modo del bundle derivado de -Drelease / -Doptimize (ya declarados por
    // standardOptimizeOption). ReleaseFast/ReleaseSafe/ReleaseSmall => AOT.
    const bundle_mode: BundleMode = switch (optimize) {
        .Debug => .debug,
        else => .release,
    };

    // ── Núcleo nativo (Zig + C23) ────────────────────────────────────────────
    // Siempre se construye para el target pedido; el mismo build.zig sirve para
    // escritorio, cross a Windows/macOS y Android (vía -Dtarget).
    const built_core = core.addCore(b, target, optimize, decoder, "core");

    // ── Runner Flutter (solo Linux desktop) ──────────────────────────────────
    // Es el único escritorio para el que este repo trae fuentes C++ del runner
    // (`linux/runner`). Para Windows/macOS se deja que `flutter build` use su
    // propio runner y recoja el núcleo que aquí producimos con -Dtarget.
    const is_linux = target.result.os.tag == .linux and !target.result.abi.isAndroid();

    var runner: ?*std.Build.Step.Compile = null;
    var fa: ?FlutterArtifacts = null;

    if (is_linux) {
        fa = setupFlutter(b, target, flutter_opt, bundle_mode);
        runner = buildLinuxRunner(b, fa.?, built_core);
    }

    // ── Steps ────────────────────────────────────────────────────────────────
    const core_step = b.step("core", "Compila solo el núcleo nativo (libcyberhex_core)");
    core_step.dependOn(&b.addInstallArtifact(built_core.lib, .{}).step);

    // Paso por defecto (`zig build` / `zig build install`): ensambla el bundle.
    const install_step = b.getInstallStep();

    if (runner) |r| {
        assembleLinuxBundle(b, install_step, r, fa.?, built_core);
        const flutter_step = b.step("flutter", "Ejecuta `flutter assemble` (assets + AOT) para Linux");
        flutter_step.dependOn(fa.?.assemble_step);
        const runner_step = b.step("runner", "Compila el runner C++ de Linux");
        runner_step.dependOn(&r.step);
    } else {
        installCoreOnly(b, install_step, target, built_core);
    }
}

/// Artefactos de Flutter que necesita el bundle de Linux.
const FlutterArtifacts = struct {
    /// Step que ejecuta `flutter assemble` (assets + AOT).
    assemble_step: *std.Build.Step,
    flutter_assets: std.Build.LazyPath,
    libapp_so: ?std.Build.LazyPath,
    icu_data: std.Build.LazyPath,
    flutter_lib: std.Build.LazyPath,
    flutter_headers: std.Build.LazyPath,
    engine_dir: std.Build.LazyPath,
};

/// Prepara todo lo de Flutter para el runner de Linux (sin CMake).
fn setupFlutter(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    flutter_opt: ?[]const u8,
    bundle_mode: BundleMode,
) FlutterArtifacts {
    const flutter = flutter_opt orelse "flutter";
    const flutter_root = resolveFlutterRoot(b, flutter);

    const arch = switch (target.result.cpu.arch) {
        .x86_64 => "linux-x64",
        .aarch64 => "linux-arm64",
        else => "linux-x64",
    };

    // El motor de release (AOT) vive en `linux-x64-release`; el de debug/JIT en
    // `linux-x64`. Hay que usar el que corresponde al modo del bundle.
    const build_mode: []const u8 = switch (bundle_mode) {
        .release => "release",
        .debug => "debug",
    };
    // Directorio base del motor (siempre existe): aporta icudtl.dat y las
    // cabeceras flutter_linux/. El .so concreto se toma del directorio variante.
    const base_dir = b.fmt("{s}/bin/cache/artifacts/engine/{s}", .{ flutter_root, arch });
    const engine_dir = switch (bundle_mode) {
        .release => b.fmt("{s}-release", .{base_dir}),
        .debug => base_dir,
    };

    // `flutter assemble` vuelca flutter_assets/ y lib/libapp.so en un directorio
    // bajo .zig-cache (ignorado por git), sin tocar el árbol fuente. Se usa una
    // ruta relativa fija porque `--output` se resuelve en tiempo de ejecución
    // (cwd = raíz del build) y necesito referenciarla también en config-time.
    const assemble_out_rel = ".zig-cache/cyberhex/flutter";
    const assemble_out = b.path(assemble_out_rel);

    const assemble_target = b.fmt("{s}_bundle_{s}_assets", .{ build_mode, arch });

    const out_arg = b.fmt("--output={s}", .{assemble_out_rel});
    const tp_arg = b.fmt("-dTargetPlatform={s}", .{arch});
    const bm_arg = b.fmt("-dBuildMode={s}", .{build_mode});

    const run = b.addSystemCommand(&.{
        flutter,
        "assemble",
        "--no-version-check",
        out_arg,
        tp_arg,
        bm_arg,
        "-dTargetFile=lib/main.dart",
        "-dTreeShakeIcons=true",
        "-dBuildName=1.0.0",
        "-dBuildNumber=1",
        assemble_target,
    });
    run.setName("flutter-assemble");

    return .{
        .assemble_step = &run.step,
        .flutter_assets = assemble_out.path(b, "flutter_assets"),
        .libapp_so = if (bundle_mode == .release) assemble_out.path(b, "lib/libapp.so") else null,
        .icu_data = .{ .cwd_relative = b.fmt("{s}/icudtl.dat", .{base_dir}) },
        .flutter_lib = .{ .cwd_relative = b.fmt("{s}/libflutter_linux_gtk.so", .{engine_dir}) },
        .flutter_headers = .{ .cwd_relative = b.fmt("{s}/flutter_linux", .{base_dir}) },
        .engine_dir = .{ .cwd_relative = engine_dir },
    };
}

/// Resuelve `flutterRoot` ejecutando `flutter --version --machine`.
fn resolveFlutterRoot(b: *std.Build, flutter: []const u8) []const u8 {
    const out = switch (b.runFallible(&.{ flutter, "--version", "--machine" }, .{})) {
        .success => |s| s,
        else => blk: {
            std.debug.print(
                "aviso: no pude ejecutar `{s} --version --machine`; " ++
                    "se asume FLUTTER_ROOT=/flutter\n",
                .{flutter},
            );
            break :blk "/flutter";
        },
    };
    const key = "\"flutterRoot\":";
    const idx = std.mem.indexOf(u8, out, key) orelse return "/flutter";
    var rest = out[idx + key.len ..];
    rest = std.mem.trim(u8, rest, " \t\r\n");
    if (rest.len == 0 or rest[0] != '"') return "/flutter";
    rest = rest[1..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return "/flutter";
    return rest[0..end];
}

/// Compila el runner C++ de Linux y lo enlaza contra el motor Flutter y GTK.
fn buildLinuxRunner(b: *std.Build, fa: FlutterArtifacts, built_core: core.Core) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "cyberhex",
        .root_module = b.createModule(.{
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });
    const m = exe.root_module;

    // Flags de pkg-config (includes + libs) para GTK/glib/gio.
    const gtk_cflags = pkgConfigCFlags(b, "gtk+-3.0 glib-2.0 gio-2.0");

    // includes de gtk/glib como include paths del módulo.
    for (gtk_cflags) |f| {
        if (std.mem.startsWith(u8, f, "-I")) {
            m.addIncludePath(.{ .cwd_relative = f[2..] });
        } else if (std.mem.startsWith(u8, f, "-D")) {
            const body = f[2..];
            if (std.mem.indexOfScalar(u8, body, '=')) |eq| {
                m.addCMacro(body[0..eq], body[eq + 1 ..]);
            } else {
                m.addCMacro(body, "1");
            }
        } else if (std.mem.eql(u8, f, "-pthread")) {
            // se ignora; pthread ya viene por gtk
        }
    }

    // includes del runner y del motor Flutter.
    m.addIncludePath(b.path("linux"));
    m.addIncludePath(b.path("linux/runner"));
    m.addIncludePath(b.path("linux/flutter"));
    m.addIncludePath(fa.flutter_headers);
    m.addIncludePath(fa.engine_dir);

    // Fuentes del runner + registrant de plugins.
    m.addCSourceFile(.{ .file = b.path("linux/runner/main.cc"), .flags = &.{"-std=c++17"} });
    m.addCSourceFile(.{ .file = b.path("linux/runner/my_application.cc"), .flags = &.{"-std=c++17"} });
    m.addCSourceFile(.{ .file = b.path("linux/runner/mpris_bridge.cc"), .flags = &.{"-std=c++17"} });
    m.addCSourceFile(.{ .file = b.path("linux/flutter/generated_plugin_registrant.cc"), .flags = &.{"-std=c++17"} });

    // Plugin `file_selector_linux` (si está en el pub-cache).
    if (linuxPluginDir(b)) |plugin_dir| {
        m.addCSourceFile(.{ .file = absPath(b, plugin_dir, "file_selector_plugin.cc"), .flags = &.{"-std=c++17"} });
        m.addCSourceFile(.{ .file = absPath(b, plugin_dir, "messages.g.cc"), .flags = &.{"-std=c++17"} });
        m.addIncludePath(absPath(b, plugin_dir, "include"));
        m.addIncludePath(.{ .cwd_relative = plugin_dir });
    }

    // Enlazar motor Flutter + GTK.
    m.addLibraryPath(fa.engine_dir);
    m.linkSystemLibrary("flutter_linux_gtk", .{});
    m.linkSystemLibrary("gtk-3", .{});
    m.linkSystemLibrary("gdk-3", .{});
    m.linkSystemLibrary("gobject-2.0", .{});
    m.linkSystemLibrary("glib-2.0", .{});
    m.linkSystemLibrary("gio-2.0", .{});

    // RPATH $ORIGIN/lib: el bundle encuentra libcyberhex_core.so y el motor sin
    // LD_LIBRARY_PATH.
    m.addRPathSpecial("$ORIGIN/lib");

    // APPLICATION_ID (lo usa my_application.cc).
    m.addCMacro("APPLICATION_ID", "\"com.gaboexperimetos.cyberhex\"");

    // El runner no depende del núcleo en sí (va al bundle por separado), pero
    // conviene que compilar el runner arrastre el núcleo al mismo `zig build`.
    exe.step.dependOn(&built_core.lib.step);

    return exe;
}

/// flags de pkg-config tokenizados (cada -I / -D / -pthread es un token).
fn pkgConfigCFlags(b: *std.Build, pkgs: []const u8) [][]const u8 {
    const out = switch (b.runFallible(&.{ "pkg-config", "--cflags", pkgs }, .{})) {
        .success => |s| s,
        else => return &.{},
    };
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
    while (it.next()) |tok| list.append(b.allocator, tok) catch @panic("OOM");
    return list.items;
}

/// Construye una LazyPath absoluta a partir de un directorio base y un nombre.
fn absPath(b: *std.Build, base: []const u8, name: []const u8) std.Build.LazyPath {
    return .{ .cwd_relative = b.pathJoin(&.{ base, name }) };
}

/// Directorio del plugin `file_selector_linux` en el pub-cache, si existe.
fn linuxPluginDir(b: *std.Build) ?[]const u8 {
    const cfg = std.Io.Dir.cwd().readFileAlloc(
        b.graph.io,
        ".dart_tool/package_config.json",
        b.allocator,
        .limited(1 << 20),
    ) catch return null;
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, cfg, search_from, "\"file_selector_linux\"")) |i| {
        const window_end = @min(cfg.len, i + 500);
        const window = cfg[i..window_end];
        const ru = std.mem.indexOf(u8, window, "\"rootUri\":") orelse {
            search_from = i + 1;
            continue;
        };
        var rest = std.mem.trim(u8, window[ru + "\"rootUri\":".len ..], " \t");
        if (rest.len == 0 or rest[0] != '"') {
            search_from = i + 1;
            continue;
        }
        rest = rest[1..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse {
            search_from = i + 1;
            continue;
        };
        var uri = rest[0..end];
        if (std.mem.startsWith(u8, uri, "file://")) uri = uri["file://".len..];
        const linux = b.fmt("{s}/linux", .{uri});
        std.Io.Dir.cwd().access(b.graph.io, linux, .{}) catch {
            search_from = i + 1;
            continue;
        };
        return linux;
    }
    return null;
}

/// Ensambla el bundle completo de Linux en zig-out.
fn assembleLinuxBundle(
    b: *std.Build,
    install_step: *std.Build.Step,
    runner: *std.Build.Step.Compile,
    fa: FlutterArtifacts,
    built_core: core.Core,
) void {
    install_step.dependOn(&b.addInstallFileWithDir(runner.getEmittedBin(), .prefix, "cyberhex").step);
    install_step.dependOn(&b.addInstallFileWithDir(fa.flutter_lib, .prefix, "lib/libflutter_linux_gtk.so").step);
    install_step.dependOn(&b.addInstallFileWithDir(built_core.lib.getEmittedBin(), .prefix, "lib/libcyberhex_core.so").step);

    // libapp.so y flutter_assets los produce `flutter assemble`: estos pasos
    // deben ir DESPUÉS de assemble, no solo después de install_step.
    if (fa.libapp_so) |app_so| {
        const s = b.addInstallFileWithDir(app_so, .prefix, "lib/libapp.so");
        s.step.dependOn(fa.assemble_step);
        install_step.dependOn(&s.step);
    }

    install_step.dependOn(&b.addInstallFileWithDir(fa.icu_data, .prefix, "data/icudtl.dat").step);

    const assets_install = b.addInstallDirectory(.{
        .source_dir = fa.flutter_assets,
        .install_dir = .prefix,
        .install_subdir = "data/flutter_assets",
    });
    assets_install.step.dependOn(fa.assemble_step);
    install_step.dependOn(&assets_install.step);
}

/// Instala solo el núcleo y su cabecera (Android/Windows/macOS cross).
fn installCoreOnly(
    b: *std.Build,
    install_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    built_core: core.Core,
) void {
    // En Android, el .so va a jniLibs/<abi>/ para que Gradle lo empaquete en el
    // APK sin tener que recompilarlo. En escritorio se instala en lib/.
    const is_android = target.result.os.tag == .linux and target.result.abi.isAndroid();
    if (is_android) {
        const abi = androidAbi(target.result.cpu.arch) orelse "arm64-v8a";
        const dest = b.fmt("jniLibs/{s}/libcyberhex_core.so", .{abi});
        install_step.dependOn(&b.addInstallFileWithDir(built_core.lib.getEmittedBin(), .prefix, dest).step);
        install_step.dependOn(&b.addInstallFileWithDir(b.path("core/include/cyberhex_core.h"), .prefix, "include/cyberhex_core.h").step);
        return;
    }
    install_step.dependOn(&b.addInstallFileWithDir(built_core.lib.getEmittedBin(), .prefix, "lib/libcyberhex_core.so").step);
    install_step.dependOn(&b.addInstallFileWithDir(b.path("core/include/cyberhex_core.h"), .prefix, "include/cyberhex_core.h").step);
}

/// Traduce la arquitectura Zig al nombre de ABI de Android.
fn androidAbi(arch: std.Target.Cpu.Arch) ?[]const u8 {
    return switch (arch) {
        .aarch64 => "arm64-v8a",
        .arm => "armeabi-v7a",
        .x86_64 => "x86_64",
        .x86 => "x86",
        else => null,
    };
}