import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cyberhex/core/player_api.dart';

/// Doble de `NativePlayer` para pruebas: sin FFI, sin motor, sin audio.
class FakePlayer implements PlayerApi {
  FakePlayer({
    this.hasTrack = false,
    this.title = '',
    this.artist = '',
    this.album = '',
  });

  @override
  bool hasTrack;

  @override
  String title;

  @override
  String artist;

  @override
  String album;

  @override
  Uint8List? cover;

  @override
  double duration = 0;

  @override
  double position = 0;

  @override
  bool isPlaying = false;

  @override
  String lastError = '';

  final List<double> _gains = List<double>.filled(_bandCount, 0);
  static const int _bandCount = 36;

  @override
  List<double> get eqGains => _gains;

  @override
  List<double> get eqBandFrequencies => List<double>.generate(
        _bandCount,
        (i) => 20 * math.pow(1000, i / (_bandCount - 1)).toDouble(),
      );

  /// Resultado que devolverá [load] / [loadAsync].
  bool loadResult = true;

  /// Rutas cargadas, en orden.
  final List<String> loadedPaths = [];

  @override
  int repeatMode = 0;

  @override
  bool shuffle = false;

  /// Cuántas veces se pidió cambiar de modo (para comprobar la llamada).
  // Fase 2: DSP. Se guardan ya recortados, como hace el motor.
  bool nineDFlag = false;
  double nineDSpeedValue = 0.15;
  double nineDDepthValue = 0.65;
  double stereoWidthValue = 1;
  double bassPunchValue = 0;
  double vocalCutValue = 0;
  bool crossfeedFlag = false;
  double crossfeedLevelValue = 0.5;
  bool nightModeFlag = false;
  double nightModeAmountValue = 0.5;
  bool s16Flag = false;

  int nineDCalls = 0;
  int stereoEnhanceCalls = 0;
  int vocalCutCalls = 0;
  int crossfeedCalls = 0;
  int nightModeCalls = 0;
  int s16Calls = 0;

  int repeatRequests = 0;
  int shuffleRequests = 0;

  /// Cola simulada: rutas en orden. La mantiene este doble igual que el motor
  /// mantiene la suya.
  final List<String> queuePaths = <String>[];
  int queueIndexValue = -1;

  /// Biblioteca que devolverá [scanDirectory].
  List<LibraryTrack> library = const <LibraryTrack>[];

  int scanCalls = 0;
  int playAtCalls = 0;
  int enqueueCalls = 0;
  int playNextCalls = 0;
  int loadAndPlayCalls = 0;
  int moveCalls = 0;
  int removeCalls = 0;
  int clearCalls = 0;

  int playCalls = 0;
  int pauseCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  bool disposed = false;

  final List<PlayerEvent> _events = [];

  /// Encola un evento como si lo hubiera emitido el motor.
  void emit(PlayerEvent event) => _events.add(event);

  @override
  bool load(String path) {
    loadedPaths.add(path);
    if (!loadResult) return false;
    hasTrack = true;
    position = 0;
    return true;
  }

  @override
  Future<bool> loadAsync(String path) async {
    loadedPaths.add(path);
    if (!loadResult) return false;
    hasTrack = true;
    position = 0;
    if (duration == 0) duration = 120;
    // ch_engine_load deja la cola con esta única pista.
    queuePaths
      ..clear()
      ..add(path);
    queueIndexValue = 0;
    return true;
  }

  @override
  void syncTrackInfo() {}

  @override
  void play() {
    playCalls++;
    isPlaying = true;
  }

