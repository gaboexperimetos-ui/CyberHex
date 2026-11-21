import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

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

class CyberHexException implements Exception {
  CyberHexException(this.message);
  final String message;

  @override
  String toString() => message;
}

class NativePlayer {
  NativePlayer._(this._engine, this._bindings);

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
  String? get title => _title;
  String get artist => _artist ?? '';
  String get album => _album ?? '';
  String? get path => _path;
  Uint8List? get cover => _cover;
  bool get hasTrack => _loaded;
  double get duration => _duration;
  double get position => _bindings.position(_engine);
  bool get isPlaying => _bindings.isPlaying(_engine) != 0;

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
  late final List<double> eqBandFrequencies = List<double>.unmodifiable([
    for (var i = 0; i < eqGains.length; i++)
      _freqOrFallback(_bindings.eqBandFreq?.call(i) ?? 0, i, eqGains.length),
  ]);

  static double _freqOrFallback(double hz, int index, int count) {
    if (hz > 0) return hz;
    if (count <= 1) return 20;
    return 20.0 * math.pow(1000.0, index / (count - 1)).toDouble();
  }

  bool load(String path) {
    if (_disposed) return false;
    final utf8 = path.toNativeUtf8();
    try {
      if (_bindings.load(_engine, utf8) != 0) {
        return false;
      }
      _applyMetadata(path);
      return true;
    } finally {
      malloc.free(utf8);
    }
  }

  /// Igual que [load] pero fuera del hilo de UI.
  Future<bool> loadAsync(String path) async {
    if (_disposed) return false;
    try {
      final address = _engine.address;
      final ok = await Isolate.run(() => _loadTrackInIsolate(address, path));
      if (!ok || _disposed) return false;
      _applyMetadata(path);
      return true;
    } catch (error) {
      _failure = error.toString();
      return false;
    }
  }

  void _applyMetadata(String path) {
    _path = path;
    final tag = _bindings.title(_engine).trim();
    _title = tag.isEmpty ? _fileName(path) : tag;
    _artist = _bindings.artist(_engine).trim();
    _album = _bindings.album(_engine).trim();
    _duration = _bindings.duration(_engine);
    _cover = _readCover();
    _loaded = true;
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

  void play() => _bindings.play(_engine);

  void pause() => _bindings.pause(_engine);

  void toggle() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void seek(double seconds) => _bindings.seek(_engine, seconds);

  void setVolume(double value) =>
      _bindings.setVolume(_engine, value.clamp(0, 1).toDouble());

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

  void resetEq() {
    for (var i = 0; i < eqGains.length; i++) {
      eqGains[i] = 0;
    }
    setBand(0, 0);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
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
        setVolume = lib.lookupFunction<_VolumeNative, _VolumeDart>('ch_engine_set_volume'),
        eqBandCount = lib.lookupFunction<_EqCountNative, _EqCountDart>('ch_engine_eq_band_count'),
        eqBandFreq = lib.providesSymbol('ch_engine_eq_band_freq')
            ? lib.lookupFunction<_EqFreqNative, _EqFreqDart>('ch_engine_eq_band_freq')
            : null,
        setEqGains = lib.lookupFunction<_EqGainsNative, _EqGainsDart>('ch_engine_set_eq_gains'),
        position = lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_position'),
        duration = lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_duration'),
        isPlaying = lib.lookupFunction<_IntNative, _IntDart>('ch_engine_is_playing'),
        titleFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_title'),
        artistFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_artist'),
        albumFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_album'),
        coverCount = lib.lookupFunction<_IntNative, _IntDart>('ch_engine_cover_count'),
        coverAt =
            lib.lookupFunction<_CoverAtNative, _CoverAtDart>('ch_engine_cover_at'),
        engineLastErrorFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_last_error'),
        coreLastErrorFn = lib.lookupFunction<_PlainTextNative, _PlainTextDart>('ch_core_last_error');

  static final _Bindings instance = _Bindings._(_open());

  final _CreateDart create;
  final _DestroyDart destroy;
  final _LoadDart load;
  final _ControlDart play;
  final _ControlDart pause;
  final _SeekDart seek;
  final _VolumeDart setVolume;
  final _EqCountDart eqBandCount;
  final _EqFreqDart? eqBandFreq;
  final _EqGainsDart setEqGains;
  final _DoubleDart position;
  final _DoubleDart duration;
  final _IntDart isPlaying;
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
