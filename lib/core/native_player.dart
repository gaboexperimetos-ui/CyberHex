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

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    calloc.free(_eventBuf);
    calloc.free(_levelBuf);
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
        coreLastErrorFn = lib.lookupFunction<_PlainTextNative, _PlainTextDart>('ch_core_last_error');

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
