import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'player_api.dart';

typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();

typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);

typedef _LoadNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _LoadDart = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _ControlNative = Int32 Function(Pointer<Void>);
typedef _ControlDart = int Function(Pointer<Void>);

typedef _SeekNative = Int32 Function(Pointer<Void>, Double);
typedef _SeekDart = int Function(Pointer<Void>, double);

typedef _VolumeNative = Int32 Function(Pointer<Void>, Float);
typedef _VolumeDart = int Function(Pointer<Void>, double);

typedef _EqCountNative = Int32 Function();
typedef _EqCountDart = int Function();

typedef _EqGainsNative = Int32 Function(Pointer<Void>, Pointer<Float>, Int32);
typedef _EqGainsDart = int Function(Pointer<Void>, Pointer<Float>, int);

typedef _EqFreqNative = Float Function(Int32);
typedef _EqFreqDart = double Function(int);

typedef _DoubleNative = Double Function(Pointer<Void>);
typedef _DoubleDart = double Function(Pointer<Void>);

typedef _IntNative = Int32 Function(Pointer<Void>);
typedef _IntDart = int Function(Pointer<Void>);

typedef _TextNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _TextDart = Pointer<Utf8> Function(Pointer<Void>);

typedef _CoverAtNative = Pointer<Uint8> Function(
    Pointer<Void>, Int32, Pointer<Uint64>);
typedef _CoverAtDart = Pointer<Uint8> Function(
    Pointer<Void>, int, Pointer<Uint64>);

typedef _PlainTextNative = Pointer<Utf8> Function();
typedef _PlainTextDart = Pointer<Utf8> Function();

/// Espejo de `ch_event` (core/include/cyberhex_core.h).
final class _ChEvent extends Struct {
  @Int32()
  external int kind;

  @Int32()
  external int a;

  @Int32()
  external int b;

  @Double()
  external double value;
}

typedef _PollEventNative = Int32 Function(Pointer<Void>, Pointer<_ChEvent>);
typedef _PollEventDart = int Function(Pointer<Void>, Pointer<_ChEvent>);

typedef _LevelsNative = Int32 Function(Pointer<Void>, Pointer<Float>, Int32);
typedef _LevelsDart = int Function(Pointer<Void>, Pointer<Float>, int);
typedef _SetFloatNative = Int32 Function(Pointer<Void>, Float);
typedef _SetFloatDart = int Function(Pointer<Void>, double);
typedef _GetFloatNative = Float Function(Pointer<Void>);
typedef _GetFloatDart = double Function(Pointer<Void>);
typedef _SetIntNative = Int32 Function(Pointer<Void>, Int32);
typedef _SetIntDart = int Function(Pointer<Void>, int);
typedef _SetTwoFloatsNative = Int32 Function(Pointer<Void>, Float, Float);
typedef _SetTwoFloatsDart = int Function(Pointer<Void>, double, double);
typedef _SetIntAndFloatNative = Int32 Function(Pointer<Void>, Int32, Float);
typedef _SetIntAndFloatDart = int Function(Pointer<Void>, int, double);
typedef _SetIntTwoFloatsNative = Int32 Function(Pointer<Void>, Int32, Float, Float);
typedef _SetIntTwoFloatsDart = int Function(Pointer<Void>, int, double, double);
typedef _OutFloatNative = Int32 Function(Pointer<Void>, Pointer<Float>);
typedef _OutFloatDart = int Function(Pointer<Void>, Pointer<Float>);

// Fase 3: medición, mezcla fina, marcadores, CUE, exportación y paisajes.
typedef _SpectrumNative = Int32 Function(Pointer<Void>, Pointer<Float>, Int32);
typedef _SpectrumDart = int Function(Pointer<Void>, Pointer<Float>, int);
typedef _TwoDoublesNative = Int32 Function(Pointer<Void>, Double, Double);
typedef _TwoDoublesDart = int Function(Pointer<Void>, double, double);
typedef _FloatOutNative = Int32 Function(Pointer<Void>, Pointer<Float>);
typedef _FloatOutDart = int Function(Pointer<Void>, Pointer<Float>);
typedef _SilenceNative = Int32 Function(
    Pointer<Utf8>, Float, Pointer<Double>, Pointer<Double>);
typedef _SilenceDart = int Function(
    Pointer<Utf8>, double, Pointer<Double>, Pointer<Double>);
typedef _DeviceNameNative = Pointer<Utf8> Function(Int32);
typedef _DeviceNameDart = Pointer<Utf8> Function(int);
typedef _LyricLineNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _LyricLineDart = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _BpmNative = Double Function(Pointer<Utf8>);
typedef _BpmDart = double Function(Pointer<Utf8>);
typedef _RenderNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Double, Double);
typedef _RenderDart = int Function(Pointer<Utf8>, Pointer<Utf8>, double, double);
typedef _RenderDspNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Double, Double);
typedef _RenderDspDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, double, double);
typedef _MarkersAddNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Double, Pointer<Utf8>);
typedef _MarkersAddDart = int Function(
    Pointer<Void>, Pointer<Utf8>, double, Pointer<Utf8>);
typedef _MarkersIndexNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _MarkersIndexDart = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _MarkersDoubleNative = Double Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _MarkersDoubleDart = double Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _MarkersNameNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Int32);
typedef _MarkersNameDart = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, int);
typedef _MarkersTrackNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _MarkersTrackDart = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _HandlePathNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _HandlePathDart = Pointer<Void> Function(Pointer<Utf8>);
typedef _HandleIntNative = Int32 Function(Pointer<Void>);
typedef _HandleIntDart = int Function(Pointer<Void>);
typedef _HandleTextNative = Pointer<Utf8> Function(Pointer<Void>, Int32);
typedef _HandleTextDart = Pointer<Utf8> Function(Pointer<Void>, int);
typedef _HandleDoubleNative = Double Function(Pointer<Void>, Int32);
typedef _HandleDoubleDart = double Function(Pointer<Void>, int);
typedef _HandleVoidNative = Void Function(Pointer<Void>);
typedef _HandleVoidDart = void Function(Pointer<Void>);

typedef _SetLoopNative = Int32 Function(Pointer<Void>, Double, Double);
typedef _SetLoopDart = int Function(Pointer<Void>, double, double);

// Cola: mover/quitar/insertar llevan índices; añadir y cargar llevan ruta.
typedef _HandleIndexTextNative = Pointer<Utf8> Function(Pointer<Void>, Int32);
typedef _HandleIndexTextDart = Pointer<Utf8> Function(Pointer<Void>, int);
typedef _HandleIndexDoubleNative = Double Function(Pointer<Void>, Int32);
typedef _HandleIndexDoubleDart = double Function(Pointer<Void>, int);
typedef _HandleIndexIntNative = Int32 Function(Pointer<Void>, Int32);
typedef _HandleIndexIntDart = int Function(Pointer<Void>, int);
typedef _TwoIntsNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _TwoIntsDart = int Function(Pointer<Void>, int, int);
typedef _IntAndPathNative = Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>);
typedef _IntAndPathDart = int Function(Pointer<Void>, int, Pointer<Utf8>);
typedef _PathArgNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _PathArgDart = int Function(Pointer<Void>, Pointer<Utf8>);

// Biblioteca: handle opaco `void*`.
typedef _LibCreateNative = Pointer<Void> Function();
typedef _LibCreateDart = Pointer<Void> Function();
typedef _LibDestroyNative = Void Function(Pointer<Void>);
typedef _LibDestroyDart = void Function(Pointer<Void>);
typedef _LibScanNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _LibScanDart = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _LibCountNative = Int32 Function(Pointer<Void>);
typedef _LibCountDart = int Function(Pointer<Void>);
typedef _LibPathNative = Pointer<Utf8> Function(Pointer<Void>, Int32);
typedef _LibPathDart = Pointer<Utf8> Function(Pointer<Void>, int);
typedef _U64Native = Uint64 Function(Pointer<Void>);
typedef _U64Dart = int Function(Pointer<Void>);
typedef _NoArgIntNative = Int32 Function();
typedef _NoArgIntDart = int Function();

/// Nombre del binario del núcleo según la plataforma.
///
/// Linux y Android siguen cargando `libcyberhex_core.so` (el mismo nombre de
/// siempre: `jniLibs` y el bundle de CMake no cambian); Windows y macOS usan el
/// que produce `zig build` allí, que es lo que copian
/// `packaging/windows/build_windows.ps1` y `packaging/macos/build_macos.sh`
/// junto al ejecutable.
String get _libraryName {
  if (Platform.isWindows) return 'cyberhex_core.dll';
  if (Platform.isMacOS) return 'libcyberhex_core.dylib';
  return 'libcyberhex_core.so';
}