  @override
  void pause() {
    pauseCalls++;
    isPlaying = false;
  }

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
    nextCalls++;
    position = 0;
  }

  @override
  void previous() {
    previousCalls++;
    position = 0;
  }

  @override
  void seek(double seconds) {
    position = seconds;
  }

  @override
  void setVolume(double value) {}

  @override
  void setRepeatMode(int mode) {
    repeatRequests++;
    repeatMode = math.max(0, math.min(2, mode));
  }

  @override
  void setShuffle(bool enabled) {
    shuffleRequests++;
    shuffle = enabled;
  }

  @override
  void cycleRepeat() {
    repeatRequests++;
    repeatMode = (repeatMode + 1) % 3;
  }

  @override
  void toggleShuffle() {
    shuffleRequests++;
    shuffle = !shuffle;
  }

  @override
  void setBand(int index, double db) {
    _gains[index] = db;
  }

  @override
  void resetEq() {
    for (var i = 0; i < _gains.length; i++) {
      _gains[i] = 0;
    }
  }

  @override
  PlayerEvent? pollEvent() => _events.isEmpty ? null : _events.removeAt(0);

  // ---------------------------------------------------------------------
  // Fase 2: DSP
  // ---------------------------------------------------------------------

  @override
  bool get nineDEnabled => nineDFlag;

  @override
  double get nineDSpeed => nineDSpeedValue;

  @override
  double get nineDDepth => nineDDepthValue;

  @override
  void set9D(bool enabled, double speedHz, double depth) {
    nineDCalls++;
    nineDFlag = enabled;
    nineDSpeedValue = speedHz.clamp(0.05, 2.0).toDouble();
    nineDDepthValue = depth.clamp(0.0, 1.0).toDouble();
  }

  @override
  double get stereoWidth => stereoWidthValue;

  @override
  double get bassPunch => bassPunchValue;

  @override
  void setStereoEnhance(double width, double bassPunch) {
    stereoEnhanceCalls++;
    stereoWidthValue = width.clamp(0.0, 2.0).toDouble();
    bassPunchValue = bassPunch.clamp(0.0, 1.0).toDouble();
  }

  @override
  void setStereoWidth(double width) {
    stereoWidthValue = width.clamp(0.0, 2.0).toDouble();
  }

  @override
  double get vocalCut => vocalCutValue;

  @override
  void setVocalCut(double amount) {
    vocalCutCalls++;
    vocalCutValue = amount.clamp(0.0, 1.0).toDouble();
  }

  @override
  bool get crossfeedEnabled => crossfeedFlag;

  @override
  double get crossfeedLevel => crossfeedLevelValue;

  @override
  void setCrossfeed(bool enabled, double level) {
    crossfeedCalls++;
    crossfeedFlag = enabled;
    crossfeedLevelValue = level.clamp(0.0, 1.0).toDouble();
  }

  @override
  bool get nightModeEnabled => nightModeFlag;

  @override
  double get nightModeAmount => nightModeAmountValue;

  @override
  void setNightMode(bool enabled, double amount) {
    nightModeCalls++;
    nightModeFlag = enabled;
    nightModeAmountValue = amount.clamp(0.0, 1.0).toDouble();
  }

  @override
  bool get s16Output => s16Flag;

  @override
  void setS16Output(bool enabled) {
    s16Calls++;
    s16Flag = enabled;
  }

  // ---------------------------------------------------------------------
  // Cola
  // ---------------------------------------------------------------------

  @override
  int get queueLength => queuePaths.length;

  @override
  int get queueIndex => queueIndexValue;

  @override
  List<QueueItem> get queueItems => List<QueueItem>.unmodifiable(<QueueItem>[
        for (var i = 0; i < queuePaths.length; i++)
          QueueItem(
            path: queuePaths[i],
            title: titleFromPath(queuePaths[i]),
            artist: i == queueIndexValue ? artist : '',
          ),
      ]);

  @override
  bool playAt(int index) {
    playAtCalls++;
    if (index < 0 || index >= queuePaths.length) return false;
    queueIndexValue = index;
    title = titleFromPath(queuePaths[index]);
    hasTrack = true;
    position = 0;
    isPlaying = true;
    return true;
  }

  @override
  bool enqueue(String path) {
    enqueueCalls++;
    queuePaths.add(path);
    return true;
  }

  @override
  bool playNext(String path) {
    playNextCalls++;
    final at = queueIndexValue < 0
        ? queuePaths.length
        : math.min(queueIndexValue + 1, queuePaths.length);
    queuePaths.insert(at, path);
    return true;
  }

  @override
  Future<bool> loadAndPlayAsync(String path) async {
    loadAndPlayCalls++;
    loadedPaths.add(path);
    if (!loadResult) return false;
    queuePaths.add(path);
    queueIndexValue = queuePaths.length - 1;
    title = titleFromPath(path);
    hasTrack = true;
    position = 0;
    if (duration == 0) duration = 120;
    isPlaying = true;
    return true;
  }

  @override
  bool moveQueueItem(int from, int to) {
    moveCalls++;
    if (from < 0 || to < 0 || from >= queuePaths.length || to >= queuePaths.length) {
      return false;
    }
    if (from == to) return true;
    final item = queuePaths.removeAt(from);
    queuePaths.insert(to, item);
    if (queueIndexValue == from) {
      queueIndexValue = to;
    } else if (from < queueIndexValue && to >= queueIndexValue) {
      queueIndexValue -= 1;
    } else if (from > queueIndexValue && to <= queueIndexValue) {
      queueIndexValue += 1;
    }
    return true;
  }

  @override
  bool removeQueueItem(int index) {
    removeCalls++;
    if (index < 0 || index >= queuePaths.length) return false;
    queuePaths.removeAt(index);
    if (queuePaths.isEmpty) {
      queueIndexValue = -1;
      hasTrack = false;
      isPlaying = false;
    } else if (index < queueIndexValue) {
      queueIndexValue -= 1;
    } else if (index == queueIndexValue) {
      queueIndexValue = math.min(index, queuePaths.length - 1);
      title = titleFromPath(queuePaths[queueIndexValue]);
    }
    return true;
  }

  @override
  void clearQueue() {
    clearCalls++;
    queuePaths.clear();
    queueIndexValue = -1;
    hasTrack = false;
    isPlaying = false;
    duration = 0;
    position = 0;
  }

  @override
  int importQueue(String playlistPath) => 0;

  @override
  bool exportQueue(String playlistPath) => false;

  // ---------------------------------------------------------------------
  // Biblioteca
  // ---------------------------------------------------------------------

  @override
  int get libraryRemoved => 0;

  @override
  Future<List<LibraryTrack>> scanDirectory(String root) async {
    scanCalls++;
    return library;
  }

  @override
  void dispose() {
    disposed = true;
  }
}
