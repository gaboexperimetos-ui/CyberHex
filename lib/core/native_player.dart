import 'dart:ffi';
import 'dart:io';

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

typedef _DoubleNative = Double Function(Pointer<Void>);
typedef _DoubleDart = double Function(Pointer<Void>);

typedef _IntNative = Int32 Function(Pointer<Void>);
typedef _IntDart = int Function(Pointer<Void>);

typedef _TextNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _TextDart = Pointer<Utf8> Function(Pointer<Void>);

typedef _PlainTextNative = Pointer<Utf8> Function();
typedef _PlainTextDart = Pointer<Utf8> Function();

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
  String? _path;
  bool _loaded = false;
  double _duration = 0;
  bool _disposed = false;

  String? get title => _title;
  String? get path => _path;
  bool get hasTrack => _loaded;
  double get duration => _duration;
  double get position => _bindings.position(_engine);
  bool get isPlaying => _bindings.isPlaying(_engine) != 0;

  String get lastError => _bindings.engineLastError(_engine);

  bool load(String path) {
    final utf8 = path.toNativeUtf8();
    try {
      final result = _bindings.load(_engine, utf8);
      if (result != 0) {
        return false;
      }
      _path = path;
      _title = _fileName(path);
      _duration = _bindings.duration(_engine);
      _loaded = true;
      return true;
    } finally {
      malloc.free(utf8);
    }
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

  void setVolume(double value) => _bindings.setVolume(_engine, value.clamp(0, 1));

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
        setEqGains = lib.lookupFunction<_EqGainsNative, _EqGainsDart>('ch_engine_set_eq_gains'),
        position = lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_position'),
        duration = lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_duration'),
        isPlaying = lib.lookupFunction<_IntNative, _IntDart>('ch_engine_is_playing'),
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
  final _EqGainsDart setEqGains;
  final _DoubleDart position;
  final _DoubleDart duration;
  final _IntDart isPlaying;
  final _TextDart engineLastErrorFn;
  final _PlainTextDart coreLastErrorFn;

  String coreLastError() => coreLastErrorFn().toDartString();

  String engineLastError(Pointer<Void> engine) {
    final text = engineLastErrorFn(engine).toDartString();
    return text.isEmpty ? 'error desconocido del núcleo' : text;
  }

  static DynamicLibrary _open() {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libcyberhex_core.so');
    }
    throw UnsupportedError('CyberHex aún no soporta ${Platform.operatingSystem}');
  }
}
