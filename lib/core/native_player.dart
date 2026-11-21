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
typedef _SetLoopNative = Int32 Function(Pointer<Void>, Double, Double);
typedef _SetLoopDart = int Function(Pointer<Void>, double, double);

// Cola: mover/quitar/insertar llevan índices; añadir y cargar llevan ruta.
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

const String _libraryName = 'libcyberhex_core.so';

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

  /// Niveles de salida `[rms_l, rms_r, peak_l, peak_r]` (0..1). Lista vacía si
  /// la librería cargada es antigua y no expone `ch_engine_levels`.
  List<double> levels() {
    if (_disposed) return const [];
    final fn = _bindings.levels;
    if (fn == null) return const [];
    final count = fn(_engine, _levelBuf, 4);
    if (count <= 0) return const [];
    return List<double>.generate(count, (i) => _levelBuf[i]);
  }

  /// Fundido de pausa en segundos (0 = corte inmediato).
  void setPauseFade(double seconds) =>
      _bindings.setPauseFade?.call(_engine, seconds);

  double get pauseFade => _bindings.pauseFade?.call(_engine) ?? 0.05;

  /// Preamp del EQ en dB (0 a -24).
  void setEqPreamp(double db) => _bindings.setEqPreamp?.call(_engine, db);

  double get eqPreamp => _bindings.eqPreamp?.call(_engine) ?? 0;

  /// ReplayGain por álbum (una ganancia para todo el disco) o por pista.
  /// Solo afecta a las pistas que se abran después.
  void setReplayGainAlbum(bool album) =>
      _bindings.setReplayGainMode?.call(_engine, album ? 1 : 0);

  bool get replayGainAlbum =>
      (_bindings.replayGainMode?.call(_engine) ?? 0) == 1;

  /// Loop A-B en segundos; `end <= start` lo desactiva.
  void setLoop(double start, double end) =>
      _bindings.setLoop?.call(_engine, start, end);

  double get loopStart => _bindings.loopStart?.call(_engine) ?? -1;

  double get loopEnd => _bindings.loopEnd?.call(_engine) ?? -1;

  /// Pistas que el motor se saltó por no poder abrirlas.
  int get skippedTracks => _bindings.skippedTracks?.call(_engine) ?? 0;

  /// Balance estéreo: -1 izquierda, 0 centro, +1 derecha.
  void setBalance(double balance) => _bindings.setBalance?.call(_engine, balance);

  double get balance => _bindings.balance?.call(_engine) ?? 0;

  /// 0 = estéreo, 1 = mono, 2 = canales intercambiados.
  void setChannelMode(int mode) =>
      _bindings.setChannelMode?.call(_engine, mode);

  int get channelMode => _bindings.channelMode?.call(_engine) ?? 0;

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

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    calloc.free(_eventBuf);
    calloc.free(_levelBuf);
    calloc.free(_outBuf);
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
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open(_libraryName);
    }
    throw UnsupportedError('CyberHex aún no soporta ${Platform.operatingSystem}');
  }
}
