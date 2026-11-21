import 'dart:async';

import 'package:flutter/foundation.dart';

import 'player_api.dart';

/// Estado y acciones del reproductor para la UI.
///
/// Dos canales de notificación a propósito:
///  * [position] (un [ValueNotifier]) cambia con cada tick y solo lo escucha la
///    barra de progreso;
///  * este mismo [ChangeNotifier] avisa solo cuando cambia algo visible
///    (pista, play/pausa, carátula, volumen, error), comparando snapshots.
///
/// Así se puede refrescar la posición a 12,5 Hz sin reconstruir la pantalla.
class PlayerController extends ChangeNotifier {
  PlayerController(this._player);

  final PlayerApi _player;

  static const Duration _tickInterval = Duration(milliseconds: 80);
  static const int _maxEventsPerTick = 32;

  /// Posición actual en segundos.
  final ValueNotifier<double> position = ValueNotifier<double>(0);

  PlayerSnapshot _snapshot = const PlayerSnapshot();
  Timer? _timer;
  Future<bool>? _loading;
  String? _error;
  double _volume = 1;
  bool _disposed = false;

  PlayerSnapshot get snapshot => _snapshot;

  List<double> get eqGains => _player.eqGains;

  List<double> get eqBandFrequencies => _player.eqBandFrequencies;

  /// Arranca el bombeo de eventos y posición.
  void start() {
    if (_disposed) return;
    _timer ??= Timer.periodic(_tickInterval, (_) => pump());
    pump();
  }

  /// Procesa eventos y refresca el estado una vez.
  ///
  /// Lo llama el temporizador; las pruebas pueden llamarlo a mano y así no
  /// dependen de relojes reales.
  void pump() {
    if (_disposed) return;
    final restarted = _drainEvents();
    // Si el motor acaba de cambiar de pista, la posición es la de la pista
    // nueva (0) y no la vieja que todavía devuelve el getter.
    if (!restarted) position.value = _player.position;
    _refresh();
  }

  bool _drainEvents() {
    var processed = 0;
    var restarted = false;
    while (processed < _maxEventsPerTick) {
      final event = _player.pollEvent();
      if (event == null) break;
      processed++;
      // El motor avisa cuando entra una pista nueva (también en gapless o
      // crossfade): hay que releer etiquetas y carátula, porque pueden haber
      // cambiado sin pasar por load().
      if (event.kind == PlayerEventKind.track) {
        _player.syncTrackInfo();
        position.value = 0;
        restarted = true;
      }
    }
    return restarted;
  }

  void _refresh() {
    if (_disposed) return;
    final next = PlayerSnapshot(
      hasTrack: _player.hasTrack,
      title: _player.title,
      artist: _player.artist,
      album: _player.album,
      cover: _player.cover,
      duration: _player.duration,
      playing: _player.isPlaying,
      busy: _loading != null,
      volume: _volume,
      error: _error,
    );
    if (next != _snapshot) {
      _snapshot = next;
      notifyListeners();
    }
  }

  /// Carga una pista sin bloquear la UI.
  ///
  /// Devuelve `null` si fue bien, o el mensaje de error para enseñarlo.
  Future<String?> openFile(String path) async {
    if (_disposed || _loading != null) return null;
    final future = _player.loadAsync(path);
    _loading = future;
    _refresh();
    final ok = await future;
    _loading = null;
    if (_disposed) return null;
    if (ok) {
      position.value = 0;
      _error = null;
    } else {
      _error = _player.lastError;
    }
    _refresh();
    return ok ? null : _error;
  }

  void play() {
    if (_disposed) return;
    _player.play();
    _error = null;
    _refresh();
  }

  void pause() {
    if (_disposed) return;
    _player.pause();
    _refresh();
  }

  void toggle() {
    if (_disposed) return;
    _player.toggle();
    _refresh();
  }

  /// Siguiente pista de la cola.
  ///
  /// El motor puede tardar en abrirla (decodificador aparte): el título nuevo
  /// llega por `CH_EVENT_TRACK`, no aquí.
  void next() {
    if (_disposed) return;
    _player.next();
    _refresh();
  }

  /// Pista anterior de la cola.
  void previous() {
    if (_disposed) return;
    _player.previous();
    _refresh();
  }

  /// Mueve la posición, siempre dentro de `[0, duración]`.
  ///
  /// El acotado vive aquí y no en quien llama porque este es el único punto por
  /// el que pasan la UI, el canal de medios y cualquier control externo, y la
  /// duración se consulta al motor en vivo (el snapshot puede estar viejo).
  void seek(double seconds) {
    if (_disposed) return;
    final duration = _player.duration;
    var target = seconds.isFinite ? seconds : 0.0;
    if (target < 0) target = 0;
    if (duration > 0 && target > duration) target = duration;
    _player.seek(target);
    position.value = target;
    _refresh();
  }

