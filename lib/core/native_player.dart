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

/// Espejo de `ch_result` (core/include/cyberhex_core.h).
enum ChResult {
  ok,
  noMem,
  invalidArg,
  decode,
  device,
  io,
  format,
  notFound,
  unsupported,
  state,
  busy,
  cancelled,
}

/// Convierte un `ChResult` a su código entero C (`ch_result`).
int chResultToInt(ChResult r) {
  switch (r) {
    case ChResult.ok:
      return 0;
    case ChResult.noMem:
      return -1;
    case ChResult.invalidArg:
      return -2;
    case ChResult.decode:
      return -3;
    case ChResult.device:
      return -4;
    case ChResult.io:
      return -5;
    case ChResult.format:
      return -6;
    case ChResult.notFound:
      return -7;
    case ChResult.unsupported:
      return -8;
    case ChResult.state:
      return -9;
    case ChResult.busy:
      return -10;
    case ChResult.cancelled:
      return -11;
  }
}

/// Devuelve el mensaje legible del núcleo para un código de resultado, o un
/// mensaje genérico si la función nativa no está disponible.
String chResultStr(ChResult r) {
  final fn = _Bindings.instance.resultStr;
  if (fn == null) {
    switch (r) {
      case ChResult.ok:
        return 'OK';
      case ChResult.noMem:
        return 'sin memoria';
      case ChResult.invalidArg:
        return 'argumento invalido';
      case ChResult.decode:
        return 'error de decodificacion';
      case ChResult.device:
        return 'error de dispositivo de audio';
      case ChResult.io:
        return 'error de E/S';
      case ChResult.format:
        return 'formato no soportado';
      case ChResult.notFound:
        return 'no encontrado';
      case ChResult.unsupported:
        return 'no soportado';
      case ChResult.state:
        return 'estado invalido';
      case ChResult.busy:
        return 'dispositivo ocupado';
      case ChResult.cancelled:
        return 'cancelado';
    }
  }
  return fn(chResultToInt(r)).toDartString();
}

/// Lanza [CyberHexException] con el código y mensaje cuando `rc != CH_OK`.
/// Útil para envolver llamadas nativas que devuelven `ch_result`.
void chResultRequireOk(int rc, String what) {
  if (rc != 0) {
    throw CyberHexException(
        'falló $what: código ${chResultIntToEnum(rc)} (${chResultStr(chResultIntToEnum(rc))})');
  }
}

/// Mapea un código entero C a [ChResult] (valores desconocidos -> cancelled).
ChResult chResultIntToEnum(int rc) {
  switch (rc) {
    case 0:
      return ChResult.ok;
    case -1:
      return ChResult.noMem;
    case -2:
      return ChResult.invalidArg;
    case -3:
      return ChResult.decode;
    case -4:
      return ChResult.device;
    case -5:
      return ChResult.io;
    case -6:
      return ChResult.format;
    case -7:
      return ChResult.notFound;
    case -8:
      return ChResult.unsupported;
    case -9:
      return ChResult.state;
    case -10:
      return ChResult.busy;
    case -11:
      return ChResult.cancelled;
    default:
      return ChResult.cancelled;
  }
}


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

/// Espejo de `ch_loudness_result` (core/include/cyberhex_core.h).
final class _ChLoudness extends Struct {
  @Double()
  external double integratedLufs;

  @Double()
  external double samplePeakDbfs;

  @Double()
  external double durationS;
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
typedef _SetLoopNative = Int32 Function(Pointer<Void>, Double, Double);
typedef _SetLoopDart = int Function(Pointer<Void>, double, double);
typedef _U64Native = Uint64 Function(Pointer<Void>);
typedef _U64Dart = int Function(Pointer<Void>);
typedef _NoArgIntNative = Int32 Function();
typedef _NoArgIntDart = int Function();
typedef _MoveNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _MoveDart = int Function(Pointer<Void>, int, int);
typedef _InsertNative = Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>);
typedef _InsertDart = int Function(Pointer<Void>, int, Pointer<Utf8>);
typedef _SeedNative = Int32 Function(Pointer<Void>, Uint32);
typedef _SeedDart = int Function(Pointer<Void>, int);
typedef _LoadStateNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Double>);
typedef _LoadStateDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Double>);
typedef _TagNative = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _TagDart = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _LyricLineNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _LyricLineDart = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _IntFloatNative = Int32 Function(Pointer<Void>, Int32, Float);
typedef _IntFloatDart = int Function(Pointer<Void>, int, double);
typedef _FloatOutNative = Int32 Function(Pointer<Void>, Pointer<Float>);
typedef _FloatOutDart = int Function(Pointer<Void>, Pointer<Float>);
typedef _MeterNative = Int32 Function(
    Pointer<Void>, Pointer<Float>, Pointer<Float>, Pointer<Float>);
typedef _MeterDart = int Function(
    Pointer<Void>, Pointer<Float>, Pointer<Float>, Pointer<Float>);
typedef _TwoDoubleOutNative = Int32 Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>);
typedef _TwoDoubleOutDart = int Function(
    Pointer<Void>, Pointer<Double>, Pointer<Double>);
typedef _NormalizeNative = Int32 Function(Pointer<Void>, Double, Pointer<Double>);
typedef _NormalizeDart = int Function(Pointer<Void>, double, Pointer<Double>);
typedef _DetectSilenceNative = Int32 Function(
    Pointer<Utf8>, Float, Pointer<Double>, Pointer<Double>);
typedef _DetectSilenceDart = int Function(
    Pointer<Utf8>, double, Pointer<Double>, Pointer<Double>);
typedef _TextAtNative = Pointer<Utf8> Function(Pointer<Void>, Int32);
typedef _TextAtDart = Pointer<Utf8> Function(Pointer<Void>, int);
typedef _ResultStrNative = Pointer<Utf8> Function(Int32);
typedef _ResultStrDart = Pointer<Utf8> Function(int);
typedef _DoubleAtNative = Double Function(Pointer<Void>, Int32);
typedef _DoubleAtDart = double Function(Pointer<Void>, int);
typedef _MarkerAddNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Double, Pointer<Utf8>);
typedef _MarkerAddDart = int Function(
    Pointer<Void>, Pointer<Utf8>, double, Pointer<Utf8>);
typedef _MarkerPosNative = Double Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _MarkerPosDart = double Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _MarkerNameNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Int32);
typedef _MarkerNameDart = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, int);
typedef _MarkerRemoveNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int32);
typedef _MarkerRemoveDart = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _CueReadNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _CueReadDart = Pointer<Void> Function(Pointer<Utf8>);
typedef _TextIndexNative = Pointer<Utf8> Function(Int32);
typedef _TextIndexDart = Pointer<Utf8> Function(int);
typedef _WaveformNative = Int32 Function(Pointer<Utf8>, Uint32, Pointer<Float>);
typedef _WaveformDart = int Function(Pointer<Utf8>, int, Pointer<Float>);
typedef _LoudnessNative = Int32 Function(Pointer<Utf8>, Pointer<_ChLoudness>);
typedef _LoudnessDart = int Function(Pointer<Utf8>, Pointer<_ChLoudness>);

// --- DSP / efectos avanzados -------------------------------------------------
typedef _Set8dNative = Int32 Function(Pointer<Void>, Int32, Float, Float);
typedef _Set8dDart = int Function(Pointer<Void>, int, double, double);
typedef _EightDNative = Int32 Function(Pointer<Void>, Pointer<Float>, Pointer<Float>);
typedef _EightDDart = int Function(Pointer<Void>, Pointer<Float>, Pointer<Float>);
typedef _SetHrtfNative = Int32 Function(Pointer<Void>, Int32, Float);
typedef _SetHrtfDart = int Function(Pointer<Void>, int, double);
typedef _HrtfNative = Int32 Function(Pointer<Void>, Pointer<Float>);
typedef _HrtfDart = int Function(Pointer<Void>, Pointer<Float>);
typedef _SetReverbNative = Int32 Function(Pointer<Void>, Int32, Float);
typedef _SetReverbDart = int Function(Pointer<Void>, int, double);
typedef _ReverbNative = Int32 Function(Pointer<Void>, Pointer<Float>);
typedef _ReverbDart = int Function(Pointer<Void>, Pointer<Float>);
typedef _SetCompressorNative = Int32 Function(
    Pointer<Void>, Int32, Float, Float, Float, Float);
typedef _SetCompressorDart = int Function(
    Pointer<Void>, int, double, double, double, double);
typedef _CompressorNative = Int32 Function(
    Pointer<Void>, Pointer<Float>, Pointer<Float>);
typedef _CompressorDart = int Function(
    Pointer<Void>, Pointer<Float>, Pointer<Float>);
typedef _SetPeqNative = Int32 Function(
    Pointer<Void>, Int32, Int32, Int32, Float, Float, Float);
typedef _SetPeqDart = int Function(
    Pointer<Void>, int, int, int, double, double, double);
typedef _PeqNative = Int32 Function(Pointer<Void>, Int32, Pointer<Int32>,
    Pointer<Float>, Pointer<Float>, Pointer<Float>);
typedef _PeqDart = int Function(Pointer<Void>, int, Pointer<Int32>,
    Pointer<Float>, Pointer<Float>, Pointer<Float>);

// --- Exportación / análisis offline ------------------------------------------
typedef _ExportWavNative = Int32 Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<Utf8>, Double, Double, Int32, Int32);
typedef _ExportWavDart = int Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<Utf8>, double, double, int, int);
typedef _ConcatWavNative = Int32 Function(
    Pointer<Void>, Pointer<Pointer<Utf8>>, Int32, Pointer<Utf8>, Int32);
typedef _ConcatWavDart = int Function(
    Pointer<Void>, Pointer<Pointer<Utf8>>, int, Pointer<Utf8>, int);
typedef _SplitSilenceNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Float, Double, Int32);
typedef _SplitSilenceDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, double, double, int);
typedef _SpectrogramPngNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Int32, Int32);
typedef _SpectrogramPngDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int, int);
typedef _DoubleOutNative = Int32 Function(Pointer<Void>, Pointer<Double>);
typedef _DoubleOutDart = int Function(Pointer<Void>, Pointer<Double>);
typedef _CountSilencesNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Float, Double, Pointer<Double>, Int32);
typedef _CountSilencesDart = int Function(
    Pointer<Void>, Pointer<Utf8>, double, double, Pointer<Double>, int);
typedef _StripSilenceNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Float, Double, Double, Int32);
typedef _StripSilenceDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, double, double, double, int);
typedef _ExportIntNative = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _ExportIntDart = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _ExportPngNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int32, Int32);
typedef _ExportPngDart = int Function(Pointer<Void>, Pointer<Utf8>, int, int);
typedef _ExportSpectrumPngNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Int32, Int32, Int32);
typedef _ExportSpectrumPngDart = int Function(
    Pointer<Void>, Pointer<Utf8>, int, int, int);

// --- Utilidades --------------------------------------------------------------
typedef _SetTagNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetTagDart = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetDoubleNative = Int32 Function(Pointer<Void>, Double);
typedef _SetDoubleDart = int Function(Pointer<Void>, double);
typedef _DetectKeyNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Uint32, Pointer<Double>);
typedef _DetectKeyDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Double>);
typedef _KeyCurrentNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Uint32, Pointer<Double>);
typedef _KeyCurrentDart = int Function(
    Pointer<Void>, Pointer<Utf8>, int, Pointer<Double>);
typedef _SetAutoGainNative = Int32 Function(Pointer<Void>, Int32, Double);
typedef _SetAutoGainDart = int Function(Pointer<Void>, int, double);
typedef _LibraryExportNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _LibraryExportDart = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _LibraryRemoveNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _LibraryRemoveDart = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _EqPresetNameNative = Int32 Function(Int32, Pointer<Utf8>, Int32);
typedef _EqPresetNameDart = int Function(int, Pointer<Utf8>, int);
typedef _EqPresetFindNative = Int32 Function(Pointer<Utf8>);
typedef _EqPresetFindDart = int Function(Pointer<Utf8>);
typedef _CopyTagsNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _CopyTagsDart = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _BpmDetectNative = Double Function(Pointer<Utf8>);
typedef _BpmDetectDart = double Function(Pointer<Utf8>);
typedef _DrMeasureNative = Double Function(Pointer<Utf8>, Pointer<Uint32>);
typedef _DrMeasureDart = double Function(Pointer<Utf8>, Pointer<Uint32>);
typedef _EngineDrNative = Double Function(Pointer<Void>, Pointer<Uint32>);
typedef _EngineDrDart = double Function(Pointer<Void>, Pointer<Uint32>);

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

