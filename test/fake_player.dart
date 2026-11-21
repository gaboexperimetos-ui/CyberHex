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
  int repeatRequests = 0;
  int shuffleRequests = 0;

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

  @override
  void dispose() {
    disposed = true;
  }
}