/// Carga una pista en un isolate aparte: `ch_engine_load` abre el archivo,
/// copia carátulas y parsea la letra, así que no debe bloquear el hilo de UI.
/// Solo se transfieren la dirección del motor (int) y la ruta (String).
bool _loadTrackInIsolate(int address, String path) {
  final lib = DynamicLibrary.open(_libraryName);
  final load = lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_load');
  final engine = Pointer<Void>.fromAddress(address);
  final utf8 = path.toNativeUtf8();
  try {
    return load(engine, utf8) == 0;
  } finally {
    malloc.free(utf8);
  }
}

/// Escaneo de biblioteca fuera del hilo de UI: en una carpeta grande, recorrer
/// el árbol y ordenar miles de rutas congela la app si se hace aquí.
///
/// La biblioteca se crea y se destruye dentro del isolate; solo cruzan rutas.
({List<String> paths, int removed}) _scanLibraryInIsolate(String root) {
  final lib = DynamicLibrary.open(_libraryName);
  final create = lib.lookupFunction<_LibCreateNative, _LibCreateDart>('ch_library_create');
  final destroy = lib.lookupFunction<_LibDestroyNative, _LibDestroyDart>('ch_library_destroy');
  final scan = lib.lookupFunction<_LibScanNative, _LibScanDart>('ch_library_scan');
  final count = lib.lookupFunction<_LibCountNative, _LibCountDart>('ch_library_count');
  final path = lib.lookupFunction<_LibPathNative, _LibPathDart>('ch_library_path');
  final removedFn =
      lib.lookupFunction<_LibCountNative, _LibCountDart>('ch_library_removed');

  final handle = create();
  if (handle == nullptr) return (paths: const <String>[], removed: 0);
  final utf8 = root.toNativeUtf8();
  try {
    if (scan(handle, utf8) < 0) return (paths: const <String>[], removed: 0);
    final removed = removedFn(handle);
    final total = count(handle);
    if (total <= 0) return (paths: const <String>[], removed: removed);
    final out = <String>[];
    for (var i = 0; i < total; i++) {
      final entry = path(handle, i);
      if (entry == nullptr) continue;
      out.add(entry.toDartString());
    }
    return (paths: out, removed: removed);
  } finally {
    malloc.free(utf8);
    destroy(handle);
  }
}

/// `ch_engine_load_add` fuera del hilo de UI. Devuelve el código del motor
/// (0 = bien); el índice real se lee después con `queue_index`, porque
/// `load_add` delega en `play_index`, que devuelve 0 y no el índice.
int _loadAddInIsolate(int address, String path) {
  final lib = DynamicLibrary.open(_libraryName);
  final loadAdd = lib.lookupFunction<_PathArgNative, _PathArgDart>('ch_engine_load_add');
  final engine = Pointer<Void>.fromAddress(address);
  final utf8 = path.toNativeUtf8();
  try {
    return loadAdd(engine, utf8);
  } finally {
    malloc.free(utf8);
  }
}


/// BPM fuera del hilo de UI: decodifica hasta 30 s del archivo.
double _bpmInIsolate(String path) {
  final lib = DynamicLibrary.open(_libraryName);
  if (!lib.providesSymbol('ch_engine_detect_bpm')) return 0;
  final fn = lib.lookupFunction<_BpmNative, _BpmDart>('ch_engine_detect_bpm');
  final utf8 = path.toNativeUtf8();
  try {
    return fn(utf8);
  } finally {
    malloc.free(utf8);
  }
}

/// Silencio inicial/final. Devuelve `(lead: -1, tail: -1)` si no se pudo.
({double lead, double tail}) _silenceInIsolate(String path, double threshold) {
  final lib = DynamicLibrary.open(_libraryName);
  if (!lib.providesSymbol('ch_engine_detect_silence')) {
    return (lead: -1.0, tail: -1.0);
  }
  final fn = lib.lookupFunction<_SilenceNative, _SilenceDart>('ch_engine_detect_silence');
  final utf8 = path.toNativeUtf8();
  final lead = calloc<Double>();
  final tail = calloc<Double>();
  try {
    if (fn(utf8, threshold, lead, tail) != 0) return (lead: -1.0, tail: -1.0);
    return (lead: lead.value, tail: tail.value);
  } finally {
    malloc.free(utf8);
    calloc.free(lead);
    calloc.free(tail);
  }
}

/// Exportación a WAV. `address` = 0 exporta plano; si no, con el DSP del motor.
int _renderWavInIsolate(
  int address,
  String source,
  String destination,
  double start,
  double end,
) {
  final lib = DynamicLibrary.open(_libraryName);
  final src = source.toNativeUtf8();
  final dst = destination.toNativeUtf8();
  try {
    if (address == 0) {
      if (!lib.providesSymbol('ch_engine_render_wav')) return -1;
      final fn = lib.lookupFunction<_RenderNative, _RenderDart>('ch_engine_render_wav');
      return fn(src, dst, start, end);
    }
    if (!lib.providesSymbol('ch_engine_render_wav_ex')) return -1;
    final fn = lib.lookupFunction<_RenderDspNative, _RenderDspDart>(
        'ch_engine_render_wav_ex');
    return fn(Pointer<Void>.fromAddress(address), src, dst, start, end);
  } finally {
    malloc.free(src);
    malloc.free(dst);
  }
}

/// Lee una hoja `.cue` y devuelve los cortes como mapas (cruzan isolates).
///
/// `isText` decide si se llama a `ch_cue_parse` (texto ya cargado) o a
/// `ch_cue_read` (ruta de archivo). El handle se libera siempre.
List<Map<String, Object?>> _cueInIsolate(String source, bool isText) {
  final lib = DynamicLibrary.open(_libraryName);
  final symbol = isText ? 'ch_cue_parse' : 'ch_cue_read';
  if (!lib.providesSymbol(symbol)) return const <Map<String, Object?>>[];
  final open = lib.lookupFunction<_HandlePathNative, _HandlePathDart>(symbol);
  final freeFn = lib.providesSymbol('ch_cue_free')
      ? lib.lookupFunction<_HandleVoidNative, _HandleVoidDart>('ch_cue_free')
      : null;
  final utf8 = source.toNativeUtf8();
  try {
    final handle = open(utf8);
    if (handle == nullptr) return const <Map<String, Object?>>[];
    try {
      final countFn = lib.lookupFunction<_HandleIntNative, _HandleIntDart>('ch_cue_count');
      final fileFn =
          lib.lookupFunction<_HandleIndexTextNative, _HandleIndexTextDart>('ch_cue_file');
      final titleFn =
          lib.lookupFunction<_HandleIndexTextNative, _HandleIndexTextDart>('ch_cue_title');
      final performerFn =
          lib.lookupFunction<_HandleIndexTextNative, _HandleIndexTextDart>('ch_cue_performer');
      final startFn =
          lib.lookupFunction<_HandleIndexDoubleNative, _HandleIndexDoubleDart>('ch_cue_start');
      final endFn =
          lib.lookupFunction<_HandleIndexDoubleNative, _HandleIndexDoubleDart>('ch_cue_end');
      final numberFn =
          lib.lookupFunction<_HandleIndexIntNative, _HandleIndexIntDart>('ch_cue_number');
      final total = countFn(handle);
      final out = <Map<String, Object?>>[];
      for (var i = 0; i < total; i++) {
        out.add(<String, Object?>{
          'file': fileFn(handle, i).toDartString(),
          'title': titleFn(handle, i).toDartString(),
          'performer': performerFn(handle, i).toDartString(),
          'start': startFn(handle, i),
          'end': endFn(handle, i),
          'number': numberFn(handle, i),
        });
      }
      return out;
    } finally {
      freeFn?.call(handle);
    }
  } finally {
    malloc.free(utf8);
  }
}

class CyberHexException implements Exception {
  CyberHexException(this.message);
  final String message;

  @override
  String toString() => message;
}

class NativePlayer implements PlayerApi {
  NativePlayer._(this._engine, this._bindings) {
    _eventBuf = calloc<_ChEvent>();
    _levelBuf = calloc<Float>(4);
    _outBuf = calloc<Float>(1);
  }

  static NativePlayer? open() {
    try {
      final bindings = _Bindings.instance;
      final engine = bindings.create();
      if (engine == nullptr) {
        _openFailure = bindings.coreLastError();
        return null;
      }
      return NativePlayer._(engine, bindings);
    } catch (error) {
      _openFailure = error.toString();
      return null;
    }
  }

  static String? _openFailure;

  static String lastCoreError() => _openFailure ?? 'no se pudo cargar el motor nativo';

  final Pointer<Void> _engine;
  final _Bindings _bindings;
  late final Pointer<_ChEvent> _eventBuf;
  late final Pointer<Float> _levelBuf;

  /// Salida de un solo float para los getters que escriben por puntero
  /// (crossfeed y modo noche). Se reserva una vez: el snapshot los lee a 12 Hz.
  late final Pointer<Float> _outBuf;

