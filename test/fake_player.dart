import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cyberhex/core/player_api.dart';

/// Doble de `NativePlayer` para pruebas: sin FFI, sin motor, sin audio.
class FakePlayer extends PlayerApi {
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

  int playCalls = 0;
  int pauseCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  bool disposed = false;

  // --- Cola y modos ---------------------------------------------------------

  /// Rutas de la cola simulada, en orden.
  final List<String> queue = [];

  @override
  int queueIndex = 0;

  @override
  int repeatMode = 0;

  @override
  bool shuffle = false;

  int shuffleSeed = 0;

  @override
  bool gapless = false;

  @override
  double crossfadeSeconds = 0;

  @override
  double speed = 1;

  @override
  double pitch = 0;

  double sleepTimer = -1;
  double sleepFade = 0;

  String? savedStatePath;
  double? stateToLoad;

  @override
  int get queueCount => queue.length;

  @override
  String queueItem(int index) =>
      index < 0 || index >= queue.length ? '' : queue[index];

  @override
  bool playIndex(int index) {
    if (index < 0 || index >= queue.length) return false;
    queueIndex = index;
    position = 0;
    return true;
  }

  @override
  bool loadAdd(String path) {
    queue.add(path);
    queueIndex = queue.length - 1;
    position = 0;
    hasTrack = true;
    return true;
  }

  @override
  bool queueAdd(String path) {
    queue.add(path);
    return true;
  }

  @override
  bool queueInsert(int index, String path) {
    final at = index < 0 || index > queue.length ? queue.length : index;
    queue.insert(at, path);
    return true;
  }

  @override
  bool queueMove(int from, int to) {
    if (from < 0 || from >= queue.length || to < 0 || to >= queue.length) {
      return false;
    }
    queue.insert(to, queue.removeAt(from));
    return true;
  }

  @override
  bool queueRemove(int index) {
    if (index < 0 || index >= queue.length) return false;
    queue.removeAt(index);
    return true;
  }

  @override
  bool queueClear() {
    queue.clear();
    queueIndex = 0;
    return true;
  }

  @override
  int queueImport(String path) => -1;

  @override
  bool queueExport(String path) {
    savedStatePath = path;
    return true;
  }

  @override
  void setShuffleSeed(int seed) => shuffleSeed = seed;

  @override
  void setSleepTimer(double seconds, {double fadeSeconds = 5}) {
    sleepTimer = seconds;
    sleepFade = fadeSeconds;
  }

  @override
  double get sleepRemaining => sleepTimer;

  @override
  bool saveState(String path) {
    savedStatePath = path;
    return true;
  }

  @override
  double? loadState(String path) {
    final seconds = stateToLoad;
    if (seconds == null) return null;
    position = seconds;
    hasTrack = true;
    return seconds;
  }

  // --- Medición y DSP -------------------------------------------------------

  @override
  List<double> levels = const [0, 0, 0, 0];

  @override
  List<double> meterLevels = const [-120, -120, -120];

  @override
  double eqPreamp = 0;

  @override
  bool limiter = false;

  double limiterCeiling = -1;

  @override
  ({bool enabled, double strength}) crossfeed =
      (enabled: false, strength: 0);

  @override
  double gainDb = 0;

  @override
  double stereoWidth = 1;

  @override
  ({bool enabled, double thresholdDb}) trimSilence =
      (enabled: false, thresholdDb: -60);

  bool replayGainEnabled = false;

  @override
  double replayGainGainDb = 0;

  @override
  double replayGainPeak = 0;

  @override
  bool mono = false;

  @override
  ({double start, double end}) abLoop = (start: -1, end: -1);

  @override
  double bufferedSeconds = 0;

  @override
  int bufferUnderflows = 0;

  /// Sonoridad que devolverá [analyzeCurrent] (`null` = falla).
  double? analysisLufs;

  /// dB que devolverá [normalizeCurrent] (`null` = falla).
  double? normalizedDb;

  /// Silencio que devolverá [detectSilence].
  ({double lead, double tail})? silence;