List<double> _waveformInIsolate(String path, int buckets) {
  final lib = DynamicLibrary.open(_libraryName);
  if (!lib.providesSymbol('ch_waveform_peaks')) return const [];
  final waveform =
      lib.lookupFunction<_WaveformNative, _WaveformDart>('ch_waveform_peaks');
  final out = calloc<Float>(buckets);
  final utf8 = path.toNativeUtf8();
  try {
    final result = waveform(utf8, buckets, out);
    if (result != 0) return const [];
    return List<double>.generate(buckets, (i) => out[i]);
  } finally {
    malloc.free(utf8);
    calloc.free(out);
  }
}

class CyberHexException implements Exception {
  CyberHexException(this.message);
  final String message;

  @override
  String toString() => message;
}

class NativePlayer extends PlayerApi {
  NativePlayer._(this._engine, this._bindings) {
    _eventBuf = calloc<_ChEvent>();
    _levelBuf = calloc<Float>(4);
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

  /// Handle perezoso de `ch_library_*` para exportar/gestionar la biblioteca.
  /// Se crea bajo demanda y se libera en [dispose].
  Pointer<Void>? _library;

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

  @override
  void seek(double seconds) => _bindings.seek(_engine, seconds);

  @override
  void setVolume(double value) =>
      _bindings.setVolume(_engine, value.clamp(0, 1).toDouble());

  @override
  double get volume => _bindings.volume?.call(_engine) ?? 1;

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

  // ---------------------------------------------------------------------------
  // Medición y DSP
  // ---------------------------------------------------------------------------

  /// Niveles de salida `[rms_l, rms_r, peak_l, peak_r]` (0..1). Lista vacía si
  /// la librería cargada es antigua y no expone `ch_engine_levels`.
  @override
  List<double> get levels {
    if (_disposed) return const [];
    final fn = _bindings.levels;
    if (fn == null) return const [];
    final count = fn(_engine, _levelBuf, 4);
    if (count <= 0) return const [];
    return List<double>.generate(count, (i) => _levelBuf[i]);
  }

  @override
  List<double> get meterLevels {
    final fn = _bindings.meter;
    if (fn == null || _disposed) return const [];
    final left = calloc<Float>();
    final right = calloc<Float>();
    final rms = calloc<Float>();
    try {
      if (fn(_engine, left, right, rms) != 0) return const [];
      return <double>[left.value, right.value, rms.value];
    } finally {
      calloc.free(left);
      calloc.free(right);
      calloc.free(rms);
    }
  }

  @override
  List<double> spectrum(int bands) {
    final fn = _bindings.spectrum;
    if (fn == null || _disposed || bands <= 0 || bands > 512) return const [];
    final buffer = calloc<Float>(bands);
    try {
      final count = fn(_engine, buffer, bands);
      if (count <= 0) return const [];
      return List<double>.generate(count, (i) => buffer[i]);
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  set eqPreamp(double db) => setEqPreamp(db);

  @override
  bool setBandGain(int band, double db) =>
      _bindings.setBandGain?.call(_engine, band, db) == 0;

  @override
  void setLimiter(bool enabled, {double ceilingDb = -1}) =>
      _bindings.setLimiter?.call(_engine, enabled ? 1 : 0, ceilingDb);

  @override
  bool get limiter => (_bindings.limiter?.call(_engine) ?? 0) != 0;

  @override
  void setCrossfeed(bool enabled, {double strength = 0.5}) =>
      _bindings.setCrossfeed?.call(_engine, enabled ? 1 : 0, strength);

  @override
  ({bool enabled, double strength}) get crossfeed {
    final fn = _bindings.crossfeed;
    if (fn == null || _disposed) return (enabled: false, strength: 0);
    final strength = calloc<Float>();
    try {
      final enabled = fn(_engine, strength) != 0;
      return (enabled: enabled, strength: strength.value);
    } finally {
      calloc.free(strength);
    }
  }

  @override
  double get gainDb => _bindings.gainDb?.call(_engine) ?? 0;

  @override
  set gainDb(double db) => _bindings.setGainDb?.call(_engine, db);

  @override
  double get stereoWidth => _bindings.stereoWidth?.call(_engine) ?? 1;

  @override
  set stereoWidth(double width) =>
      _bindings.setStereoWidth?.call(_engine, width);

  @override
  void setTrimSilence(bool enabled, {double thresholdDb = -60}) =>
      _bindings.setTrimSilence?.call(_engine, enabled ? 1 : 0, thresholdDb);

  @override
  ({bool enabled, double thresholdDb}) get trimSilence {
    final fn = _bindings.trimSilence;
    if (fn == null || _disposed) return (enabled: false, thresholdDb: -60);
    final threshold = calloc<Float>();
    try {
      final enabled = fn(_engine, threshold) != 0;
      return (enabled: enabled, thresholdDb: threshold.value);
    } finally {
      calloc.free(threshold);
    }
  }

  @override
  void setReplayGain(bool enabled) =>
      _bindings.setReplayGain?.call(_engine, enabled ? 1 : 0);

  @override
  double get replayGainGainDb => _bindings.replayGainGainDb?.call(_engine) ?? 0;

  @override
  double get replayGainPeak => _bindings.replayGainPeak?.call(_engine) ?? 0;

  @override
  void setMono(bool enabled) =>
      _bindings.setMono?.call(_engine, enabled ? 1 : 0);

  @override
  bool get mono => (_bindings.mono?.call(_engine) ?? 0) != 0;

  @override
  void setAbLoop(double start, double end) =>
      _bindings.setAbLoop?.call(_engine, start, end);

  @override
  void clearAbLoop() => _bindings.clearAbLoop?.call(_engine);

  @override
  ({double start, double end}) get abLoop {
    final fn = _bindings.abLoop;
    if (fn == null || _disposed) return (start: -1, end: -1);
    final start = calloc<Double>();
    final end = calloc<Double>();
    try {
      if (fn(_engine, start, end) == 0) return (start: -1, end: -1);
      return (start: start.value, end: end.value);
    } finally {
      calloc.free(start);
      calloc.free(end);
    }
  }

  @override
  ({double lufs, double peakDb})? analyzeCurrent() {
    final fn = _bindings.analyzeCurrent;
    if (fn == null || _disposed) return null;
    final lufs = calloc<Double>();
    final peak = calloc<Double>();
    try {
      if (fn(_engine, lufs, peak) != 0) return null;
      return (lufs: lufs.value, peakDb: peak.value);
    } finally {
      calloc.free(lufs);
      calloc.free(peak);
    }
  }

  @override
  double? normalizeCurrent(double targetLufs) {
    final fn = _bindings.normalizeCurrent;
    if (fn == null || _disposed) return null;
    final applied = calloc<Double>();
    try {
      if (fn(_engine, targetLufs, applied) != 0) return null;
      return applied.value;
    } finally {
      calloc.free(applied);
    }
  }

  @override
  double get bufferedSeconds => _bindings.bufferedSeconds?.call(_engine) ?? 0;

  @override
  int get bufferUnderflows => _bindings.bufferUnderflows?.call(_engine) ?? 0;

  @override
  ({double lead, double tail})? detectSilence(String path,
      {double thresholdDb = -60}) {
    final fn = _bindings.detectSilence;
    if (fn == null || _disposed) return null;
    final lead = calloc<Double>();
    final tail = calloc<Double>();
    final utf8 = path.toNativeUtf8();
    try {
      if (fn(utf8, thresholdDb, lead, tail) != 0) return null;
      return (lead: lead.value, tail: tail.value);
    } finally {
      malloc.free(utf8);
      calloc.free(lead);
      calloc.free(tail);
    }
  }

  /// Fundido de pausa en segundos (0 = corte inmediato).
  void setPauseFade(double seconds) =>
      _bindings.setPauseFade?.call(_engine, seconds);

  double get pauseFade => _bindings.pauseFade?.call(_engine) ?? 0.05;

  /// Preamp del EQ en dB (0 a -24).
  void setEqPreamp(double db) => _bindings.setEqPreamp?.call(_engine, db);

  @override
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

  // ---------------------------------------------------------------------------
  // Cola y modos de reproducción
  // ---------------------------------------------------------------------------

  @override
  int get queueCount => _bindings.queueCount?.call(_engine) ?? 0;

  @override
  int get queueIndex => _bindings.queueIndex?.call(_engine) ?? 0;

  @override
  String queueItem(int index) => _text(_bindings.queueItem?.call(_engine, index));

  @override
  bool playIndex(int index) => _bindings.playIndex?.call(_engine, index) == 0;

  @override
  bool loadAdd(String path) {
    final ok =
        _pathCall(path, (ptr) => _bindings.loadAdd?.call(_engine, ptr)) == 0;
    if (ok) {
      _path = path;
      _loaded = true;
      syncTrackInfo();
    }
    return ok;
  }

  @override
  bool queueAdd(String path) =>
      _pathCall(path, (ptr) => _bindings.queueAdd?.call(_engine, ptr)) == 0;

  @override
  bool queueInsert(int index, String path) =>
      _pathCall(path, (ptr) => _bindings.queueInsert?.call(_engine, index, ptr)) ==
          0;

  @override
  bool queueMove(int from, int to) =>
      _bindings.queueMove?.call(_engine, from, to) == 0;

  @override
  bool queueRemove(int index) =>
      _bindings.queueRemove?.call(_engine, index) == 0;

  @override
  bool queueClear() => _bindings.queueClear?.call(_engine) == 0;

  @override
  int queueImport(String path) =>
      _pathCall(path, (ptr) => _bindings.queueImport?.call(_engine, ptr));

  @override
  bool queueExport(String path) =>
      _pathCall(path, (ptr) => _bindings.queueExport?.call(_engine, ptr)) == 0;

  @override
  int get repeatMode => _bindings.repeat?.call(_engine) ?? 0;

  @override
  set repeatMode(int mode) =>
      _bindings.setRepeat?.call(_engine, mode < 0 ? 0 : (mode > 2 ? 2 : mode));

  @override
  bool get shuffle => (_bindings.shuffle?.call(_engine) ?? 0) != 0;

  @override
  set shuffle(bool enabled) =>
      _bindings.setShuffle?.call(_engine, enabled ? 1 : 0);

  @override
  void setShuffleSeed(int seed) =>
      _bindings.setShuffleSeed?.call(_engine, seed & 0xFFFFFFFF);

  @override
  bool get gapless => (_bindings.gapless?.call(_engine) ?? 0) != 0;

  @override
  set gapless(bool enabled) =>
      _bindings.setGapless?.call(_engine, enabled ? 1 : 0);

  @override
  double get crossfadeSeconds => _bindings.crossfade?.call(_engine) ?? 0;

  @override
  set crossfadeSeconds(double seconds) =>
      _bindings.setCrossfade?.call(_engine, seconds.clamp(0.0, 30.0).toDouble());

  @override
  double get speed => _bindings.speed?.call(_engine) ?? 1;

  @override
  set speed(double value) =>
      _bindings.setSpeed?.call(_engine, value.clamp(0.25, 4.0).toDouble());

  @override
  double get pitch => _bindings.pitch?.call(_engine) ?? 0;

  @override
  set pitch(double value) =>
      _bindings.setPitch?.call(_engine, value.clamp(-12.0, 12.0).toDouble());

  @override
  void setSleepTimer(double seconds, {double fadeSeconds = 5}) =>
      _bindings.setSleepTimer?.call(_engine, seconds, fadeSeconds);

  @override
  double get sleepRemaining => _bindings.sleepRemaining?.call(_engine) ?? -1;

  @override
  bool saveState(String path) =>
      _pathCall(path, (ptr) => _bindings.saveState?.call(_engine, ptr)) == 0;

  @override
  double? loadState(String path) {
    final out = calloc<Double>();
    try {
      final rc = _pathCall(
          path, (ptr) => _bindings.loadState?.call(_engine, ptr, out));
      if (rc != 0) return null;
      _loaded = true;
      syncTrackInfo();
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  // ---------------------------------------------------------------------------
  // Biblioteca, marcadores, CUE y utilidades de archivo
  // ---------------------------------------------------------------------------

  @override
  ({List<String> tracks, int removed})? scanLibrary(String root) {
    final b = _bindings;
    final create = b.libraryCreate;
    final destroy = b.libraryDestroy;
    final scan = b.libraryScan;
    final count = b.libraryCount;
    final pathAt = b.libraryPath;
    if (create == null || destroy == null || scan == null || count == null) {
      return null;
    }
    final handle = create();
    if (handle == nullptr) return null;
    final utf8 = root.toNativeUtf8();
    try {
      if (scan(handle, utf8) < 0) return null;
      final total = count(handle);
      final tracks = <String>[];
      if (pathAt != null) {
        for (var i = 0; i < total; i++) {
          final path = _text(pathAt(handle, i));
          if (path.isNotEmpty) tracks.add(path);
        }
      }
      return (tracks: tracks, removed: b.libraryRemoved?.call(handle) ?? 0);
    } finally {
      malloc.free(utf8);
      destroy(handle);
    }
  }

  @override
  List<TrackMarker> loadMarkers(String path, String track) {
    final b = _bindings;
    final create = b.markersCreate;
    final destroy = b.markersDestroy;
    final load = b.markersLoad;
    if (create == null || destroy == null || load == null) return const [];
    final handle = create();
    if (handle == nullptr) return const [];
    final pathUtf8 = path.toNativeUtf8();
    final trackUtf8 = track.toNativeUtf8();
    try {
      if (load(handle, pathUtf8) != 0) return const [];
      final total = b.markersCount?.call(handle, trackUtf8) ?? 0;
      final markers = <TrackMarker>[];
      for (var i = 0; i < total; i++) {
        final position = b.markersPosition?.call(handle, trackUtf8, i) ?? -1;
        if (position < 0) continue;
        markers.add(TrackMarker(
          position,
          _text(b.markersName?.call(handle, trackUtf8, i)),
        ));
      }
      return markers;
    } finally {
      malloc.free(pathUtf8);
      malloc.free(trackUtf8);
      destroy(handle);
    }
  }

  @override
  bool saveMarkers(String path, String track, List<TrackMarker> markers) {
    final b = _bindings;
    final create = b.markersCreate;
    final destroy = b.markersDestroy;
    final add = b.markersAdd;
    final save = b.markersSave;
    if (create == null ||
        destroy == null ||
        add == null ||
        save == null) {
      return false;
    }
    final handle = create();
    if (handle == nullptr) return false;
    final pathUtf8 = path.toNativeUtf8();
    final trackUtf8 = track.toNativeUtf8();
    try {
      for (final marker in markers) {
        final nameUtf8 = marker.name.toNativeUtf8();
        try {
          if (add(handle, trackUtf8, marker.position, nameUtf8) < 0) {
            return false;
          }
        } finally {
          malloc.free(nameUtf8);
        }
      }
      return save(handle, pathUtf8) == 0;
    } finally {
      malloc.free(pathUtf8);
      malloc.free(trackUtf8);
      destroy(handle);
    }
  }

  @override
  bool removeMarker(String path, String track, int index) {
    final current = loadMarkers(path, track);
    if (index < 0 || index >= current.length) return false;
    final next = List<TrackMarker>.of(current)..removeAt(index);
    return saveMarkers(path, track, next);
  }

  @override
  bool clearMarkers(String path, String track) =>
      saveMarkers(path, track, const []);

  @override
  CueSheet? readCue(String path) {
    final b = _bindings;
    final read = b.cueRead;
    final free = b.cueFree;
    if (read == null || free == null) return null;
    final utf8 = path.toNativeUtf8();
    Pointer<Void> cue;
    try {
      cue = read(utf8);
    } finally {
      malloc.free(utf8);
    }
    if (cue == nullptr) return null;
    try {
      final total = b.cueCount?.call(cue) ?? 0;
      final tracks = <CueTrack>[];
      for (var i = 0; i < total; i++) {
        tracks.add(CueTrack(
          number: b.cueNumber?.call(cue, i) ?? 0,
          title: _text(b.cueTitle?.call(cue, i)),
          performer: _text(b.cuePerformer?.call(cue, i)),
          file: _text(b.cueFile?.call(cue, i)),
          start: b.cueStart?.call(cue, i) ?? 0,
          end: b.cueEnd?.call(cue, i) ?? 0,
        ));
      }
      return CueSheet(
        album: _text(b.cueAlbum?.call(cue)),
        albumPerformer: _text(b.cueAlbumPerformer?.call(cue)),
        tracks: tracks,
      );
    } finally {
      free(cue);
    }
  }

  @override
  List<String> get outputDevices {
    final total = _bindings.outputDeviceCount?.call() ?? 0;
    final nameAt = _bindings.outputDeviceName;
    if (total <= 0 || nameAt == null) return const [];
    return List<String>.generate(total, (i) => _text(nameAt(i)));
  }

  @override
  int get outputDevice => _bindings.outputDevice?.call(_engine) ?? -1;

  @override
  set outputDevice(int index) =>
      _bindings.setOutputDevice?.call(_engine, index);

  @override
  ({double lufs, double peakDb, double duration})? scanLoudness(String path) {
    final fn = _bindings.loudnessScan;
    if (fn == null) return null;
    final result = calloc<_ChLoudness>();
    final utf8 = path.toNativeUtf8();
    try {
      if (fn(utf8, result) != 0) return null;
      final value = result.ref;
      return (
        lufs: value.integratedLufs,
        peakDb: value.samplePeakDbfs,
        duration: value.durationS,
      );
    } finally {
      malloc.free(utf8);
      calloc.free(result);
    }
  }

  @override
  List<double> waveform(String path, int buckets) {
    final fn = _bindings.waveformPeaks;
    if (fn == null || buckets <= 0) return const [];
    final out = calloc<Float>(buckets);
    final utf8 = path.toNativeUtf8();
    try {
      final result = fn(utf8, buckets, out);
      if (result != 0) return const [];
      return List<double>.generate(buckets, (i) => out[i]);
    } finally {
      malloc.free(utf8);
      calloc.free(out);
    }
  }

  @override
  Future<List<double>> waveformAsync(String path, int buckets) {
    if (buckets <= 0) return Future.value(const []);
    return Isolate.run(() => _waveformInIsolate(path, buckets));
  }

  @override
  String get coreVersion => _text(_bindings.coreVersion?.call());

  // ---------------------------------------------------------------------------
  // Metadatos completos, letras y carátulas
  // ---------------------------------------------------------------------------

  static String _text(Pointer<Utf8>? ptr) =>
      ptr == null ? '' : ptr.toDartString().trim();

  @override
  String get date => _text(_bindings.dateFn?.call(_engine));

  @override
  String get genre => _text(_bindings.genreFn?.call(_engine));

  @override
  String get composer => _text(_bindings.composerFn?.call(_engine));

  @override
  int get trackNumber => _bindings.trackNumber?.call(_engine) ?? 0;

  @override
  int get discNumber => _bindings.discNumber?.call(_engine) ?? 0;

  @override
  String tag(String key) {
    final fn = _bindings.tag;
    if (fn == null || _disposed) return '';
    final utf8 = key.toNativeUtf8();
    try {
      return _text(fn(_engine, utf8));
    } finally {
      malloc.free(utf8);
    }
  }

  @override
  int get sampleRate =>
      (_bindings.sampleRate?.call(_engine) ?? 0).round();

  @override
  int get channels => _bindings.channels?.call(_engine) ?? 2;

  @override
  bool saveCover(int index, String path) =>
      _pathCall(path, (ptr) => _bindings.saveCover?.call(_engine, index, ptr)) ==
          0;

  @override
  int get lyricsCount => _bindings.lyricsCount?.call(_engine) ?? 0;

  @override
  String get activeLyricLine {
    final fn = _bindings.lyricLine;
    if (fn == null || _disposed) return '';
    const size = 1024;
    final buffer = calloc<Uint8>(size).cast<Utf8>();
    try {
      if (fn(_engine, buffer, size) <= 0) return '';
      return buffer.toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  /// Llama a una función que recibe una ruta UTF-8 y libera el buffer.
  /// Devuelve -1 si el motor ya se liberó o la `.so` no expone la función.
  int _pathCall(String path, int? Function(Pointer<Utf8>) call) {
    if (_disposed) return -1;
    final utf8 = path.toNativeUtf8();
    try {
      return call(utf8) ?? -1;
    } finally {
      malloc.free(utf8);
    }
  }

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

  // ---------------------------------------------------------------------------
  // DSP / efectos avanzados
  // ---------------------------------------------------------------------------

  /// Sonido 8D: rotación estéreo. `speed` en Hz y `depth` 0..1.
  void set8d(bool enabled, {double speed = 1, double depth = 0.5}) =>
      _bindings.set8d?.call(_engine, enabled ? 1 : 0, speed, depth);

  ({double speed, double depth})? get8d() {
    final fn = _bindings.get8d;
    if (fn == null || _disposed) return null;
    final speed = calloc<Float>();
    final depth = calloc<Float>();
    try {
      if (fn(_engine, speed, depth) != 0) return null;
      return (speed: speed.value, depth: depth.value);
    } finally {
      calloc.free(speed);
      calloc.free(depth);
    }
  }

  /// HRTF: panoramización binaural. `angle` en grados.
  void setHrtf(bool enabled, {double angle = 0}) =>
      _bindings.setHrtf?.call(_engine, enabled ? 1 : 0, angle);

  double? getHrtf() {
    final fn = _bindings.getHrtf;
    if (fn == null || _disposed) return null;
    final angle = calloc<Float>();
    try {
      if (fn(_engine, angle) != 0) return null;
      return angle.value;
    } finally {
      calloc.free(angle);
    }
  }

  /// Reverb. `mix` 0..1.
  void setReverb(bool enabled, {double mix = 0.3}) =>
      _bindings.setReverb?.call(_engine, enabled ? 1 : 0, mix);

  double? getReverb() {
    final fn = _bindings.getReverb;
    if (fn == null || _disposed) return null;
    final mix = calloc<Float>();
    try {
      if (fn(_engine, mix) != 0) return null;
      return mix.value;
    } finally {
      calloc.free(mix);
    }
  }

  /// Compresor de rango dinámico.
  void setCompressor(
    bool enabled, {
    double thresholdDb = -18,
    double ratio = 4,
    double attackS = 0.01,
    double releaseS = 0.1,
  }) =>
      _bindings.setCompressor?.call(
          _engine, enabled ? 1 : 0, thresholdDb, ratio, attackS, releaseS);

  ({double thresholdDb, double ratio})? getCompressor() {
    final fn = _bindings.getCompressor;
    if (fn == null || _disposed) return null;
    final threshold = calloc<Float>();
    final ratio = calloc<Float>();
    try {
      if (fn(_engine, threshold, ratio) != 0) return null;
      return (thresholdDb: threshold.value, ratio: ratio.value);
    } finally {
      calloc.free(threshold);
      calloc.free(ratio);
    }
  }

  /// EQ paramétrico por banda (`band` 0-based). `type` = tipo de filtro,
  /// `freq` en Hz, `gainDb` en dB y `q` el factor Q.
  void setPeq(
    int band, {
    bool enabled = true,
    int type = 0,
    double freq = 1000,
    double gainDb = 0,
    double q = 1,
  }) =>
      _bindings.setPeq?.call(
          _engine, band, enabled ? 1 : 0, type, freq, gainDb, q);

  ({int type, double freq, double gainDb, double q})? getPeq(int band) {
    final fn = _bindings.getPeq;
    if (fn == null || _disposed) return null;
    final type = calloc<Int32>();
    final freq = calloc<Float>();
    final gain = calloc<Float>();
    final q = calloc<Float>();
    try {
      if (fn(_engine, band, type, freq, gain, q) != 0) return null;
      return (type: type.value, freq: freq.value, gainDb: gain.value, q: q.value);
    } finally {
      calloc.free(type);
      calloc.free(freq);
      calloc.free(gain);
      calloc.free(q);
    }
  }

  // ---------------------------------------------------------------------------
  // Cola avanzada
  // ---------------------------------------------------------------------------

  bool queueSort() => _bindings.queueSort?.call(_engine) == 0;

  bool queueReverse() => _bindings.queueReverse?.call(_engine) == 0;

  /// Reordena la cola al azar con una semilla reproducible.
  bool queueShuffle([int seed = 0]) =>
      _bindings.queueShuffle?.call(_engine, seed & 0xFFFFFFFF) == 0;

  bool queueSortTitle() => _bindings.queueSortTitle?.call(_engine) == 0;

  bool queueSortArtist() => _bindings.queueSortArtist?.call(_engine) == 0;

  bool queueSortAlbum() => _bindings.queueSortAlbum?.call(_engine) == 0;

  bool queueSortYear() => _bindings.queueSortYear?.call(_engine) == 0;

  bool queueSortTrack() => _bindings.queueSortTrack?.call(_engine) == 0;

  bool queueSortDuration() => _bindings.queueSortDuration?.call(_engine) == 0;

  bool queueSortAlbumArtist() =>
      _bindings.queueSortAlbumArtist?.call(_engine) == 0;

  bool queueSortGenre() => _bindings.queueSortGenre?.call(_engine) == 0;

  bool queueSortComposer() => _bindings.queueSortComposer?.call(_engine) == 0;

  bool queueSortFileSize() => _bindings.queueSortFilesize?.call(_engine) == 0;

  bool queueInsertSorted(String path) =>
      _pathCall(path, (ptr) => _bindings.queueInsertSorted?.call(_engine, ptr)) ==
      0;

  bool queueKeepCurrent() => _bindings.queueKeepCurrent?.call(_engine) == 0;

  bool queueDuplicateCurrent() =>
      _bindings.queueDuplicateCurrent?.call(_engine) == 0;

  bool queueRotate() => _bindings.queueRotate?.call(_engine) == 0;

  /// Nº de pistas de la cola cuya extensión coincide con `ext` (p. ej. ".flac").
  int queueCountExt(String ext) {
    final rc =
        _pathCall(ext, (ptr) => _bindings.queueCountExt?.call(_engine, ptr));
    return rc < 0 ? 0 : rc;
  }

  bool queuePrune() => _bindings.queuePrune?.call(_engine) == 0;

  bool queueDedup() => _bindings.queueDedup?.call(_engine) == 0;

  bool queueDedupHash() => _bindings.queueDedupHash?.call(_engine) == 0;

  bool queueFilterDir(String dir) =>
      _pathCall(dir, (ptr) => _bindings.queueFilterDir?.call(_engine, ptr)) ==
      0;

  bool queueExportJson(String path) =>
      _pathCall(path, (ptr) => _bindings.queueExportJson?.call(_engine, ptr)) ==
      0;

  /// Importa una cola desde JSON; devuelve el nº de pistas añadidas (-1 si falla).
  int queueImportJson(String path) =>
      _pathCall(path, (ptr) => _bindings.queueImportJson?.call(_engine, ptr));

  bool queueExportM3uExt(String path) =>
      _pathCall(
          path, (ptr) => _bindings.queueExportM3uExt?.call(_engine, ptr)) ==
      0;

  bool queueExportM3uRelative(String path) =>
      _pathCall(path,
          (ptr) => _bindings.queueExportM3uRelative?.call(_engine, ptr)) ==
      0;

  /// Exporta la cola a CSV (símbolo nativo `ch_engine_export_queue_csv`).
  bool exportQueueCsv(String path) =>
      _pathCall(path, (ptr) => _bindings.exportQueueCsv?.call(_engine, ptr)) ==
      0;

  // ---------------------------------------------------------------------------
  // Exportación y análisis offline
  // ---------------------------------------------------------------------------

  /// Exporta un fragmento de `srcPath` a WAV en `dstPath`.
  bool exportWav(
    String srcPath,
    String dstPath, {
    double startS = 0,
    double durationS = 0,
    int rate = 44100,
    int channels = 2,
  }) {
    final fn = _bindings.exportWav;
    if (fn == null || _disposed) return false;
    final src = srcPath.toNativeUtf8();
    final dst = dstPath.toNativeUtf8();
    try {
      return fn(_engine, src, dst, startS, durationS, rate, channels) == 0;
    } finally {
      malloc.free(src);
      malloc.free(dst);
    }
  }

  /// Concatena varios WAV en `dstPath`.
  bool concatWav(List<String> srcPaths, String dstPath, {int rate = 44100}) {
    final fn = _bindings.concatWav;
    if (fn == null || _disposed || srcPaths.isEmpty) return false;
    final count = srcPaths.length;
    final ptrs = calloc<Pointer<Utf8>>(count);
    var allocated = 0;
    final dst = dstPath.toNativeUtf8();
    try {
      for (var i = 0; i < count; i++) {
        ptrs[i] = srcPaths[i].toNativeUtf8();
        allocated++;
      }
      return fn(_engine, ptrs, count, dst, rate) == 0;
    } finally {
      for (var i = 0; i < allocated; i++) {
        malloc.free(ptrs[i]);
      }
      calloc.free(ptrs);
      malloc.free(dst);
    }
  }

  /// Parte `srcPath` en varios WAV usando `prefix` como base de nombre.
  /// Devuelve el nº de segmentos creados (-1 si falla).
  int splitBySilence(
    String srcPath,
    String prefix, {
    double thresholdDb = -60,
    double minS = 0.5,
    int rate = 44100,
  }) {
    final fn = _bindings.splitBySilence;
    if (fn == null || _disposed) return -1;
    final src = srcPath.toNativeUtf8();
    final pre = prefix.toNativeUtf8();
    try {
      return fn(_engine, src, pre, thresholdDb, minS, rate);
    } finally {
      malloc.free(src);
      malloc.free(pre);
    }
  }

  bool writeReplaygain(String path) =>
      _pathCall(path, (ptr) => _bindings.writeReplaygain?.call(_engine, ptr)) ==
      0;

  bool writeReplaygainDir(String dir) =>
      _pathCall(
          dir, (ptr) => _bindings.writeReplaygainDir?.call(_engine, ptr)) ==
      0;

  bool writeReplaygainQueue() =>
      _bindings.writeReplaygainQueue?.call(_engine) == 0;

  bool writeBpm(String path) =>
      _pathCall(path, (ptr) => _bindings.writeBpm?.call(_engine, ptr)) == 0;

  bool spectrogramPng(
    String srcPath,
    String outPath, {
    int width = 1200,
    int height = 600,
  }) {
    final fn = _bindings.spectrogramPng;
    if (fn == null || _disposed) return false;
    final src = srcPath.toNativeUtf8();
    final out = outPath.toNativeUtf8();
    try {
      return fn(_engine, src, out, width, height) == 0;
    } finally {
      malloc.free(src);
      malloc.free(out);
    }
  }

  /// Sonoridad integrada del conjunto de pistas cargadas (LUFS).
  double? albumLoudness() {
    final fn = _bindings.albumLoudness;
    if (fn == null || _disposed) return null;
    final out = calloc<Double>();
    try {
      if (fn(_engine, out) != 0) return null;
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  /// Normaliza el álbum a `targetLufs`; devuelve la ganancia aplicada en dB.
  double? normalizeAlbum(double targetLufs) {
    final fn = _bindings.normalizeAlbum;
    if (fn == null || _disposed) return null;
    final applied = calloc<Double>();
    try {
      if (fn(_engine, targetLufs, applied) != 0) return null;
      return applied.value;
    } finally {
      calloc.free(applied);
    }
  }

  /// Segmentos de silencio de `path` (inicio de cada uno, en segundos).
  List<double> countSilences(
    String path, {
    double thresholdDb = -60,
    double minS = 0.5,
    int maxSegments = 256,
  }) {
    final fn = _bindings.countSilences;
    if (fn == null || _disposed || maxSegments <= 0) return const [];
    final out = calloc<Double>(maxSegments);
    final utf8 = path.toNativeUtf8();
    try {
      final count = fn(_engine, utf8, thresholdDb, minS, out, maxSegments);
      if (count <= 0) return const [];
      final n = count > maxSegments ? maxSegments : count;
      return List<double>.generate(n, (i) => out[i]);
    } finally {
      malloc.free(utf8);
      calloc.free(out);
    }
  }

  /// Elimina los silencios de `srcPath` y escribe el resultado en `dstPath`.
  bool stripSilence(
    String srcPath,
    String dstPath, {
    double thresholdDb = -60,
    double minS = 0.5,
    double gapS = 0.1,
    int rate = 44100,
  }) {
    final fn = _bindings.stripSilence;
    if (fn == null || _disposed) return false;
    final src = srcPath.toNativeUtf8();
    final dst = dstPath.toNativeUtf8();
    try {
      return fn(_engine, src, dst, thresholdDb, minS, gapS, rate) == 0;
    } finally {
      malloc.free(src);
      malloc.free(dst);
    }
  }

  bool exportSpectrumCsv(String path, {int points = 1024}) {
    final fn = _bindings.exportSpectrumCsv;
    if (fn == null) return false;
    return _pathCall(path, (ptr) => fn(_engine, ptr, points)) == 0;
  }

  bool exportWaveformCsv(String path, {int buckets = 2000}) {
    final fn = _bindings.exportWaveformCsv;
    if (fn == null) return false;
    return _pathCall(path, (ptr) => fn(_engine, ptr, buckets)) == 0;
  }

  bool exportWaveformPng(
    String path, {
    int width = 1200,
    int height = 400,
  }) {
    final fn = _bindings.exportWaveformPng;
    if (fn == null) return false;
    return _pathCall(path, (ptr) => fn(_engine, ptr, width, height)) == 0;
  }

  bool exportSpectrumPng(
    String path, {
    int width = 1200,
    int height = 600,
    int bands = 512,
  }) {
    final fn = _bindings.exportSpectrumPng;
    if (fn == null) return false;
    return _pathCall(path, (ptr) => fn(_engine, ptr, width, height, bands)) == 0;
  }

  // ---------------------------------------------------------------------------
  // Favoritos
  // ---------------------------------------------------------------------------

  bool favoritesAdd(String path) =>
      _pathCall(path, (ptr) => _bindings.favoritesAdd?.call(_engine, ptr)) == 0;

  bool favoritesRemove(String path) =>
      _pathCall(path, (ptr) => _bindings.favoritesRemove?.call(_engine, ptr)) ==
      0;

  int get favoritesCount => _bindings.favoritesCount?.call(_engine) ?? 0;

  String favoritesPath(int index) =>
      _text(_bindings.favoritesPath?.call(_engine, index));

  bool favoritesSave(String path) =>
      _pathCall(path, (ptr) => _bindings.favoritesSave?.call(_engine, ptr)) ==
      0;

  bool favoritesLoad(String path) =>
      _pathCall(path, (ptr) => _bindings.favoritesLoad?.call(_engine, ptr)) ==
      0;

  bool favoritesExportM3u(String path) =>
      _pathCall(
          path, (ptr) => _bindings.favoritesExportM3u?.call(_engine, ptr)) ==
      0;

  // ---------------------------------------------------------------------------
  // Utilidades: etiquetas, carátulas, letras, tonalidad, etc.
  // ---------------------------------------------------------------------------

  /// Escribe una etiqueta genérica `key = value` en el archivo actual.
  bool setTag(String key, String value) {
    final fn = _bindings.setTagFn;
    if (fn == null || _disposed) return false;
    final k = key.toNativeUtf8();
    final v = value.toNativeUtf8();
    try {
      return fn(_engine, k, v) == 0;
    } finally {
      malloc.free(k);
      malloc.free(v);
    }
  }

  int get coverCountCurrent =>
      _bindings.coverCountCurrent?.call(_engine) ?? 0;

  bool saveCoverCurrent(int index, String path) =>
      _pathCall(path,
          (ptr) => _bindings.saveCoverCurrent?.call(_engine, index, ptr)) ==
      0;

  bool saveLyrics(String path) =>
      _pathCall(path, (ptr) => _bindings.saveLyrics?.call(_engine, ptr)) == 0;

  bool loadLyrics(String path) =>
      _pathCall(path, (ptr) => _bindings.loadLyrics?.call(_engine, ptr)) == 0;

  /// Desplaza la letra `deltaS` segundos (positivo = adelanta).
  bool shiftLyrics(double deltaS) =>
      _bindings.shiftLyrics?.call(_engine, deltaS) == 0;

  double get lyricsOffsetMs => _bindings.lyricsOffsetMs?.call(_engine) ?? 0;

  /// Detecta la tonalidad musical de `path`.
  ({String key, double confidence})? detectKey(String path) {
    final fn = _bindings.detectKey;
    if (fn == null || _disposed) return null;
    const size = 32;
    final out = calloc<Uint8>(size).cast<Utf8>();
    final confidence = calloc<Double>();
    final utf8 = path.toNativeUtf8();
    try {
      if (fn(_engine, utf8, out, size, confidence) != 0) return null;
      return (key: out.toDartString(), confidence: confidence.value);
    } finally {
      malloc.free(utf8);
      calloc.free(out);
      calloc.free(confidence);
    }
  }

  /// Tonalidad de la pista actual.
  ({String key, double confidence})? keyCurrent() {
    final fn = _bindings.keyCurrent;
    if (fn == null || _disposed) return null;
    const size = 32;
    final out = calloc<Uint8>(size).cast<Utf8>();
    final confidence = calloc<Double>();
    try {
      if (fn(_engine, out, size, confidence) != 0) return null;
      return (key: out.toDartString(), confidence: confidence.value);
    } finally {
      calloc.free(out);
      calloc.free(confidence);
    }
  }

  bool setAvoidRecent(bool enabled) =>
      _bindings.setAvoidRecent?.call(_engine, enabled ? 1 : 0) == 0;

  bool get avoidRecent => (_bindings.avoidRecent?.call(_engine) ?? 0) != 0;

  int get recentCount => _bindings.recentCount?.call(_engine) ?? 0;

  bool recentClear() => _bindings.recentClear?.call(_engine) == 0;

  bool setPauseAtDirEnd(bool enabled) =>
      _bindings.setPauseAtDirEnd?.call(_engine, enabled ? 1 : 0) == 0;

  bool get pauseAtDirEnd => (_bindings.pauseAtDirEnd?.call(_engine) ?? 0) != 0;

  /// Carga (o recarga) todos los archivos de un directorio en la cola.
  bool loadDir(String dir) =>
      _pathCall(dir, (ptr) => _bindings.loadDir?.call(_engine, ptr)) == 0;

  /// Ganancia automática por pista para alcanzar `targetLufs`.
  bool setAutoGain(bool enabled, {double targetLufs = -14}) =>
      _bindings.setAutoGain?.call(_engine, enabled ? 1 : 0, targetLufs) == 0;

  /// LUFS objetivo de la ganancia automática (null si no está disponible).
  double? autoGain() {
    final fn = _bindings.autoGain;
    if (fn == null || _disposed) return null;
    final out = calloc<Double>();
    try {
      if (fn(_engine, out) != 0) return null;
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  // ---------------------------------------------------------------------------
  // Biblioteca (handle persistente, liberado en dispose)
  // ---------------------------------------------------------------------------

  Pointer<Void>? _libraryHandle() {
    final create = _bindings.libraryCreate;
    if (create == null) return null;
    final existing = _library;
    if (existing != null && existing != nullptr) return existing;
    final handle = create();
    if (handle == nullptr) return null;
    return _library = handle;
  }

  /// Escanea `root` en la biblioteca interna y devuelve el nº de pistas.
  int libraryScanInto(String root) {
    final b = _bindings;
    final lib = _libraryHandle();
    if (lib == null || b.libraryScan == null) return -1;
    return _pathCall(root, (ptr) => b.libraryScan!(lib, ptr));
  }

  bool exportLibraryJson(String path) {
    final lib = _library;
    final fn = _bindings.libraryExportJson;
    if (lib == null || lib == nullptr || fn == null) return false;
    return _pathCall(path, (ptr) => fn(lib, ptr)) == 0;
  }

  bool exportLibraryCsv(String path) {
    final lib = _library;
    final fn = _bindings.libraryExportCsv;
    if (lib == null || lib == nullptr || fn == null) return false;
    return _pathCall(path, (ptr) => fn(lib, ptr)) == 0;
  }

  /// Quita `path` del índice de la biblioteca interna.
  bool libraryRemove(String path) {
    final lib = _library;
    final fn = _bindings.libraryRemove;
    if (lib == null || lib == nullptr || fn == null) return false;
    return _pathCall(path, (ptr) => fn(lib, ptr)) == 0;
  }

  // ---------------------------------------------------------------------------
  // Presets de EQ y utilidades de archivos
  // ---------------------------------------------------------------------------

  int get eqPresetCount => _bindings.eqPresetCount?.call() ?? 0;

  String eqPresetName(int index) {
    final fn = _bindings.eqPresetName;
    if (fn == null) return '';
    const size = 256;
    final out = calloc<Uint8>(size).cast<Utf8>();
    try {
      if (fn(index, out, size) <= 0) return '';
      return out.toDartString();
    } finally {
      calloc.free(out);
    }
  }

  /// Índice del preset con nombre `name`, o -1 si no existe.
  int eqPresetFind(String name) {
    final fn = _bindings.eqPresetFind;
    if (fn == null) return -1;
    final utf8 = name.toNativeUtf8();
    try {
      return fn(utf8);
    } finally {
      malloc.free(utf8);
    }
  }

  bool applyEqPreset(int index) =>
      _bindings.applyEqPreset?.call(_engine, index) == 0;

  bool saveEqPreset(String path) =>
      _pathCall(path, (ptr) => _bindings.saveEqPreset?.call(_engine, ptr)) ==
      0;

  bool loadEqPreset(String path) =>
      _pathCall(path, (ptr) => _bindings.loadEqPreset?.call(_engine, ptr)) ==
      0;

  bool copyTags(String srcPath, String dstPath) {
    final fn = _bindings.copyTags;
    if (fn == null) return false;
    final src = srcPath.toNativeUtf8();
    final dst = dstPath.toNativeUtf8();
    try {
      return fn(src, dst) == 0;
    } finally {
      malloc.free(src);
      malloc.free(dst);
    }
  }

  // ---------------------------------------------------------------------------
  // BPM y rango dinámico (DR)
  // ---------------------------------------------------------------------------

  /// BPM de un archivo (null si no se pudo medir).
  double? bpmDetectPath(String path) {
    final fn = _bindings.bpmDetectPath;
    if (fn == null) return null;
    final utf8 = path.toNativeUtf8();
    try {
      final value = fn(utf8);
      return value > 0 ? value : null;
    } finally {
      malloc.free(utf8);
    }
  }

  double get bpm => _bindings.bpmFn?.call(_engine) ?? 0;

  /// DR de un archivo: valor y nº de bloques (null si no se pudo medir).
  ({double value, int blocks})? drMeasurePath(String path) {
    final fn = _bindings.drMeasurePath;
    if (fn == null) return null;
    final blocks = calloc<Uint32>();
    final utf8 = path.toNativeUtf8();
    try {
      final value = fn(utf8, blocks);
      if (value <= 0) return null;
      return (value: value, blocks: blocks.value);
    } finally {
      malloc.free(utf8);
      calloc.free(blocks);
    }
  }

  /// DR de la pista actual.
  ({double value, int blocks})? dr() {
    final fn = _bindings.drFn;
    if (fn == null || _disposed) return null;
    final blocks = calloc<Uint32>();
    try {
      final value = fn(_engine, blocks);
      if (value <= 0) return null;
      return (value: value, blocks: blocks.value);
    } finally {
      calloc.free(blocks);
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
    final library = _library;
    if (library != null && library != nullptr) {
      _bindings.libraryDestroy?.call(library);
      _library = null;
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
        setChannelMode = lib.providesSymbol('ch_engine_set_channel_mode')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_channel_mode')
            : null,
        channelMode = lib.providesSymbol('ch_engine_channel_mode')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_channel_mode')
            : null,
        playIndex = lib.providesSymbol('ch_engine_play_index')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_play_index')
            : null,
        loadAdd = lib.providesSymbol('ch_engine_load_add')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_load_add')
            : null,
        queueAdd = lib.providesSymbol('ch_engine_queue_add')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_queue_add')
            : null,
        queueInsert = lib.providesSymbol('ch_engine_queue_insert')
            ? lib.lookupFunction<_InsertNative, _InsertDart>('ch_engine_queue_insert')
            : null,
        queueMove = lib.providesSymbol('ch_engine_queue_move')
            ? lib.lookupFunction<_MoveNative, _MoveDart>('ch_engine_queue_move')
            : null,
        queueRemove = lib.providesSymbol('ch_engine_queue_remove')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_queue_remove')
            : null,
        queueClear = lib.providesSymbol('ch_engine_queue_clear')
            ? lib.lookupFunction<_ControlNative, _ControlDart>('ch_engine_queue_clear')
            : null,
        queueImport = lib.providesSymbol('ch_engine_queue_import')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_queue_import')
            : null,
        queueExport = lib.providesSymbol('ch_engine_queue_export')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_queue_export')
            : null,
        queueItem = lib.providesSymbol('ch_engine_queue_item')
            ? lib.lookupFunction<_TextAtNative, _TextAtDart>('ch_engine_queue_item')
            : null,
        volume = lib.providesSymbol('ch_engine_volume')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_volume')
            : null,
        queueCount = lib.providesSymbol('ch_engine_queue_count')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_queue_count')
            : null,
        queueIndex = lib.providesSymbol('ch_engine_queue_index')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_queue_index')
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
        setShuffleSeed = lib.providesSymbol('ch_engine_set_shuffle_seed')
            ? lib.lookupFunction<_SeedNative, _SeedDart>('ch_engine_set_shuffle_seed')
            : null,
        setGapless = lib.providesSymbol('ch_engine_set_gapless')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_gapless')
            : null,
        gapless = lib.providesSymbol('ch_engine_gapless')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_gapless')
            : null,
        setCrossfade = lib.providesSymbol('ch_engine_set_crossfade')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_crossfade')
            : null,
        crossfade = lib.providesSymbol('ch_engine_crossfade')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_crossfade')
            : null,
        setSpeed = lib.providesSymbol('ch_engine_set_speed')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_speed')
            : null,
        speed = lib.providesSymbol('ch_engine_speed')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_speed')
            : null,
        setPitch = lib.providesSymbol('ch_engine_set_pitch')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_pitch')
            : null,
        pitch = lib.providesSymbol('ch_engine_pitch')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_pitch')
            : null,
        setSleepTimer = lib.providesSymbol('ch_engine_set_sleep_timer')
            ? lib.lookupFunction<_SetLoopNative, _SetLoopDart>('ch_engine_set_sleep_timer')
            : null,
        sleepRemaining = lib.providesSymbol('ch_engine_sleep_remaining')
            ? lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_sleep_remaining')
            : null,
        saveState = lib.providesSymbol('ch_engine_save_state')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_save_state')
            : null,
        loadState = lib.providesSymbol('ch_engine_load_state')
            ? lib.lookupFunction<_LoadStateNative, _LoadStateDart>('ch_engine_load_state')
            : null,
        libraryCreate = lib.providesSymbol('ch_library_create')
            ? lib.lookupFunction<_CreateNative, _CreateDart>('ch_library_create')
            : null,
        libraryDestroy = lib.providesSymbol('ch_library_destroy')
            ? lib.lookupFunction<_DestroyNative, _DestroyDart>('ch_library_destroy')
            : null,
        libraryScan = lib.providesSymbol('ch_library_scan')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_library_scan')
            : null,
        libraryCount = lib.providesSymbol('ch_library_count')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_library_count')
            : null,
        libraryPath = lib.providesSymbol('ch_library_path')
            ? lib.lookupFunction<_TextAtNative, _TextAtDart>('ch_library_path')
            : null,
        libraryRemoved = lib.providesSymbol('ch_library_removed')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_library_removed')
            : null,
        markersCreate = lib.providesSymbol('ch_markers_create')
            ? lib.lookupFunction<_CreateNative, _CreateDart>('ch_markers_create')
            : null,
        markersDestroy = lib.providesSymbol('ch_markers_destroy')
            ? lib.lookupFunction<_DestroyNative, _DestroyDart>('ch_markers_destroy')
            : null,
        markersLoad = lib.providesSymbol('ch_markers_load')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_markers_load')
            : null,
        markersSave = lib.providesSymbol('ch_markers_save')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_markers_save')
            : null,
        markersAdd = lib.providesSymbol('ch_markers_add')
            ? lib.lookupFunction<_MarkerAddNative, _MarkerAddDart>('ch_markers_add')
            : null,
        markersCount = lib.providesSymbol('ch_markers_count')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_markers_count')
            : null,
        markersPosition = lib.providesSymbol('ch_markers_position')
            ? lib.lookupFunction<_MarkerPosNative, _MarkerPosDart>('ch_markers_position')
            : null,
        markersName = lib.providesSymbol('ch_markers_name')
            ? lib.lookupFunction<_MarkerNameNative, _MarkerNameDart>('ch_markers_name')
            : null,
        markersRemove = lib.providesSymbol('ch_markers_remove')
            ? lib.lookupFunction<_MarkerRemoveNative, _MarkerRemoveDart>('ch_markers_remove')
            : null,
        markersClear = lib.providesSymbol('ch_markers_clear')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_markers_clear')
            : null,
        cueRead = lib.providesSymbol('ch_cue_read')
            ? lib.lookupFunction<_CueReadNative, _CueReadDart>('ch_cue_read')
            : null,
        cueFree = lib.providesSymbol('ch_cue_free')
            ? lib.lookupFunction<_DestroyNative, _DestroyDart>('ch_cue_free')
            : null,
        cueCount = lib.providesSymbol('ch_cue_count')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_cue_count')
            : null,
        cueAlbum = lib.providesSymbol('ch_cue_album')
            ? lib.lookupFunction<_TextNative, _TextDart>('ch_cue_album')
            : null,
        cueAlbumPerformer = lib.providesSymbol('ch_cue_album_performer')
            ? lib.lookupFunction<_TextNative, _TextDart>('ch_cue_album_performer')
            : null,
        cueFile = lib.providesSymbol('ch_cue_file')
            ? lib.lookupFunction<_TextAtNative, _TextAtDart>('ch_cue_file')
            : null,
        cueTitle = lib.providesSymbol('ch_cue_title')
            ? lib.lookupFunction<_TextAtNative, _TextAtDart>('ch_cue_title')
            : null,
        cuePerformer = lib.providesSymbol('ch_cue_performer')
            ? lib.lookupFunction<_TextAtNative, _TextAtDart>('ch_cue_performer')
            : null,
        cueStart = lib.providesSymbol('ch_cue_start')
            ? lib.lookupFunction<_DoubleAtNative, _DoubleAtDart>('ch_cue_start')
            : null,
        cueEnd = lib.providesSymbol('ch_cue_end')
            ? lib.lookupFunction<_DoubleAtNative, _DoubleAtDart>('ch_cue_end')
            : null,
        cueNumber = lib.providesSymbol('ch_cue_number')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_cue_number')
            : null,
        outputDeviceCount = lib.providesSymbol('ch_engine_output_device_count')
            ? lib.lookupFunction<_NoArgIntNative, _NoArgIntDart>('ch_engine_output_device_count')
            : null,
        outputDeviceName = lib.providesSymbol('ch_engine_output_device_name')
            ? lib.lookupFunction<_TextIndexNative, _TextIndexDart>('ch_engine_output_device_name')
            : null,
        outputDevice = lib.providesSymbol('ch_engine_output_device')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_output_device')
            : null,
        setOutputDevice = lib.providesSymbol('ch_engine_set_output_device')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_output_device')
            : null,
        loudnessScan = lib.providesSymbol('ch_loudness_scan')
            ? lib.lookupFunction<_LoudnessNative, _LoudnessDart>('ch_loudness_scan')
            : null,
        waveformPeaks = lib.providesSymbol('ch_waveform_peaks')
            ? lib.lookupFunction<_WaveformNative, _WaveformDart>('ch_waveform_peaks')
            : null,
        coreVersion = lib.providesSymbol('ch_core_version')
            ? lib.lookupFunction<_PlainTextNative, _PlainTextDart>('ch_core_version')
            : null,
        meter = lib.providesSymbol('ch_engine_meter')
            ? lib.lookupFunction<_MeterNative, _MeterDart>('ch_engine_meter')
            : null,
        spectrum = lib.providesSymbol('ch_engine_spectrum')
            ? lib.lookupFunction<_LevelsNative, _LevelsDart>('ch_engine_spectrum')
            : null,
        setBandGain = lib.providesSymbol('ch_engine_set_band_gain')
            ? lib.lookupFunction<_IntFloatNative, _IntFloatDart>('ch_engine_set_band_gain')
            : null,
        setLimiter = lib.providesSymbol('ch_engine_set_limiter')
            ? lib.lookupFunction<_IntFloatNative, _IntFloatDart>('ch_engine_set_limiter')
            : null,
        limiter = lib.providesSymbol('ch_engine_limiter')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_limiter')
            : null,
        setCrossfeed = lib.providesSymbol('ch_engine_set_crossfeed')
            ? lib.lookupFunction<_IntFloatNative, _IntFloatDart>('ch_engine_set_crossfeed')
            : null,
        crossfeed = lib.providesSymbol('ch_engine_crossfeed')
            ? lib.lookupFunction<_FloatOutNative, _FloatOutDart>('ch_engine_crossfeed')
            : null,
        setGainDb = lib.providesSymbol('ch_engine_set_gain_db')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_gain_db')
            : null,
        gainDb = lib.providesSymbol('ch_engine_gain_db')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_gain_db')
            : null,
        setStereoWidth = lib.providesSymbol('ch_engine_set_stereo_width')
            ? lib.lookupFunction<_SetFloatNative, _SetFloatDart>('ch_engine_set_stereo_width')
            : null,
        stereoWidth = lib.providesSymbol('ch_engine_stereo_width')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_stereo_width')
            : null,
        setTrimSilence = lib.providesSymbol('ch_engine_set_trim_silence')
            ? lib.lookupFunction<_IntFloatNative, _IntFloatDart>('ch_engine_set_trim_silence')
            : null,
        trimSilence = lib.providesSymbol('ch_engine_trim_silence')
            ? lib.lookupFunction<_FloatOutNative, _FloatOutDart>('ch_engine_trim_silence')
            : null,
        setReplayGain = lib.providesSymbol('ch_engine_set_replaygain')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_replaygain')
            : null,
        replayGainGainDb = lib.providesSymbol('ch_engine_replaygain_gain_db')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_replaygain_gain_db')
            : null,
        replayGainPeak = lib.providesSymbol('ch_engine_replaygain_peak')
            ? lib.lookupFunction<_GetFloatNative, _GetFloatDart>('ch_engine_replaygain_peak')
            : null,
        setMono = lib.providesSymbol('ch_engine_set_mono')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>('ch_engine_set_mono')
            : null,
        mono = lib.providesSymbol('ch_engine_mono')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_mono')
            : null,
        setAbLoop = lib.providesSymbol('ch_engine_set_ab_loop')
            ? lib.lookupFunction<_SetLoopNative, _SetLoopDart>('ch_engine_set_ab_loop')
            : null,
        clearAbLoop = lib.providesSymbol('ch_engine_clear_ab_loop')
            ? lib.lookupFunction<_ControlNative, _ControlDart>('ch_engine_clear_ab_loop')
            : null,
        abLoop = lib.providesSymbol('ch_engine_ab_loop')
            ? lib.lookupFunction<_TwoDoubleOutNative, _TwoDoubleOutDart>('ch_engine_ab_loop')
            : null,
        analyzeCurrent = lib.providesSymbol('ch_engine_analyze_current')
            ? lib.lookupFunction<_TwoDoubleOutNative, _TwoDoubleOutDart>('ch_engine_analyze_current')
            : null,
        normalizeCurrent = lib.providesSymbol('ch_engine_normalize_current')
            ? lib.lookupFunction<_NormalizeNative, _NormalizeDart>('ch_engine_normalize_current')
            : null,
        bufferedSeconds = lib.providesSymbol('ch_engine_buffered_seconds')
            ? lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_buffered_seconds')
            : null,
        bufferUnderflows = lib.providesSymbol('ch_engine_buffer_underflows')
            ? lib.lookupFunction<_U64Native, _U64Dart>('ch_engine_buffer_underflows')
            : null,
        detectSilence = lib.providesSymbol('ch_engine_detect_silence')
            ? lib.lookupFunction<_DetectSilenceNative, _DetectSilenceDart>('ch_engine_detect_silence')
            : null,
        tag = lib.providesSymbol('ch_engine_tag')
            ? lib.lookupFunction<_TagNative, _TagDart>('ch_engine_tag')
            : null,
        dateFn = lib.providesSymbol('ch_engine_date')
            ? lib.lookupFunction<_TextNative, _TextDart>('ch_engine_date')
            : null,
        genreFn = lib.providesSymbol('ch_engine_genre')
            ? lib.lookupFunction<_TextNative, _TextDart>('ch_engine_genre')
            : null,
        composerFn = lib.providesSymbol('ch_engine_composer')
            ? lib.lookupFunction<_TextNative, _TextDart>('ch_engine_composer')
            : null,
        trackNumber = lib.providesSymbol('ch_engine_track_number')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_track_number')
            : null,
        discNumber = lib.providesSymbol('ch_engine_disc_number')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_disc_number')
            : null,
        saveCover = lib.providesSymbol('ch_engine_save_cover')
            ? lib.lookupFunction<_InsertNative, _InsertDart>('ch_engine_save_cover')
            : null,
        sampleRate = lib.providesSymbol('ch_engine_sample_rate')
            ? lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_sample_rate')
            : null,
        channels = lib.providesSymbol('ch_engine_channels')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_channels')
            : null,
        lyricsCount = lib.providesSymbol('ch_engine_lyrics_count')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_lyrics_count')
            : null,
        lyricLine = lib.providesSymbol('ch_engine_lyric_line')
            ? lib.lookupFunction<_LyricLineNative, _LyricLineDart>('ch_engine_lyric_line')
            : null,
        titleFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_title'),
        artistFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_artist'),
        albumFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_album'),
        coverCount = lib.lookupFunction<_IntNative, _IntDart>('ch_engine_cover_count'),
        coverAt =
            lib.lookupFunction<_CoverAtNative, _CoverAtDart>('ch_engine_cover_at'),
        engineLastErrorFn = lib.lookupFunction<_TextNative, _TextDart>('ch_engine_last_error'),
        set8d = lib.providesSymbol('ch_engine_set_8d')
            ? lib.lookupFunction<_Set8dNative, _Set8dDart>('ch_engine_set_8d')
            : null,
        get8d = lib.providesSymbol('ch_engine_8d')
            ? lib.lookupFunction<_EightDNative, _EightDDart>('ch_engine_8d')
            : null,
        setHrtf = lib.providesSymbol('ch_engine_set_hrtf')
            ? lib.lookupFunction<_SetHrtfNative, _SetHrtfDart>('ch_engine_set_hrtf')
            : null,
        getHrtf = lib.providesSymbol('ch_engine_hrtf')
            ? lib.lookupFunction<_HrtfNative, _HrtfDart>('ch_engine_hrtf')
            : null,
        setReverb = lib.providesSymbol('ch_engine_set_reverb')
            ? lib.lookupFunction<_SetReverbNative, _SetReverbDart>(
                'ch_engine_set_reverb')
            : null,
        getReverb = lib.providesSymbol('ch_engine_reverb')
            ? lib.lookupFunction<_ReverbNative, _ReverbDart>('ch_engine_reverb')
            : null,
        setCompressor = lib.providesSymbol('ch_engine_set_compressor')
            ? lib.lookupFunction<_SetCompressorNative, _SetCompressorDart>(
                'ch_engine_set_compressor')
            : null,
        getCompressor = lib.providesSymbol('ch_engine_compressor')
            ? lib.lookupFunction<_CompressorNative, _CompressorDart>(
                'ch_engine_compressor')
            : null,
        setPeq = lib.providesSymbol('ch_engine_set_peq')
            ? lib.lookupFunction<_SetPeqNative, _SetPeqDart>('ch_engine_set_peq')
            : null,
        getPeq = lib.providesSymbol('ch_engine_peq')
            ? lib.lookupFunction<_PeqNative, _PeqDart>('ch_engine_peq')
            : null,
        queueSort = lib.providesSymbol('ch_engine_queue_sort')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort')
            : null,
        queueReverse = lib.providesSymbol('ch_engine_queue_reverse')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_reverse')
            : null,
        queueShuffle = lib.providesSymbol('ch_engine_queue_shuffle')
            ? lib.lookupFunction<_SeedNative, _SeedDart>('ch_engine_queue_shuffle')
            : null,
        queueSortTitle = lib.providesSymbol('ch_engine_queue_sort_title')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort_title')
            : null,
        queueSortArtist = lib.providesSymbol('ch_engine_queue_sort_artist')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort_artist')
            : null,
        queueSortAlbum = lib.providesSymbol('ch_engine_queue_sort_album')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort_album')
            : null,
        queueSortYear = lib.providesSymbol('ch_engine_queue_sort_year')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort_year')
            : null,
        queueSortTrack = lib.providesSymbol('ch_engine_queue_sort_track')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort_track')
            : null,
        queueSortDuration = lib.providesSymbol('ch_engine_queue_sort_duration')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort_duration')
            : null,
        queueSortAlbumArtist =
            lib.providesSymbol('ch_engine_queue_sort_albumartist')
                ? lib.lookupFunction<_ControlNative, _ControlDart>(
                    'ch_engine_queue_sort_albumartist')
                : null,
        queueSortGenre = lib.providesSymbol('ch_engine_queue_sort_genre')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort_genre')
            : null,
        queueSortComposer = lib.providesSymbol('ch_engine_queue_sort_composer')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort_composer')
            : null,
        queueSortFilesize = lib.providesSymbol('ch_engine_queue_sort_filesize')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_sort_filesize')
            : null,
        queueInsertSorted = lib.providesSymbol('ch_engine_queue_insert_sorted')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_queue_insert_sorted')
            : null,
        queueKeepCurrent = lib.providesSymbol('ch_engine_queue_keep_current')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_keep_current')
            : null,
        queueDuplicateCurrent =
            lib.providesSymbol('ch_engine_queue_duplicate_current')
                ? lib.lookupFunction<_ControlNative, _ControlDart>(
                    'ch_engine_queue_duplicate_current')
                : null,
        queueRotate = lib.providesSymbol('ch_engine_queue_rotate')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_rotate')
            : null,
        queueCountExt = lib.providesSymbol('ch_engine_queue_count_ext')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_queue_count_ext')
            : null,
        queuePrune = lib.providesSymbol('ch_engine_queue_prune')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_prune')
            : null,
        queueDedup = lib.providesSymbol('ch_engine_queue_dedup')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_dedup')
            : null,
        queueDedupHash = lib.providesSymbol('ch_engine_queue_dedup_hash')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_queue_dedup_hash')
            : null,
        queueFilterDir = lib.providesSymbol('ch_engine_queue_filter_dir')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_queue_filter_dir')
            : null,
        queueExportJson = lib.providesSymbol('ch_engine_queue_export_json')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_queue_export_json')
            : null,
        queueImportJson = lib.providesSymbol('ch_engine_queue_import_json')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_queue_import_json')
            : null,
        queueExportM3uExt =
            lib.providesSymbol('ch_engine_queue_export_m3u_ext')
                ? lib.lookupFunction<_LoadNative, _LoadDart>(
                    'ch_engine_queue_export_m3u_ext')
                : null,
        queueExportM3uRelative =
            lib.providesSymbol('ch_engine_queue_export_m3u_relative')
                ? lib.lookupFunction<_LoadNative, _LoadDart>(
                    'ch_engine_queue_export_m3u_relative')
                : null,
        exportQueueCsv = lib.providesSymbol('ch_engine_export_queue_csv')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_export_queue_csv')
            : null,
        exportWav = lib.providesSymbol('ch_engine_export_wav')
            ? lib.lookupFunction<_ExportWavNative, _ExportWavDart>(
                'ch_engine_export_wav')
            : null,
        concatWav = lib.providesSymbol('ch_engine_concat_wav')
            ? lib.lookupFunction<_ConcatWavNative, _ConcatWavDart>(
                'ch_engine_concat_wav')
            : null,
        splitBySilence = lib.providesSymbol('ch_engine_split_by_silence')
            ? lib.lookupFunction<_SplitSilenceNative, _SplitSilenceDart>(
                'ch_engine_split_by_silence')
            : null,
        writeReplaygain = lib.providesSymbol('ch_engine_write_replaygain')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_write_replaygain')
            : null,
        writeReplaygainDir =
            lib.providesSymbol('ch_engine_write_replaygain_dir')
                ? lib.lookupFunction<_LoadNative, _LoadDart>(
                    'ch_engine_write_replaygain_dir')
                : null,
        writeReplaygainQueue =
            lib.providesSymbol('ch_engine_write_replaygain_queue')
                ? lib.lookupFunction<_ControlNative, _ControlDart>(
                    'ch_engine_write_replaygain_queue')
                : null,
        writeBpm = lib.providesSymbol('ch_engine_write_bpm')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_write_bpm')
            : null,
        spectrogramPng = lib.providesSymbol('ch_engine_spectrogram_png')
            ? lib.lookupFunction<_SpectrogramPngNative, _SpectrogramPngDart>(
                'ch_engine_spectrogram_png')
            : null,
        albumLoudness = lib.providesSymbol('ch_engine_album_loudness')
            ? lib.lookupFunction<_DoubleOutNative, _DoubleOutDart>(
                'ch_engine_album_loudness')
            : null,
        normalizeAlbum = lib.providesSymbol('ch_engine_normalize_album')
            ? lib.lookupFunction<_NormalizeNative, _NormalizeDart>(
                'ch_engine_normalize_album')
            : null,
        countSilences = lib.providesSymbol('ch_engine_count_silences')
            ? lib.lookupFunction<_CountSilencesNative, _CountSilencesDart>(
                'ch_engine_count_silences')
            : null,
        stripSilence = lib.providesSymbol('ch_engine_strip_silence')
            ? lib.lookupFunction<_StripSilenceNative, _StripSilenceDart>(
                'ch_engine_strip_silence')
            : null,
        exportSpectrumCsv =
            lib.providesSymbol('ch_engine_export_spectrum_csv')
                ? lib.lookupFunction<_ExportIntNative, _ExportIntDart>(
                    'ch_engine_export_spectrum_csv')
                : null,
        exportWaveformCsv =
            lib.providesSymbol('ch_engine_export_waveform_csv')
                ? lib.lookupFunction<_ExportIntNative, _ExportIntDart>(
                    'ch_engine_export_waveform_csv')
                : null,
        exportWaveformPng =
            lib.providesSymbol('ch_engine_export_waveform_png')
                ? lib.lookupFunction<_ExportPngNative, _ExportPngDart>(
                    'ch_engine_export_waveform_png')
                : null,
        exportSpectrumPng =
            lib.providesSymbol('ch_engine_export_spectrum_png')
                ? lib.lookupFunction<_ExportSpectrumPngNative,
                        _ExportSpectrumPngDart>(
                    'ch_engine_export_spectrum_png')
                : null,
        favoritesAdd = lib.providesSymbol('ch_engine_favorites_add')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_favorites_add')
            : null,
        favoritesRemove = lib.providesSymbol('ch_engine_favorites_remove')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_favorites_remove')
            : null,
        favoritesCount = lib.providesSymbol('ch_engine_favorites_count')
            ? lib.lookupFunction<_IntNative, _IntDart>(
                'ch_engine_favorites_count')
            : null,
        favoritesPath = lib.providesSymbol('ch_engine_favorites_path')
            ? lib.lookupFunction<_TextAtNative, _TextAtDart>(
                'ch_engine_favorites_path')
            : null,
        favoritesSave = lib.providesSymbol('ch_engine_favorites_save')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_favorites_save')
            : null,
        favoritesLoad = lib.providesSymbol('ch_engine_favorites_load')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_favorites_load')
            : null,
        favoritesExportM3u =
            lib.providesSymbol('ch_engine_favorites_export_m3u')
                ? lib.lookupFunction<_LoadNative, _LoadDart>(
                    'ch_engine_favorites_export_m3u')
                : null,
        setTagFn = lib.providesSymbol('ch_engine_set_tag')
            ? lib.lookupFunction<_SetTagNative, _SetTagDart>('ch_engine_set_tag')
            : null,
        coverCountCurrent =
            lib.providesSymbol('ch_engine_cover_count_current')
                ? lib.lookupFunction<_IntNative, _IntDart>(
                    'ch_engine_cover_count_current')
                : null,
        saveCoverCurrent =
            lib.providesSymbol('ch_engine_save_cover_current')
                ? lib.lookupFunction<_InsertNative, _InsertDart>(
                    'ch_engine_save_cover_current')
                : null,
        saveLyrics = lib.providesSymbol('ch_engine_save_lyrics')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_save_lyrics')
            : null,
        loadLyrics = lib.providesSymbol('ch_engine_load_lyrics')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_load_lyrics')
            : null,
        shiftLyrics = lib.providesSymbol('ch_engine_shift_lyrics')
            ? lib.lookupFunction<_SetDoubleNative, _SetDoubleDart>(
                'ch_engine_shift_lyrics')
            : null,
        lyricsOffsetMs = lib.providesSymbol('ch_engine_lyrics_offset_ms')
            ? lib.lookupFunction<_DoubleNative, _DoubleDart>(
                'ch_engine_lyrics_offset_ms')
            : null,
        detectKey = lib.providesSymbol('ch_engine_detect_key')
            ? lib.lookupFunction<_DetectKeyNative, _DetectKeyDart>(
                'ch_engine_detect_key')
            : null,
        keyCurrent = lib.providesSymbol('ch_engine_key_current')
            ? lib.lookupFunction<_KeyCurrentNative, _KeyCurrentDart>(
                'ch_engine_key_current')
            : null,
        setAvoidRecent = lib.providesSymbol('ch_engine_set_avoid_recent')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>(
                'ch_engine_set_avoid_recent')
            : null,
        avoidRecent = lib.providesSymbol('ch_engine_avoid_recent')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_avoid_recent')
            : null,
        recentCount = lib.providesSymbol('ch_engine_recent_count')
            ? lib.lookupFunction<_IntNative, _IntDart>('ch_engine_recent_count')
            : null,
        recentClear = lib.providesSymbol('ch_engine_recent_clear')
            ? lib.lookupFunction<_ControlNative, _ControlDart>(
                'ch_engine_recent_clear')
            : null,
        setPauseAtDirEnd = lib.providesSymbol('ch_engine_set_pause_at_dir_end')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>(
                'ch_engine_set_pause_at_dir_end')
            : null,
        pauseAtDirEnd = lib.providesSymbol('ch_engine_pause_at_dir_end')
            ? lib.lookupFunction<_IntNative, _IntDart>(
                'ch_engine_pause_at_dir_end')
            : null,
        loadDir = lib.providesSymbol('ch_engine_load_dir')
            ? lib.lookupFunction<_LoadNative, _LoadDart>('ch_engine_load_dir')
            : null,
        setAutoGain = lib.providesSymbol('ch_engine_set_auto_gain')
            ? lib.lookupFunction<_SetAutoGainNative, _SetAutoGainDart>(
                'ch_engine_set_auto_gain')
            : null,
        autoGain = lib.providesSymbol('ch_engine_auto_gain')
            ? lib.lookupFunction<_DoubleOutNative, _DoubleOutDart>(
                'ch_engine_auto_gain')
            : null,
        libraryExportJson = lib.providesSymbol('ch_library_export_json')
            ? lib.lookupFunction<_LibraryExportNative, _LibraryExportDart>(
                'ch_library_export_json')
            : null,
        libraryExportCsv = lib.providesSymbol('ch_library_export_csv')
            ? lib.lookupFunction<_LibraryExportNative, _LibraryExportDart>(
                'ch_library_export_csv')
            : null,
        libraryRemove = lib.providesSymbol('ch_library_remove')
            ? lib.lookupFunction<_LibraryRemoveNative, _LibraryRemoveDart>(
                'ch_library_remove')
            : null,
        eqPresetCount = lib.providesSymbol('ch_engine_eq_preset_count')
            ? lib.lookupFunction<_NoArgIntNative, _NoArgIntDart>(
                'ch_engine_eq_preset_count')
            : null,
        eqPresetName = lib.providesSymbol('ch_engine_eq_preset_name')
            ? lib.lookupFunction<_EqPresetNameNative, _EqPresetNameDart>(
                'ch_engine_eq_preset_name')
            : null,
        eqPresetFind = lib.providesSymbol('ch_engine_eq_preset_find')
            ? lib.lookupFunction<_EqPresetFindNative, _EqPresetFindDart>(
                'ch_engine_eq_preset_find')
            : null,
        applyEqPreset = lib.providesSymbol('ch_engine_apply_eq_preset')
            ? lib.lookupFunction<_SetIntNative, _SetIntDart>(
                'ch_engine_apply_eq_preset')
            : null,
        saveEqPreset = lib.providesSymbol('ch_engine_save_eq_preset')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_save_eq_preset')
            : null,
        loadEqPreset = lib.providesSymbol('ch_engine_load_eq_preset')
            ? lib.lookupFunction<_LoadNative, _LoadDart>(
                'ch_engine_load_eq_preset')
            : null,
        copyTags = lib.providesSymbol('ch_engine_copy_tags')
            ? lib.lookupFunction<_CopyTagsNative, _CopyTagsDart>(
                'ch_engine_copy_tags')
            : null,
        bpmDetectPath = lib.providesSymbol('ch_bpm_detect_path')
            ? lib.lookupFunction<_BpmDetectNative, _BpmDetectDart>(
                'ch_bpm_detect_path')
            : null,
        bpmFn = lib.providesSymbol('ch_engine_bpm')
            ? lib.lookupFunction<_DoubleNative, _DoubleDart>('ch_engine_bpm')
            : null,
        drMeasurePath = lib.providesSymbol('ch_dr_measure_path')
            ? lib.lookupFunction<_DrMeasureNative, _DrMeasureDart>(
                'ch_dr_measure_path')
            : null,
        drFn = lib.providesSymbol('ch_engine_dr')
            ? lib.lookupFunction<_EngineDrNative, _EngineDrDart>('ch_engine_dr')
            : null,
        coreLastErrorFn = lib.lookupFunction<_PlainTextNative, _PlainTextDart>('ch_core_last_error'),
        resultStr = lib.providesSymbol('ch_result_str')
            ? lib.lookupFunction<_ResultStrNative, _ResultStrDart>('ch_result_str')
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
  final _SetIntDart? setChannelMode;
  final _IntDart? channelMode;
  final _SetIntDart? playIndex;
  final _LoadDart? loadAdd;
  final _LoadDart? queueAdd;
  final _InsertDart? queueInsert;
  final _MoveDart? queueMove;
  final _SetIntDart? queueRemove;
  final _ControlDart? queueClear;
  final _LoadDart? queueImport;
  final _LoadDart? queueExport;
  final _TextAtDart? queueItem;
  final _GetFloatDart? volume;
  final _IntDart? queueCount;
  final _IntDart? queueIndex;
  final _SetIntDart? setRepeat;
  final _IntDart? repeat;
  final _SetIntDart? setShuffle;
  final _IntDart? shuffle;
  final _SeedDart? setShuffleSeed;
  final _SetIntDart? setGapless;
  final _IntDart? gapless;
  final _SetFloatDart? setCrossfade;
  final _GetFloatDart? crossfade;
  final _SetFloatDart? setSpeed;
  final _GetFloatDart? speed;
  final _SetFloatDart? setPitch;
  final _GetFloatDart? pitch;
  final _SetLoopDart? setSleepTimer;
  final _DoubleDart? sleepRemaining;
  final _LoadDart? saveState;
  final _LoadStateDart? loadState;
  final _CreateDart? libraryCreate;
  final _DestroyDart? libraryDestroy;
  final _LoadDart? libraryScan;
  final _IntDart? libraryCount;
  final _TextAtDart? libraryPath;
  final _IntDart? libraryRemoved;
  final _CreateDart? markersCreate;
  final _DestroyDart? markersDestroy;
  final _LoadDart? markersLoad;
  final _LoadDart? markersSave;
  final _MarkerAddDart? markersAdd;
  final _LoadDart? markersCount;
  final _MarkerPosDart? markersPosition;
  final _MarkerNameDart? markersName;
  final _MarkerRemoveDart? markersRemove;
  final _LoadDart? markersClear;
  final _CueReadDart? cueRead;
  final _DestroyDart? cueFree;
  final _IntDart? cueCount;
  final _TextDart? cueAlbum;
  final _TextDart? cueAlbumPerformer;
  final _TextAtDart? cueFile;
  final _TextAtDart? cueTitle;
  final _TextAtDart? cuePerformer;
  final _DoubleAtDart? cueStart;
  final _DoubleAtDart? cueEnd;
  final _SetIntDart? cueNumber;
  final _NoArgIntDart? outputDeviceCount;
  final _TextIndexDart? outputDeviceName;
  final _IntDart? outputDevice;
  final _SetIntDart? setOutputDevice;
  final _LoudnessDart? loudnessScan;
  final _WaveformDart? waveformPeaks;
  final _PlainTextDart? coreVersion;
  final _MeterDart? meter;
  final _LevelsDart? spectrum;
  final _IntFloatDart? setBandGain;
  final _IntFloatDart? setLimiter;
  final _IntDart? limiter;
  final _IntFloatDart? setCrossfeed;
  final _FloatOutDart? crossfeed;
  final _SetFloatDart? setGainDb;
  final _GetFloatDart? gainDb;
  final _SetFloatDart? setStereoWidth;
  final _GetFloatDart? stereoWidth;
  final _IntFloatDart? setTrimSilence;
  final _FloatOutDart? trimSilence;
  final _SetIntDart? setReplayGain;
  final _GetFloatDart? replayGainGainDb;
  final _GetFloatDart? replayGainPeak;
  final _SetIntDart? setMono;
  final _IntDart? mono;
  final _SetLoopDart? setAbLoop;
  final _ControlDart? clearAbLoop;
  final _TwoDoubleOutDart? abLoop;
  final _TwoDoubleOutDart? analyzeCurrent;
  final _NormalizeDart? normalizeCurrent;
  final _DoubleDart? bufferedSeconds;
  final _U64Dart? bufferUnderflows;
  final _DetectSilenceDart? detectSilence;
  final _TagDart? tag;
  final _TextDart? dateFn;
  final _TextDart? genreFn;
  final _TextDart? composerFn;
  final _IntDart? trackNumber;
  final _IntDart? discNumber;
  final _InsertDart? saveCover;
  final _DoubleDart? sampleRate;
  final _IntDart? channels;
  final _IntDart? lyricsCount;
  final _LyricLineDart? lyricLine;
  final _TextDart titleFn;
  final _TextDart artistFn;
  final _TextDart albumFn;
  final _IntDart coverCount;
  final _CoverAtDart coverAt;
  final _Set8dDart? set8d;
  final _EightDDart? get8d;
  final _SetHrtfDart? setHrtf;
  final _HrtfDart? getHrtf;
  final _SetReverbDart? setReverb;
  final _ReverbDart? getReverb;
  final _SetCompressorDart? setCompressor;
  final _CompressorDart? getCompressor;
  final _SetPeqDart? setPeq;
  final _PeqDart? getPeq;
  final _ControlDart? queueSort;
  final _ControlDart? queueReverse;
  final _SeedDart? queueShuffle;
  final _ControlDart? queueSortTitle;
  final _ControlDart? queueSortArtist;
  final _ControlDart? queueSortAlbum;
  final _ControlDart? queueSortYear;
  final _ControlDart? queueSortTrack;
  final _ControlDart? queueSortDuration;
  final _ControlDart? queueSortAlbumArtist;
  final _ControlDart? queueSortGenre;
  final _ControlDart? queueSortComposer;
  final _ControlDart? queueSortFilesize;
  final _LoadDart? queueInsertSorted;
  final _ControlDart? queueKeepCurrent;
  final _ControlDart? queueDuplicateCurrent;
  final _ControlDart? queueRotate;
  final _LoadDart? queueCountExt;
  final _ControlDart? queuePrune;
  final _ControlDart? queueDedup;
  final _ControlDart? queueDedupHash;
  final _LoadDart? queueFilterDir;
  final _LoadDart? queueExportJson;
  final _LoadDart? queueImportJson;
  final _LoadDart? queueExportM3uExt;
  final _LoadDart? queueExportM3uRelative;
  final _LoadDart? exportQueueCsv;
  final _ExportWavDart? exportWav;
  final _ConcatWavDart? concatWav;
  final _SplitSilenceDart? splitBySilence;
  final _LoadDart? writeReplaygain;
  final _LoadDart? writeReplaygainDir;
  final _ControlDart? writeReplaygainQueue;
  final _LoadDart? writeBpm;
  final _SpectrogramPngDart? spectrogramPng;
  final _DoubleOutDart? albumLoudness;
  final _NormalizeDart? normalizeAlbum;
  final _CountSilencesDart? countSilences;
  final _StripSilenceDart? stripSilence;
  final _ExportIntDart? exportSpectrumCsv;
  final _ExportIntDart? exportWaveformCsv;
  final _ExportPngDart? exportWaveformPng;
  final _ExportSpectrumPngDart? exportSpectrumPng;
  final _LoadDart? favoritesAdd;
  final _LoadDart? favoritesRemove;
  final _IntDart? favoritesCount;
  final _TextAtDart? favoritesPath;
  final _LoadDart? favoritesSave;
  final _LoadDart? favoritesLoad;
  final _LoadDart? favoritesExportM3u;
  final _SetTagDart? setTagFn;
  final _IntDart? coverCountCurrent;
  final _InsertDart? saveCoverCurrent;
  final _LoadDart? saveLyrics;
  final _LoadDart? loadLyrics;
  final _SetDoubleDart? shiftLyrics;
  final _DoubleDart? lyricsOffsetMs;
  final _DetectKeyDart? detectKey;
  final _KeyCurrentDart? keyCurrent;
  final _SetIntDart? setAvoidRecent;
  final _IntDart? avoidRecent;
  final _IntDart? recentCount;
  final _ControlDart? recentClear;
  final _SetIntDart? setPauseAtDirEnd;
  final _IntDart? pauseAtDirEnd;
  final _LoadDart? loadDir;
  final _SetAutoGainDart? setAutoGain;
  final _DoubleOutDart? autoGain;
  final _LibraryExportDart? libraryExportJson;
  final _LibraryExportDart? libraryExportCsv;
  final _LibraryRemoveDart? libraryRemove;
  final _NoArgIntDart? eqPresetCount;
  final _EqPresetNameDart? eqPresetName;
  final _EqPresetFindDart? eqPresetFind;
  final _SetIntDart? applyEqPreset;
  final _LoadDart? saveEqPreset;
  final _LoadDart? loadEqPreset;
  final _CopyTagsDart? copyTags;
  final _BpmDetectDart? bpmDetectPath;
  final _DoubleDart? bpmFn;
  final _DrMeasureDart? drMeasurePath;
  final _EngineDrDart? drFn;
  final _TextDart engineLastErrorFn;
  final _PlainTextDart coreLastErrorFn;
  final _ResultStrDart? resultStr;

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