  @override
  final List<double> eqGains = List<double>.filled(_Bindings.instance.eqBandCount(), 0);

  String? _title;
  String? _artist;
  String? _album;
  String? _path;
  Uint8List? _cover;
  String? _failure;
  bool _loaded = false;
  double _duration = 0;
  bool _disposed = false;

  /// Título para mostrar: la etiqueta del archivo si existe, o su nombre.
  @override
  String get title => _title ?? '';

  @override
  String get artist => _artist ?? '';

  @override
  String get album => _album ?? '';

  String? get path => _path;

  @override
  Uint8List? get cover => _cover;

  @override
  bool get hasTrack => _loaded;

  @override
  double get duration => _duration;

  @override
  double get position => _bindings.position(_engine);

  @override
  bool get isPlaying => _bindings.isPlaying(_engine) != 0;

  @override
  String get lastError {
    final failure = _failure;
    if (failure != null) {
      _failure = null;
      return failure;
    }
    return _bindings.engineLastError(_engine);
  }

  /// Frecuencias centrales de las bandas del EQ, en Hz.
  ///
  /// Usa `ch_engine_eq_band_freq`; si la librería cargada es anterior a esa
  /// función, aproxima el reparto logarítmico 20 Hz–20 kHz del núcleo.
  @override
  late final List<double> eqBandFrequencies = List<double>.unmodifiable([
    for (var i = 0; i < eqGains.length; i++)
      _freqOrFallback(_bindings.eqBandFreq?.call(i) ?? 0, i, eqGains.length),
  ]);

  static double _freqOrFallback(double hz, int index, int count) {
    if (hz > 0) return hz;
    if (count <= 1) return 20;
    return 20.0 * math.pow(1000.0, index / (count - 1)).toDouble();
  }

  @override
  bool load(String path) {
    if (_disposed) return false;
    final utf8 = path.toNativeUtf8();
    try {
      if (_bindings.load(_engine, utf8) != 0) {
        return false;
      }
      // ch_engine_load deja la cola con una sola pista: esta.
      _queuePaths
        ..clear()
        ..add(path);
      _applyMetadata(path);
      return true;
    } finally {
      malloc.free(utf8);
    }
  }

  /// Igual que [load] pero fuera del hilo de UI.
  @override
  Future<bool> loadAsync(String path) async {
    if (_disposed) return false;
    try {
      final address = _engine.address;
      final ok = await Isolate.run(() => _loadTrackInIsolate(address, path));
      if (!ok || _disposed) return false;
      _queuePaths
        ..clear()
        ..add(path);
      _applyMetadata(path);
      return true;
    } catch (error) {
      _failure = error.toString();
      return false;
    }
  }

  void _applyMetadata(String path) {
    _path = path;
    _loaded = true;
    syncTrackInfo();
  }

  @override
  void syncTrackInfo() {
    final tag = _bindings.title(_engine).trim();
    final fallback = _path == null ? '' : _fileName(_path!);
    _title = tag.isEmpty ? fallback : tag;
    _artist = _bindings.artist(_engine).trim();
    _album = _bindings.album(_engine).trim();
    _duration = _bindings.duration(_engine);
    _cover = _readCover();
  }

  Uint8List? _readCover() {
    final count = _bindings.coverCount(_engine);
    if (count <= 0) return null;
    final size = calloc<Uint64>();
    try {
      for (var i = 0; i < count; i++) {
        final data = _bindings.coverAt(_engine, i, size);
        final length = size.value;
        if (data == nullptr || length <= 0 || length > 32 * 1024 * 1024) {
          continue;
        }
        return Uint8List.fromList(data.asTypedList(length));
      }
    } finally {
      calloc.free(size);
    }
    return null;
  }

  @override
  void play() => _bindings.play(_engine);

  @override
  void pause() => _bindings.pause(_engine);

  @override
  void toggle() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  @override
  void next() {
    if (_disposed) return;
    // El motor avisa del cambio de pista con CH_EVENT_TRACK; el controlador
    // relee etiquetas entonces. Aquí no se toca el estado.
    _bindings.next?.call(_engine);
  }

  @override
  void previous() {
    if (_disposed) return;
    _bindings.previous?.call(_engine);
  }

  /// Modo de repetición del motor (0 apagado, 1 todo, 2 una).
  @override
  int get repeatMode {
    if (_disposed) return 0;
    final value = _bindings.repeat?.call(_engine) ?? 0;
    return math.max(0, math.min(2, value));
  }

  @override
  bool get shuffle => !_disposed && (_bindings.shuffle?.call(_engine) ?? 0) != 0;

  @override
  void setRepeatMode(int mode) {
    if (_disposed) return;
    _bindings.setRepeat?.call(_engine, math.max(0, math.min(2, mode)));
  }

  @override
  void setShuffle(bool enabled) {
    if (_disposed) return;
    _bindings.setShuffle?.call(_engine, enabled ? 1 : 0);
  }

  /// 0 → 1 → 2 → 0. Se lee del motor para no desincronizarse si otra vía
  /// (el servicio de medios, un preset guardado) lo cambió por su cuenta.
  @override
  void cycleRepeat() => setRepeatMode((repeatMode + 1) % 3);

  @override
  void toggleShuffle() => setShuffle(!shuffle);

  // ---------------------------------------------------------------------
  // Fase 2: núcleo DSP audiófilo
  // ---------------------------------------------------------------------

  /// Lee un float por puntero: 0 si la `.so` es anterior a estos símbolos.
  double _valueOut(_OutFloatDart? fn) {
    if (_disposed || fn == null) return 0;
    fn(_engine, _outBuf);
    return _outBuf.value;
  }

  @override
  bool get nineDEnabled =>
      !_disposed && (_bindings.nineDEnabled?.call(_engine) ?? 0) != 0;

  @override
  double get nineDSpeed => _bindings.nineDSpeed?.call(_engine) ?? 0;

  @override
  double get nineDDepth => _bindings.nineDDepth?.call(_engine) ?? 0;