  @override
  List<double> spectrum(int bands) => List<double>.filled(bands, 0);

  @override
  bool setBandGain(int band, double db) {
    if (band < 0 || band >= _gains.length) return false;
    _gains[band] = db;
    return true;
  }

  @override
  void setLimiter(bool enabled, {double ceilingDb = -1}) {
    limiter = enabled;
    limiterCeiling = ceilingDb;
  }

  @override
  void setCrossfeed(bool enabled, {double strength = 0.5}) =>
      crossfeed = (enabled: enabled, strength: strength);

  @override
  void setTrimSilence(bool enabled, {double thresholdDb = -60}) =>
      trimSilence = (enabled: enabled, thresholdDb: thresholdDb);

  @override
  void setReplayGain(bool enabled) => replayGainEnabled = enabled;

  @override
  void setMono(bool enabled) => mono = enabled;

  @override
  void setAbLoop(double start, double end) =>
      abLoop = (start: start, end: end);

  @override
  void clearAbLoop() => abLoop = (start: -1, end: -1);

  @override
  ({double lufs, double peakDb})? analyzeCurrent() {
    final lufs = analysisLufs;
    return lufs == null ? null : (lufs: lufs, peakDb: 0);
  }

  @override
  double? normalizeCurrent(double targetLufs) {
    final db = normalizedDb;
    if (db == null) return null;
    gainDb = db;
    return db;
  }

  @override
  ({double lead, double tail})? detectSilence(String path,
          {double thresholdDb = -60}) =>
      silence;

  // --- Metadatos completos y letras -----------------------------------------

  @override
  String date = '';

  @override
  String genre = '';

  @override
  String composer = '';

  @override
  int trackNumber = 0;

  @override
  int discNumber = 0;

  @override
  int sampleRate = 48000;

  @override
  int channels = 2;

  @override
  int lyricsCount = 0;

  @override
  String activeLyricLine = '';

  /// Etiquetas arbitrarias que devolverá [tag].
  final Map<String, String> tags = {};

  String? savedCoverPath;

  @override
  String tag(String key) => tags[key] ?? '';

  @override
  bool saveCover(int index, String path) {
    if (index < 0 || cover == null) return false;
    savedCoverPath = path;
    return true;
  }

  // --- Biblioteca, marcadores, CUE y dispositivos ---------------------------

  List<String> libraryTracks = const [];
  int libraryRemoved = 0;

  final Map<String, List<TrackMarker>> markersByTrack = {};

  CueSheet? cue;

  @override
  List<String> outputDevices = const ['Altavoces', 'Auriculares'];

  @override
  int outputDevice = -1;

  ({double lufs, double peakDb, double duration})? loudness;

  List<double> waveformPeaksValue = const [];

  @override
  String coreVersion = 'test';

  @override
  ({List<String> tracks, int removed})? scanLibrary(String root) =>
      (tracks: libraryTracks, removed: libraryRemoved);

  @override
  List<TrackMarker> loadMarkers(String path, String track) =>
      markersByTrack['$path|$track'] ?? const [];

  @override
  bool saveMarkers(String path, String track, List<TrackMarker> markers) {
    markersByTrack['$path|$track'] = List<TrackMarker>.of(markers);
    return true;
  }

  @override
  bool removeMarker(String path, String track, int index) {
    final key = '$path|$track';
    final current = markersByTrack[key] ?? const <TrackMarker>[];
    if (index < 0 || index >= current.length) return false;
    markersByTrack[key] = List<TrackMarker>.of(current)..removeAt(index);
    return true;
  }

  @override
  bool clearMarkers(String path, String track) {
    markersByTrack.remove('$path|$track');
    return true;
  }

  @override
  CueSheet? readCue(String path) => cue;

  @override
  ({double lufs, double peakDb, double duration})? scanLoudness(String path) =>
      loudness;

  @override
  List<double> waveform(String path, int buckets) => waveformPeaksValue;

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
  double volume = 1;

  @override
  void setVolume(double value) => volume = value;

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

  @override
  void dispose() {
    disposed = true;
  }
}
