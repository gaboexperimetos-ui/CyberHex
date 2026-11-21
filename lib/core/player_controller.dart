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