  @override
  void set9D(bool enabled, double speedHz, double depth) {
    if (_disposed) return;
    _bindings.set9D?.call(
      _engine,
      enabled ? 1 : 0,
      speedHz.clamp(0.05, 2.0).toDouble(),
      depth.clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  double get stereoWidth => _bindings.stereoWidthFn?.call(_engine) ?? 1;

  @override
  double get bassPunch => _bindings.bassPunchFn?.call(_engine) ?? 0;

  @override
  void setStereoEnhance(double width, double bassPunch) {
    if (_disposed) return;
    _bindings.setStereoEnhance?.call(
      _engine,
      width.clamp(0.0, 2.0).toDouble(),
      bassPunch.clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  void setStereoWidth(double width) {
    if (_disposed) return;
    _bindings.setStereoWidthFn?.call(_engine, width.clamp(0.0, 2.0).toDouble());
  }

  @override
  double get vocalCut => _bindings.vocalCutFn?.call(_engine) ?? 0;

  @override
  void setVocalCut(double amount) {
    if (_disposed) return;
    _bindings.setVocalCut?.call(_engine, amount.clamp(0.0, 1.0).toDouble());
  }

  @override
  bool get crossfeedEnabled => !_disposed && _crossfeed() != 0;

  @override
  double get crossfeedLevel {
    if (_disposed || _bindings.crossfeedFn == null) return 0;
    _bindings.crossfeedFn!(_engine, _outBuf);
    return _outBuf.value;
  }

  int _crossfeed() => _bindings.crossfeedFn?.call(_engine, nullptr) ?? 0;

  @override
  void setCrossfeed(bool enabled, double level) {
    if (_disposed) return;
    _bindings.setCrossfeedFn?.call(
      _engine,
      enabled ? 1 : 0,
      level.clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  bool get nightModeEnabled => !_disposed && _nightMode() != 0;

  @override
  double get nightModeAmount => _valueOut(_bindings.nightModeFn);

  int _nightMode() => _bindings.nightModeFn?.call(_engine, nullptr) ?? 0;

  @override
  void setNightMode(bool enabled, double amount) {
    if (_disposed) return;
    _bindings.setNightMode?.call(
      _engine,
      enabled ? 1 : 0,
      amount.clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  bool get s16Output => !_disposed && (_bindings.s16Fn?.call(_engine) ?? 0) != 0;

  @override
  void setS16Output(bool enabled) {
    if (_disposed) return;
    _bindings.setS16?.call(_engine, enabled ? 1 : 0);
  }

  // ---------------------------------------------------------------------
  // Cola
  // ---------------------------------------------------------------------

  /// Espejo de las rutas de la cola.
  ///
  /// El núcleo no expone `queue_path`: solo `queue_count`/`queue_index`. Todas
  /// las mutaciones de la cola pasan por esta clase, así que el espejo es fiel;
  /// si el motor tuviera más pistas de las conocidas (cola importada por fuera
  /// o restaurada por el propio núcleo) se rellenan con rutas vacías en vez de
  /// inventarlas.
  final List<String> _queuePaths = <String>[];

  int _libraryRemoved = 0;

  @override
  int get queueLength {
    if (_disposed) return 0;
    final count = _bindings.queueCount?.call(_engine) ?? _queuePaths.length;
    return count < 0 ? 0 : count;
  }

  @override
  int get queueIndex {
    if (_disposed) return -1;
    return _bindings.queueIndex?.call(_engine) ?? -1;
  }

  void _syncMirror() {
    final count = queueLength;
    if (_queuePaths.length > count) {
      _queuePaths.removeRange(count, _queuePaths.length);
      return;
    }
    while (_queuePaths.length < count) {
      _queuePaths.add('');
    }
  }

  @override
  List<QueueItem> get queueItems {
    _syncMirror();
    final index = queueIndex;
    return List<QueueItem>.unmodifiable(<QueueItem>[
      for (var i = 0; i < _queuePaths.length; i++)
        QueueItem(
          path: _queuePaths[i],
          title: _queuePaths[i].isEmpty
              ? 'Pista ${i + 1}'
              : titleFromPath(_queuePaths[i]),
          artist: i == index ? artist : '',
        ),
    ]);
  }

  @override
  bool playAt(int index) {
    if (_disposed) return false;
    final fn = _bindings.playIndex;
    if (fn == null) return false;
    if (fn(_engine, index) != 0) return false;
    _loaded = true;
    syncTrackInfo();
    return true;
  }

  @override
  bool enqueue(String path) {
    if (_disposed) return false;
    final fn = _bindings.queueAdd;
    if (fn == null) return false;
    final utf8 = path.toNativeUtf8();
    try {
      // queue_add devuelve el índice donde la puso.
      final index = fn(_engine, utf8);
      if (index < 0) return false;
      _syncMirror();
      if (index < _queuePaths.length) {
        _queuePaths[index] = path;
      } else {
        _queuePaths.add(path);
      }
      return true;
    } finally {
      malloc.free(utf8);
    }
  }

  @override
  bool playNext(String path) {
    if (_disposed) return false;
    final fn = _bindings.queueInsert;
    if (fn == null) return false;
    final current = queueIndex;
    final length = queueLength;
    final at = current < 0 ? length : math.min(current + 1, length);
    final utf8 = path.toNativeUtf8();
    try {
      if (fn(_engine, at, utf8) != 0) return false;
      while (_queuePaths.length < length) {
        _queuePaths.add('');
      }
      _queuePaths.insert(at, path);
      return true;
    } finally {
      malloc.free(utf8);
    }
  }

  @override
  Future<bool> loadAndPlayAsync(String path) async {
    if (_disposed) return false;
    if (_bindings.loadAdd == null) return loadAsync(path);
    try {
      final address = _engine.address;
      final result = await Isolate.run(() => _loadAddInIsolate(address, path));
      if (result != 0 || _disposed) return false;
      // load_add delega en play_index: el índice audible es el de la pista.
      final at = queueIndex;
      _syncMirror();
      if (at >= 0 && at < _queuePaths.length) {
        _queuePaths[at] = path;
      }
      _applyMetadata(path);
      return true;
    } catch (error) {
      _failure = error.toString();
      return false;
    }
  }

  @override
  bool moveQueueItem(int from, int to) {
    if (_disposed) return false;
    final fn = _bindings.queueMove;
    if (fn == null) return false;
    if (fn(_engine, from, to) != 0) return false;
    _syncMirror();
    if (from < 0 || to < 0 || from >= _queuePaths.length || to >= _queuePaths.length) {
      return true;
    }
    final item = _queuePaths.removeAt(from);
    _queuePaths.insert(to, item);
    return true;
  }

  @override
  bool removeQueueItem(int index) {
    if (_disposed) return false;
    final fn = _bindings.queueRemove;
    if (fn == null) return false;
    if (fn(_engine, index) != 0) return false;
    if (index >= 0 && index < _queuePaths.length) {
      _queuePaths.removeAt(index);
    }
    _syncMirror();
    return true;
  }

  @override
  void clearQueue() {
    if (_disposed) return;
    _bindings.queueClear?.call(_engine);
    _queuePaths.clear();
    _loaded = false;
    _duration = 0;
  }

  @override
  int importQueue(String playlistPath) {
    if (_disposed) return 0;
    final fn = _bindings.queueImport;
    if (fn == null) return 0;
    final utf8 = playlistPath.toNativeUtf8();
    try {
      final added = fn(_engine, utf8);
      if (added <= 0) return 0;
      // El motor añade al final en el mismo orden del archivo: se replica para
      // no quedarnos con rutas vacías en el espejo.
      _queuePaths.addAll(_readPlaylistPaths(playlistPath));
      _syncMirror();
      return added;
    } finally {
      malloc.free(utf8);
    }
  }

  @override
  bool exportQueue(String playlistPath) {
    if (_disposed) return false;
    final fn = _bindings.queueExport;
    if (fn == null) return false;
    final utf8 = playlistPath.toNativeUtf8();
    try {
      return fn(_engine, utf8) == 0;
    } finally {
      malloc.free(utf8);
    }
  }

  /// Lee un M3U/M3U8/PLS como texto y devuelve rutas absolutas.
  static List<String> _readPlaylistPaths(String playlistPath) {
    try {
      final file = File(playlistPath);
      if (!file.existsSync()) return const <String>[];
      final base = file.parent.path;
      final paths = <String>[];
      for (final raw in file.readAsLinesSync()) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        var value = line;
        final equals = line.indexOf('=');
        if (equals > 0 && line.substring(0, equals).toLowerCase().startsWith('file')) {
          value = line.substring(equals + 1).trim();
        }
        if (value.isEmpty) continue;
        paths.add(value.startsWith('/') ? value : '$base/$value');
      }
      return paths;
    } catch (_) {
      return const <String>[];
    }
  }

  // ---------------------------------------------------------------------
  // Biblioteca
  // ---------------------------------------------------------------------

  @override
  int get libraryRemoved => _libraryRemoved;

  @override
  Future<List<LibraryTrack>> scanDirectory(String root) async {
    if (_disposed) return const <LibraryTrack>[];
    if (_bindings.libraryCreate == null || _bindings.libraryScan == null) {
      return const <LibraryTrack>[];
    }
    try {
      final scan = await Isolate.run(() => _scanLibraryInIsolate(root));
      if (_disposed) return const <LibraryTrack>[];
      _libraryRemoved = scan.removed;
      return List<LibraryTrack>.unmodifiable(
        scan.paths.map(LibraryTrack.fromPath),
      );
    } catch (error) {
      _failure = error.toString();
      return const <LibraryTrack>[];
    }
  }

  @override
  void seek(double seconds) => _bindings.seek(_engine, seconds);

  @override
  void setVolume(double value) =>
      _bindings.setVolume(_engine, value.clamp(0, 1).toDouble());

  @override
  void setBand(int index, double db) {
    eqGains[index] = db;
    final buffer = calloc<Float>(eqGains.length);
    try {
      for (var i = 0; i < eqGains.length; i++) {
        buffer[i] = eqGains[i];
      }
      _bindings.setEqGains(_engine, buffer, eqGains.length);
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  void resetEq() {
    for (var i = 0; i < eqGains.length; i++) {
      eqGains[i] = 0;
    }
    setBand(0, 0);
  }

  /// Fundido de pausa en segundos (0 = corte inmediato).
  void setPauseFade(double seconds) =>
      _bindings.setPauseFade?.call(_engine, seconds);

  double get pauseFade => _bindings.pauseFade?.call(_engine) ?? 0.05;

  /// Preamp del EQ en dB (0 a -24).
  void setEqPreamp(double db) => _bindings.setEqPreamp?.call(_engine, db);

  double get eqPreamp => _bindings.eqPreamp?.call(_engine) ?? 0;

  /// Pistas que el motor se saltó por no poder abrirlas.
  int get skippedTracks => _bindings.skippedTracks?.call(_engine) ?? 0;

  /// ABI del núcleo cargado (0 si la librería es tan antigua que no lo expone).
  static int get coreAbiVersion => _Bindings.instance.abiVersion?.call() ?? 0;

  @override
  PlayerEvent? pollEvent() {
    if (_disposed) return null;
    if (_bindings.pollEvent(_engine, _eventBuf) <= 0) return null;
    final raw = _eventBuf.ref;
    return PlayerEvent(
      _eventKind(raw.kind),
      a: raw.a,
      b: raw.b,
      value: raw.value,
    );
  }

  static PlayerEventKind _eventKind(int kind) {
    switch (kind) {
      case 1:
        return PlayerEventKind.state;
      case 2:
        return PlayerEventKind.track;
      case 3:
        return PlayerEventKind.queue;
      case 4:
        return PlayerEventKind.end;
      case 5:
        return PlayerEventKind.sleep;
      default:
        return PlayerEventKind.unknown;
    }
  }


  // ---------------------------------------------------------------------
  // Fase 3: medición, mezcla fina y transporte extendido
  // ---------------------------------------------------------------------

  @override
  PlayerLevels levels() {
    if (_disposed) return PlayerLevels.silent;
    final fn = _bindings.levels;
    if (fn == null) return PlayerLevels.silent;
    if (fn(_engine, _levelBuf, 4) < 4) return PlayerLevels.silent;
    return PlayerLevels(
      rmsLeft: _levelBuf[0],
      rmsRight: _levelBuf[1],
      peakLeft: _levelBuf[2],
      peakRight: _levelBuf[3],
    );
  }

  @override
  List<double> spectrum([int bands = 32]) {
    if (_disposed) return const <double>[];
    final fn = _bindings.spectrum;
    if (fn == null || bands <= 0) return const <double>[];
    final buffer = calloc<Float>(bands);
    try {
      final count = fn(_engine, buffer, bands);
      if (count <= 0) return const <double>[];
      return List<double>.generate(count, (i) => buffer[i]);
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  double get balance => _bindings.balance?.call(_engine) ?? 0;

  @override
  void setBalance(double value) {
    if (_disposed) return;
    _bindings.setBalance?.call(_engine, value.clamp(-1.0, 1.0).toDouble());
  }

  @override
  int get channelMode {
    final value = _bindings.channelMode?.call(_engine) ?? 0;
    return value < 0 || value > 2 ? 0 : value;
  }

  @override
  void setChannelMode(int mode) {
    if (_disposed) return;
    _bindings.setChannelMode?.call(_engine, mode.clamp(0, 2));
  }

  /// El núcleo solo expone el *setter* de ReplayGain (`ch_engine_set_replaygain`),
  /// no un getter, así que aquí se recuerda el último valor enviado. Arranca
  /// activado porque es el valor por defecto del motor; al restaurar la sesión,
  /// `applyAudioSettings` vuelve a mandarlo.
  bool _replayGainEnabled = true;

  @override
  bool get replayGainEnabled => !_disposed && _replayGainEnabled;

  @override
  void setReplayGain(bool enabled) {
    if (_disposed) return;
    _replayGainEnabled = enabled;
    _bindings.setReplayGain?.call(_engine, enabled ? 1 : 0);
  }

  @override
  double get replayGainGainDb => _bindings.rgGainDb?.call(_engine) ?? 0;

  @override
  double get replayGainPeak => _bindings.rgPeak?.call(_engine) ?? 0;

  @override
  bool get replayGainAlbum =>
      (_bindings.replayGainMode?.call(_engine) ?? 0) == 1;

  @override
  void setReplayGainAlbum(bool album) {
    if (_disposed) return;
    _bindings.setReplayGainMode?.call(_engine, album ? 1 : 0);
  }

  @override
  double get speed => _bindings.speed?.call(_engine) ?? 1;

  @override
  void setSpeed(double value) {
    if (_disposed) return;
    _bindings.setSpeed?.call(_engine, value.clamp(0.25, 4.0).toDouble());
  }

  @override
  double get pitch => _bindings.pitch?.call(_engine) ?? 0;

  @override
  void setPitch(double semitones) {
    if (_disposed) return;
    _bindings.setPitch?.call(_engine, semitones.clamp(-12.0, 12.0).toDouble());
  }

  @override
  double get crossfade => _bindings.crossfade?.call(_engine) ?? 0;

  @override
  void setCrossfade(double seconds) {
    if (_disposed) return;
    _bindings.setCrossfade?.call(_engine, seconds.clamp(0.0, 12.0).toDouble());
  }

  @override
  bool get gapless => !_disposed && (_bindings.gapless?.call(_engine) ?? 1) != 0;

  @override
  void setGapless(bool enabled) {
    if (_disposed) return;
    _bindings.setGapless?.call(_engine, enabled ? 1 : 0);
  }

  @override
  void setLoop(double start, double end) {
    if (_disposed) return;
    _bindings.setLoop?.call(_engine, start, end);
  }

  @override
  void clearLoop() {
    if (_disposed) return;
    _bindings.setLoop?.call(_engine, 0, 0);
  }

  @override
  double get loopStart => _bindings.loopStart?.call(_engine) ?? -1;

  @override
  double get loopEnd => _bindings.loopEnd?.call(_engine) ?? -1;

  @override
  bool get loopActive {
    final a = loopStart;
    final b = loopEnd;
    return a >= 0 && b > a;
  }

  /// Handle de marcadores; se crea la primera vez y se destruye en [dispose].
  Pointer<Void>? _markers;

  Pointer<Void>? _markerHandle() {
    if (_disposed) return null;
    final existing = _markers;
    if (existing != null) return existing;
    final create = _bindings.markersCreate;
    if (create == null) return null;
    final handle = create();
    if (handle == nullptr) return null;
    _markers = handle;
    return handle;
  }

  @override
  bool loadMarkers(String path) {
    final handle = _markerHandle();
    if (handle == null) return false;
    final fn = _bindings.markersLoad;
    if (fn == null) return false;
    final utf8 = path.toNativeUtf8();
    try {
      return fn(handle, utf8) == 0;
    } finally {
      malloc.free(utf8);
    }
  }

  @override
  bool saveMarkers(String path) {
    final handle = _markerHandle();
    if (handle == null) return false;
    final fn = _bindings.markersSave;
    if (fn == null) return false;
    final utf8 = path.toNativeUtf8();
    try {
      return fn(handle, utf8) == 0;
    } finally {
      malloc.free(utf8);
    }
  }

  @override
  List<AudioMarker> markersOf(String trackPath) {
    final handle = _markerHandle();
    if (handle == null) return const <AudioMarker>[];
    final track = trackPath.toNativeUtf8();
    try {
      return _readMarkersAll(handle, track);
    } finally {
      malloc.free(track);
    }
  }

  List<AudioMarker> _readMarkersAll(Pointer<Void> handle, Pointer<Utf8> track) {
    final count = _bindings.markersCount?.call(handle, track) ?? 0;
    if (count <= 0) return const <AudioMarker>[];
    final out = <AudioMarker>[];
    for (var i = 0; i < count; i++) {
      final position = _bindings.markersPosition?.call(handle, track, i) ?? 0;
      final namePtr = _bindings.markersName?.call(handle, track, i);
      out.add(AudioMarker(
        position: position,
        name: namePtr == null ? '' : namePtr.toDartString(),
      ));
    }
    return List<AudioMarker>.unmodifiable(out);
  }

  @override
  bool addMarker(String trackPath, double position, String name) {
    if (!position.isFinite || position < 0) return false;
    final handle = _markerHandle();
    if (handle == null) return false;
    final fn = _bindings.markersAdd;
    if (fn == null) return false;
    final track = trackPath.toNativeUtf8();
    final label = name.toNativeUtf8();
    try {
      return fn(handle, track, position, label) == 0;
    } finally {
      malloc.free(track);
      malloc.free(label);
    }
  }

  @override
  bool removeMarker(String trackPath, int index) {
    final handle = _markerHandle();
    if (handle == null) return false;
    final fn = _bindings.markersRemove;
    if (fn == null) return false;
    final track = trackPath.toNativeUtf8();
    try {
      return fn(handle, track, index) == 0;
    } finally {
      malloc.free(track);
    }
  }

  @override
  void clearMarkers(String trackPath) {
    final handle = _markerHandle();
    if (handle == null) return;
    final track = trackPath.toNativeUtf8();
    try {
      _bindings.markersClear?.call(handle, track);
    } finally {
      malloc.free(track);
    }
  }

  @override
  void setSleepTimer(double seconds, {double fadeSeconds = 8}) {
    if (_disposed) return;
    _bindings.setSleepTimer?.call(_engine, seconds, fadeSeconds);
  }

  @override
  double get sleepRemaining => _bindings.sleepRemaining?.call(_engine) ?? -1;

  @override
  Future<SilenceTrim?> detectSilence(String path,
      {double thresholdDb = -60}) async {
    if (_disposed) return null;
    if (_bindings.detectSilence == null) return null;
    try {
      final result = await Isolate.run(() => _silenceInIsolate(path, thresholdDb));
      if (_disposed || result.lead < 0) return null;
      return SilenceTrim(lead: result.lead, tail: result.tail);
    } catch (error) {
      _failure = error.toString();
      return null;
    }
  }

  @override
  List<AudioDevice> get outputDevices {
    final count = _bindings.deviceCount?.call() ?? 0;
    if (count <= 0) return const <AudioDevice>[];
    final out = <AudioDevice>[const AudioDevice(index: -1, name: 'Predeterminado')];
    for (var i = 0; i < count; i++) {
      final name = _bindings.deviceName?.call(i)?.toDartString() ?? '';
      out.add(AudioDevice(index: i, name: name));
    }
    return List<AudioDevice>.unmodifiable(out);
  }

  @override
  int get outputDevice => _bindings.currentDevice?.call(_engine) ?? -1;

  @override
  bool setOutputDevice(int index) {
    if (_disposed) return false;
    final fn = _bindings.setOutputDevice;
    if (fn == null) return false;
    return fn(_engine, index) == 0;
  }

  @override
  int get lyricLineCount {
    final value = _bindings.lyricsCount?.call(_engine) ?? 0;
    return value < 0 ? 0 : value;
  }

  @override
  String get currentLyricLine {
    if (_disposed) return '';
    final fn = _bindings.lyricLine;
    if (fn == null) return '';
    final buffer = calloc<Uint8>(512);
    try {
      final written = fn(_engine, buffer.cast<Utf8>(), 512);
      if (written <= 0) return '';
      return utf8.decode(buffer.asTypedList(written), allowMalformed: true);
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  SoundscapePreset get soundscape {
    if (_disposed) return SoundscapePreset.off;
    final fn = _bindings.soundscapeGet;
    if (fn == null) return SoundscapePreset.off;
    return SoundscapePreset.fromCode(fn(_engine, _outBuf));
  }

  @override
  double get soundscapeLevel {
    if (_disposed) return 0;
    final fn = _bindings.soundscapeGet;
    if (fn == null) return 0;
    fn(_engine, _outBuf);
    return _outBuf.value;
  }

  @override
  void setSoundscape(SoundscapePreset preset, {double? level}) {
    if (_disposed) return;
    final fn = _bindings.soundscapeSet;
    if (fn == null) return;
    final desired = (level ?? soundscapeLevel).clamp(0.0, 1.0).toDouble();
    fn(_engine, preset.code, desired);
  }

  @override
  Future<double> detectBpm(String path) async {
    if (_disposed || _bindings.detectBpm == null) return 0;
    try {
      final value = await Isolate.run(() => _bpmInIsolate(path));
      if (_disposed || !value.isFinite) return 0;
      return value;
    } catch (error) {
      _failure = error.toString();
      return 0;
    }
  }

  @override
  Future<bool> renderWav(
    String sourcePath,
    String destinationPath, {
    double start = 0,
    double end = 0,
    bool withDsp = true,
  }) async {
    if (_disposed) return false;
    if (withDsp && _bindings.renderDsp == null) return false;
    if (!withDsp && _bindings.renderFlat == null) return false;
    try {
      final address = withDsp ? _engine.address : 0;
      final code = await Isolate.run(
        () => _renderWavInIsolate(address, sourcePath, destinationPath, start, end),
      );
      if (code != 0) {
        _failure = _renderError(code);
        return false;
      }
      return true;
    } catch (error) {
      _failure = error.toString();
      return false;
    }
  }

  static String _renderError(int code) {
    switch (code) {
      case -1:
        return 'exportación: argumentos inválidos';
      case -2:
        return 'exportación: no se pudo abrir el origen';
      case -3:
        return 'exportación: no se pudo crear el destino';
      case -4:
        return 'exportación: error de escritura';
      case -5:
        return 'exportación: demasiado largo para un WAV';
      case -6:
        return 'exportación: el origen se cortó antes de tiempo';
      default:
        return 'exportación: error $code';
    }
  }

  @override
  List<CueTrack> readCue(String path) {
    if (_disposed || _bindings.cueRead == null) return const <CueTrack>[];
    return _cueFrom(_cueInIsolate(path, false));
  }

  @override
  List<CueTrack> parseCue(String text) {
    if (_disposed || _bindings.cueParse == null) return const <CueTrack>[];
    return _cueFrom(_cueInIsolate(text, true));
  }

  static List<CueTrack> _cueFrom(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return const <CueTrack>[];
    return List<CueTrack>.unmodifiable(<CueTrack>[
      for (final row in rows)
        CueTrack(
          file: row['file'] as String? ?? '',
          title: row['title'] as String? ?? '',
          performer: row['performer'] as String? ?? '',
          start: (row['start'] as num?)?.toDouble() ?? 0,
          end: (row['end'] as num?)?.toDouble() ?? -1,
          number: (row['number'] as int?) ?? 0,
        ),
    ]);
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    calloc.free(_eventBuf);
    calloc.free(_levelBuf);
    calloc.free(_outBuf);
    final markers = _markers;
    if (markers != null) {
      _bindings.markersDestroy?.call(markers);
      _markers = null;
    }
    _bindings.destroy(_engine);
  }

  static String _fileName(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

class _Bindings {
  _Bindings._(DynamicLibrary lib)
      : create = lib.lookupFunction<_CreateNative, _CreateDart>('ch_engine_create'),
        destroy = lib.lookupFunction<_DestroyNative, _DestroyDart>('ch_engine_destroy'),
        load = lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_load'),
        play = lib.lookupFunction<_ControlNative, _ControlDart>('ch_engine_play'),
        pause = lib.lookupFunction<_ControlNative, _ControlDart>('ch_engine_pause'),
        seek = lib.lookupFunction<_SeekNative, _SeekDart>('ch_engine_seek'),
        next = lib.providesSymbol('ch_engine_next')
            ? lib.lookupFunction<_ControlNative, _ControlDart>('ch_engine_next')
            : null,
        previous = lib.providesSymbol('ch_engine_previous')
            ? lib.lookupFunction<_ControlNative, _ControlDart>('ch_engine_previous')
            : null,
        setVolume = lib.lookupFunction<_VolumeNative, _VolumeDart>('ch_engine_set_volume'),
        eqBandCount = lib.lookupFunction<_EqCountNative, _EqCountDart>('ch_engine_eq_band_count'),
        eqBandFreq = lib.providesSymbol('ch_engine_eq_band_freq')
            ? lib.lookupFunction<_EqFreqNative, _EqFreqDart>('ch_engine_eq_band_freq')
            : null,
        setEqGains = lib.lookupFunction<_EqGainsNative, _EqGainsDart>('ch_engine_set_eq_gains'),
        position = lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_position'),
        duration = lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_duration'),
        isPlaying = lib.lookupFunction<_IntNative, _IntDart>('ch_engine_is_playing'),
        pollEvent =
            lib.lookupFunction<_PollEventNative, _PollEventDart>('ch_engine_poll_event'),
        levels = lib.providesSymbol('ch_engine_levels')
            ? lib.lookupFunction<_LevelsNative, _LevelsDart>('ch_engine_levels')
            : null,
        setPauseFade = lib.providesSymbol('ch_engine_set_pause_fade')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_pause_fade')
            : null,
        pauseFade = lib.providesSymbol('ch_engine_pause_fade')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_pause_fade')
            : null,
        setEqPreamp = lib.providesSymbol('ch_engine_set_eq_preamp')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_eq_preamp')
            : null,
        eqPreamp = lib.providesSymbol('ch_engine_eq_preamp')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_eq_preamp')
            : null,
        setReplayGainMode = lib.providesSymbol('ch_engine_set_replaygain_mode')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_replaygain_mode')
            : null,
        replayGainMode = lib.providesSymbol('ch_engine_replaygain_mode')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_replaygain_mode')
            : null,
        setLoop = lib.providesSymbol('ch_engine_set_loop')
            ? lib.lookupFunction<_SetLoopNative, _SetLoopDart>('ch_engine_set_loop')
            : null,
        loopStart = lib.providesSymbol('ch_engine_loop_start')
            ? lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_loop_start')
            : null,
        loopEnd = lib.providesSymbol('ch_engine_loop_end')
            ? lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_loop_end')
            : null,
        skippedTracks = lib.providesSymbol('ch_engine_skipped_tracks')
            ? lib.lookupFunction<_U64Native, _U64Dart>('ch_engine_skipped_tracks')
            : null,
        abiVersion = lib.providesSymbol('ch_engine_abi_version')
            ? lib.lookupFunction<_NoArgIntNative, _NoArgIntDart>('ch_engine_abi_version')
            : null,
        setBalance = lib.providesSymbol('ch_engine_set_balance')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_balance')
            : null,
        balance = lib.providesSymbol('ch_engine_balance')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_balance')
            : null,
        setRepeat = lib.providesSymbol('ch_engine_set_repeat')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_repeat')
            : null,
        repeat = lib.providesSymbol('ch_engine_repeat')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_repeat')
            : null,
        setShuffle = lib.providesSymbol('ch_engine_set_shuffle')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_shuffle')
            : null,
        shuffle = lib.providesSymbol('ch_engine_shuffle')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_shuffle')
            : null,
        setChannelMode = lib.providesSymbol('ch_engine_set_channel_mode')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_channel_mode')
            : null,
        channelMode = lib.providesSymbol('ch_engine_channel_mode')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_channel_mode')
            : null,
        titleFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_title'),
        artistFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_artist'),
        albumFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_album'),
        coverCount = lib.lookupFunction<_IntNative, _IntDart>('ch_engine_cover_count'),
        coverAt =
            lib.lookupFunction<_CoverAtNative, _CoverAtDart>('ch_engine_cover_at'),
        engineLastErrorFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_last_error'),
        coreLastErrorFn = lib.lookupFunction<_PlainTextNative, _PlainTextDart>('ch_core_last_error'),
        playIndex = lib.providesSymbol('ch_engine_play_index')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_play_index')
            : null,
        loadAdd = lib.providesSymbol('ch_engine_load_add')
            ? lib.lookupFunction<_PathArgNative, _PathArgDart>('ch_engine_load_add')
            : null,
        queueAdd = lib.providesSymbol('ch_engine_queue_add')
            ? lib.lookupFunction<_PathArgNative, _PathArgDart>('ch_engine_queue_add')
            : null,
        queueCount = lib.providesSymbol('ch_engine_queue_count')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_queue_count')
            : null,
        queueIndex = lib.providesSymbol('ch_engine_queue_index')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_queue_index')
            : null,
        queueClear = lib.providesSymbol('ch_engine_queue_clear')
            ? lib.lookupFunction<_ControlNative, _ControlDart>('ch_engine_queue_clear')
            : null,
        queueMove = lib.providesSymbol('ch_engine_queue_move')
            ? lib.lookupFunction<_TwoIntsNative, _TwoIntsDart>('ch_engine_queue_move')
            : null,
        queueRemove = lib.providesSymbol('ch_engine_queue_remove')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_queue_remove')
            : null,
        queueInsert = lib.providesSymbol('ch_engine_queue_insert')
            ? lib.lookupFunction<_IntAndPathNative, _IntAndPathDart>('ch_engine_queue_insert')
            : null,
        queueImport = lib.providesSymbol('ch_engine_queue_import')
            ? lib.lookupFunction<_PathArgNative, _PathArgDart>('ch_engine_queue_import')
            : null,
        queueExport = lib.providesSymbol('ch_engine_queue_export')
            ? lib.lookupFunction<_PathArgNative, _PathArgDart>('ch_engine_queue_export')
            : null,
        libraryCreate = lib.providesSymbol('ch_library_create')
            ? lib.lookupFunction<_LibCreateNative, _LibCreateDart>('ch_library_create')
            : null,
        libraryDestroy = lib.providesSymbol('ch_library_destroy')
            ? lib.lookupFunction<_LibDestroyNative, _LibDestroyDart>('ch_library_destroy')
            : null,
        libraryScan = lib.providesSymbol('ch_library_scan')
            ? lib.lookupFunction<_LibScanNative, _LibScanDart>('ch_library_scan')
            : null,
        libraryCount = lib.providesSymbol('ch_library_count')
            ? lib.lookupFunction<_LibCountNative, _LibCountDart>('ch_library_count')
            : null,
        libraryPath = lib.providesSymbol('ch_library_path')
            ? lib.lookupFunction<_LibPathNative, _LibPathDart>('ch_library_path')
            : null,
        libraryRemovedFn = lib.providesSymbol('ch_library_removed')
            ? lib.lookupFunction<_LibCountNative, _LibCountDart>('ch_library_removed')
            : null,
        set9D = lib.providesSymbol('ch_engine_set_9d')
            ? lib.lookupFunction<_SetIntTwoFloatsNative, _SetIntTwoFloatsDart>(
                'ch_engine_set_9d')
            : null,
        nineDEnabled = lib.providesSymbol('ch_engine_9d_enabled')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_9d_enabled')
            : null,
        nineDSpeed = lib.providesSymbol('ch_engine_9d_speed')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_9d_speed')
            : null,
        nineDDepth = lib.providesSymbol('ch_engine_9d_depth')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_9d_depth')
            : null,
        setStereoEnhance = lib.providesSymbol('ch_engine_set_stereo_enhance')
            ? lib.lookupFunction<_SetTwoFloatsNative, _SetTwoFloatsDart>(
                'ch_engine_set_stereo_enhance')
            : null,
        setStereoWidthFn = lib.providesSymbol('ch_engine_set_stereo_width')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_stereo_width')
            : null,
        stereoWidthFn = lib.providesSymbol('ch_engine_stereo_width')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_stereo_width')
            : null,
        bassPunchFn = lib.providesSymbol('ch_engine_bass_punch')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_bass_punch')
            : null,
        setVocalCut = lib.providesSymbol('ch_engine_set_vocal_cut')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_vocal_cut')
            : null,
        vocalCutFn = lib.providesSymbol('ch_engine_vocal_cut')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_vocal_cut')
            : null,
        setCrossfeedFn = lib.providesSymbol('ch_engine_set_crossfeed')
            ? lib.lookupFunction<_SetIntAndFloatNative, _SetIntAndFloatDart>(
                'ch_engine_set_crossfeed')
            : null,
        crossfeedFn = lib.providesSymbol('ch_engine_crossfeed')
            ? lib.lookupFunction<_OutFloatNative, _OutFloatDart>('ch_engine_crossfeed')
            : null,
        setNightMode = lib.providesSymbol('ch_engine_set_night_mode')
            ? lib.lookupFunction<_SetIntAndFloatNative, _SetIntAndFloatDart>(
                'ch_engine_set_night_mode')
            : null,
        nightModeFn = lib.providesSymbol('ch_engine_night_mode')
            ? lib.lookupFunction<_OutFloatNative, _OutFloatDart>('ch_engine_night_mode')
            : null,
        setS16 = lib.providesSymbol('ch_engine_set_s16_output')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_s16_output')
            : null,
        s16Fn = lib.providesSymbol('ch_engine_s16_output')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_s16_output')
            : null,
        spectrum = lib.providesSymbol('ch_engine_spectrum')
            ? lib.lookupFunction<_SpectrumNative, _SpectrumDart>('ch_engine_spectrum')
            : null,
        setReplayGain = lib.providesSymbol('ch_engine_set_replaygain')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_replaygain')
            : null,
        rgGainDb = lib.providesSymbol('ch_engine_replaygain_gain_db')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>(
                'ch_engine_replaygain_gain_db')
            : null,
        rgPeak = lib.providesSymbol('ch_engine_replaygain_peak')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>(
                'ch_engine_replaygain_peak')
            : null,
        speed = lib.providesSymbol('ch_engine_speed')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_speed')
            : null,
        setSpeed = lib.providesSymbol('ch_engine_set_speed')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_speed')
            : null,
        pitch = lib.providesSymbol('ch_engine_pitch')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_pitch')
            : null,
        setPitch = lib.providesSymbol('ch_engine_set_pitch')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_pitch')
            : null,
        crossfade = lib.providesSymbol('ch_engine_crossfade')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_crossfade')
            : null,
        setCrossfade = lib.providesSymbol('ch_engine_set_crossfade')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_crossfade')
            : null,
        gapless = lib.providesSymbol('ch_engine_gapless')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_gapless')
            : null,
        setGapless = lib.providesSymbol('ch_engine_set_gapless')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_gapless')
            : null,
        setSleepTimer = lib.providesSymbol('ch_engine_set_sleep_timer')
            ? lib.lookupFunction<_TwoDoublesNative, _TwoDoublesDart>(
                'ch_engine_set_sleep_timer')
            : null,
        sleepRemaining = lib.providesSymbol('ch_engine_sleep_remaining')
            ? lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_sleep_remaining')
            : null,
        detectSilence = lib.providesSymbol('ch_engine_detect_silence')
            ? lib.lookupFunction<_SilenceNative, _SilenceDart>('ch_engine_detect_silence')
            : null,
        deviceCount = lib.providesSymbol('ch_engine_output_device_count')
            ? lib.lookupFunction<_NoArgIntNative, _NoArgIntDart>(
                'ch_engine_output_device_count')
            : null,
        deviceName = lib.providesSymbol('ch_engine_output_device_name')
            ? lib.lookupFunction<_DeviceNameNative, _DeviceNameDart>(
                'ch_engine_output_device_name')
            : null,
        currentDevice = lib.providesSymbol('ch_engine_output_device')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_output_device')
            : null,
        setOutputDevice = lib.providesSymbol('ch_engine_set_output_device')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_output_device')
            : null,
        lyricsCount = lib.providesSymbol('ch_engine_lyrics_count')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_lyrics_count')
            : null,
        lyricLine = lib.providesSymbol('ch_engine_lyric_line')
            ? lib.lookupFunction<_LyricLineNative, _LyricLineDart>('ch_engine_lyric_line')
            : null,
        soundscapeSet = lib.providesSymbol('ch_engine_set_soundscape')
            ? lib.lookupFunction<_SetIntAndFloatNative, _SetIntAndFloatDart>(
                'ch_engine_set_soundscape')
            : null,
        soundscapeGet = lib.providesSymbol('ch_engine_soundscape')
            ? lib.lookupFunction<_FloatOutNative, _FloatOutDart>('ch_engine_soundscape')
            : null,
        detectBpm = lib.providesSymbol('ch_engine_detect_bpm')
            ? lib.lookupFunction<_BpmNative, _BpmDart>('ch_engine_detect_bpm')
            : null,
        renderFlat = lib.providesSymbol('ch_engine_render_wav')
            ? lib.lookupFunction<_RenderNative, _RenderDart>('ch_engine_render_wav')
            : null,
        renderDsp = lib.providesSymbol('ch_engine_render_wav_ex')
            ? lib.lookupFunction<_RenderDspNative, _RenderDspDart>(
                'ch_engine_render_wav_ex')
            : null,
        cueRead = lib.providesSymbol('ch_cue_read')
            ? lib.lookupFunction<_HandlePathNative, _HandlePathDart>('ch_cue_read')
            : null,
        cueParse = lib.providesSymbol('ch_cue_parse')
            ? lib.lookupFunction<_HandlePathNative, _HandlePathDart>('ch_cue_parse')
            : null,
        markersCreate = lib.providesSymbol('ch_markers_create')
            ? lib.lookupFunction<_LibCreateNative, _LibCreateDart>('ch_markers_create')
            : null,
        markersDestroy = lib.providesSymbol('ch_markers_destroy')
            ? lib.lookupFunction<_HandleVoidNative, _HandleVoidDart>('ch_markers_destroy')
            : null,
        markersLoad = lib.providesSymbol('ch_markers_load')
            ? lib.lookupFunction<_MarkersTrackNative, _MarkersTrackDart>('ch_markers_load')
            : null,
        markersSave = lib.providesSymbol('ch_markers_save')
            ? lib.lookupFunction<_MarkersTrackNative, _MarkersTrackDart>('ch_markers_save')
            : null,
        markersAdd = lib.providesSymbol('ch_markers_add')
            ? lib.lookupFunction<_MarkersAddNative, _MarkersAddDart>('ch_markers_add')
            : null,
        markersCount = lib.providesSymbol('ch_markers_count')
            ? lib.lookupFunction<_MarkersTrackNative, _MarkersTrackDart>('ch_markers_count')
            : null,
        markersPosition = lib.providesSymbol('ch_markers_position')
            ? lib.lookupFunction<_MarkersDoubleNative, _MarkersDoubleDart>(
                'ch_markers_position')
            : null,
        markersName = lib.providesSymbol('ch_markers_name')
            ? lib.lookupFunction<_MarkersNameNative, _MarkersNameDart>('ch_markers_name')
            : null,
        markersRemove = lib.providesSymbol('ch_markers_remove')
            ? lib.lookupFunction<_MarkersIndexNative, _MarkersIndexDart>(
                'ch_markers_remove')
            : null,
        markersClear = lib.providesSymbol('ch_markers_clear')
            ? lib.lookupFunction<_MarkersTrackNative, _MarkersTrackDart>('ch_markers_clear')
            : null;

  static final _Bindings instance = _Bindings._(_open());

  final _CreateDart create;
  final _DestroyDart destroy;
  final _LoadDart load;
  final _ControlDart play;
  final _ControlDart pause;

  /// `null` si la librería cargada es anterior a la ABI 2 (sin next/previous).
  final _ControlDart? next;
  final _ControlDart? previous;
  final _SeekDart seek;
  final _VolumeDart setVolume;
  final _EqCountDart eqBandCount;
  final _EqFreqDart? eqBandFreq;
  final _EqGainsDart setEqGains;
  final _DoubleDart position;
  final _DoubleDart duration;
  final _IntDart isPlaying;
  final _PollEventDart pollEvent;
  final _LevelsDart? levels;
  final _SetFloatDart? setPauseFade;
  final _GetFloatDart? pauseFade;
  final _SetFloatDart? setEqPreamp;
  final _GetFloatDart? eqPreamp;
  final _SetIntDart? setReplayGainMode;
  final _IntDart? replayGainMode;
  final _SetLoopDart? setLoop;
  final _DoubleDart? loopStart;
  final _DoubleDart? loopEnd;
  final _U64Dart? skippedTracks;
  final _NoArgIntDart? abiVersion;
  final _SetFloatDart? setBalance;
  final _GetFloatDart? balance;
  final _SetIntDart? setRepeat;
  final _IntDart? repeat;
  final _SetIntDart? setShuffle;
  final _IntDart? shuffle;
  final _SetIntDart? setChannelMode;
  final _IntDart? channelMode;
  final _SetIntDart? playIndex;
  final _PathArgDart? loadAdd;
  final _PathArgDart? queueAdd;
  final _IntDart? queueCount;
  final _IntDart? queueIndex;
  final _ControlDart? queueClear;
  final _TwoIntsDart? queueMove;
  final _SetIntDart? queueRemove;
  final _IntAndPathDart? queueInsert;
  final _PathArgDart? queueImport;
  final _PathArgDart? queueExport;
  final _LibCreateDart? libraryCreate;
  final _LibDestroyDart? libraryDestroy;
  final _LibScanDart? libraryScan;
  final _LibCountDart? libraryCount;
  final _LibPathDart? libraryPath;
  final _LibCountDart? libraryRemovedFn;
  final _SetIntTwoFloatsDart? set9D;
  final _IntDart? nineDEnabled;
  final _GetFloatDart? nineDSpeed;
  final _GetFloatDart? nineDDepth;
  final _SetTwoFloatsDart? setStereoEnhance;
  final _SetFloatDart? setStereoWidthFn;
  final _GetFloatDart? stereoWidthFn;
  final _GetFloatDart? bassPunchFn;
  final _SetFloatDart? setVocalCut;
  final _GetFloatDart? vocalCutFn;
  final _SetIntAndFloatDart? setCrossfeedFn;
  final _OutFloatDart? crossfeedFn;
  final _SetIntAndFloatDart? setNightMode;
  final _OutFloatDart? nightModeFn;
  final _SetIntDart? setS16;
  final _IntDart? s16Fn;
  final _SpectrumDart? spectrum;
  final _SetIntDart? setReplayGain;
  final _GetFloatDart? rgGainDb;
  final _GetFloatDart? rgPeak;
  final _GetFloatDart? speed;
  final _SetFloatDart? setSpeed;
  final _GetFloatDart? pitch;
  final _SetFloatDart? setPitch;
  final _GetFloatDart? crossfade;
  final _SetFloatDart? setCrossfade;
  final _IntDart? gapless;
  final _SetIntDart? setGapless;
  final _TwoDoublesDart? setSleepTimer;
  final _DoubleDart? sleepRemaining;
  final _SilenceDart? detectSilence;
  final _NoArgIntDart? deviceCount;
  final _DeviceNameDart? deviceName;
  final _IntDart? currentDevice;
  final _SetIntDart? setOutputDevice;
  final _IntDart? lyricsCount;
  final _LyricLineDart? lyricLine;
  final _SetIntAndFloatDart? soundscapeSet;
  final _FloatOutDart? soundscapeGet;
  final _BpmDart? detectBpm;
  final _RenderDart? renderFlat;
  final _RenderDspDart? renderDsp;
  final _HandlePathDart? cueRead;
  final _HandlePathDart? cueParse;
  final _LibCreateDart? markersCreate;
  final _HandleVoidDart? markersDestroy;
  final _MarkersTrackDart? markersLoad;
  final _MarkersTrackDart? markersSave;
  final _MarkersAddDart? markersAdd;
  final _MarkersTrackDart? markersCount;
  final _MarkersDoubleDart? markersPosition;
  final _MarkersNameDart? markersName;
  final _MarkersIndexDart? markersRemove;
  final _MarkersTrackDart? markersClear;
  final _TextDart titleFn;
  final _TextDart artistFn;
  final _TextDart albumFn;
  final _IntDart coverCount;
  final _CoverAtDart coverAt;
  final _TextDart engineLastErrorFn;
  final _PlainTextDart coreLastErrorFn;

  String coreLastError() => coreLastErrorFn().toDartString();

  String title(Pointer<Void> engine) => titleFn(engine).toDartString();

  String artist(Pointer<Void> engine) => artistFn(engine).toDartString();

  String album(Pointer<Void> engine) => albumFn(engine).toDartString();

  String engineLastError(Pointer<Void> engine) {
    final text = engineLastErrorFn(engine).toDartString();
    return text.isEmpty ? 'error desconocido del núcleo' : text;
  }

  static DynamicLibrary _open() {
    if (Platform.isAndroid ||
        Platform.isLinux ||
        Platform.isWindows ||
        Platform.isMacOS) {
      return DynamicLibrary.open(_libraryName);
    }
    throw UnsupportedError('CyberHex aún no soporta ${Platform.operatingSystem}');
  }
}