  void setVolume(double value) {
    if (_disposed) return;
    _volume = value.clamp(0, 1).toDouble();
    _player.setVolume(_volume);
    _refresh();
  }

  void setBand(int index, double db) {
    if (_disposed) return;
    _player.setBand(index, db);
  }

  void resetEq() {
    if (_disposed) return;
    _player.resetEq();
  }

  // ---------------------------------------------------------------------------
  // Cola y modos de reproducción
  // ---------------------------------------------------------------------------

  int get queueCount => _player.queueCount;

  int get queueIndex => _player.queueIndex;

  int get repeatMode => _player.repeatMode;

  set repeatMode(int mode) {
    if (_disposed) return;
    _player.repeatMode = mode;
    _refresh();
  }

  bool get shuffle => _player.shuffle;

  set shuffle(bool enabled) {
    if (_disposed) return;
    _player.shuffle = enabled;
    _refresh();
  }

  void setShuffleSeed(int seed) {
    if (_disposed) return;
    _player.setShuffleSeed(seed);
  }

  bool get gapless => _player.gapless;

  set gapless(bool enabled) {
    if (_disposed) return;
    _player.gapless = enabled;
  }

  double get crossfadeSeconds => _player.crossfadeSeconds;

  set crossfadeSeconds(double seconds) {
    if (_disposed) return;
    _player.crossfadeSeconds = seconds;
  }

  double get speed => _player.speed;

  set speed(double value) {
    if (_disposed) return;
    _player.speed = value;
  }

  double get pitch => _player.pitch;

  set pitch(double value) {
    if (_disposed) return;
    _player.pitch = value;
  }

  /// Añade una pista al final de la cola sin cortar la que suena.
  bool enqueue(String path) {
    if (_disposed) return false;
    final ok = _player.queueAdd(path);
    if (ok) _refresh();
    return ok;
  }

  /// Añade una pista al final de la cola y la reproduce.
  bool loadAndPlay(String path) {
    if (_disposed) return false;
    final ok = _player.loadAdd(path);
    if (ok) {
      position.value = 0;
      _error = null;
      _refresh();
    }
    return ok;
  }

  /// Salta a una pista de la cola. El título nuevo llega por `CH_EVENT_TRACK`.
  bool playIndex(int index) {
    if (_disposed) return false;
    final ok = _player.playIndex(index);
    if (ok) position.value = 0;
    _refresh();
    return ok;
  }

  bool queueInsert(int index, String path) {
    if (_disposed) return false;
    final ok = _player.queueInsert(index, path);
    if (ok) _refresh();
    return ok;
  }

  bool queueMove(int from, int to) {
    if (_disposed) return false;
    final ok = _player.queueMove(from, to);
    if (ok) _refresh();
    return ok;
  }

  bool queueRemove(int index) {
    if (_disposed) return false;
    final ok = _player.queueRemove(index);
    if (ok) _refresh();
    return ok;
  }

  bool queueClear() {
    if (_disposed) return false;
    final ok = _player.queueClear();
    if (ok) _refresh();
    return ok;
  }

  int queueImport(String path) => _disposed ? -1 : _player.queueImport(path);

  bool queueExport(String path) =>
      _disposed ? false : _player.queueExport(path);

  void setSleepTimer(double seconds, {double fadeSeconds = 5}) {
    if (_disposed) return;
    _player.setSleepTimer(seconds, fadeSeconds: fadeSeconds);
  }

  double get sleepRemaining => _player.sleepRemaining;

  bool saveState(String path) => _disposed ? false : _player.saveState(path);

  // ---------------------------------------------------------------------------
  // Metadatos completos, letras y carátulas
  // ---------------------------------------------------------------------------

  String get date => _player.date;

  String get genre => _player.genre;

  String get composer => _player.composer;

  int get trackNumber => _player.trackNumber;

  int get discNumber => _player.discNumber;

  String tag(String key) => _player.tag(key);

  int get sampleRate => _player.sampleRate;

  int get channels => _player.channels;

  int get lyricsCount => _player.lyricsCount;

  String get activeLyricLine => _player.activeLyricLine;

  bool saveCover(int index, String path) =>
      _disposed ? false : _player.saveCover(index, path);

  /// Restaura el estado y deja la posición en la pista recuperada.
  double? loadState(String path) {
    if (_disposed) return null;
    final seconds = _player.loadState(path);
    if (seconds == null) return null;
    position.value = seconds;
    _refresh();
    return seconds;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    final pending = _loading;
    if (pending != null) {
      // La carga corre en otro isolate: liberar el motor antes de que termine
      // dejaría un puntero colgado.
      pending.whenComplete(_player.dispose);
    } else {
      _player.dispose();
    }
    position.dispose();
    super.dispose();
  }
}
