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
  bool _queueProtected = false;
  List<QueueItem> _queue = const <QueueItem>[];
  int _queueIndex = -1;
  List<LibraryTrack> _libraryTracks = const <LibraryTrack>[];
  bool _disposed = false;

  PlayerSnapshot get snapshot => _snapshot;

  /// ¿La cola está protegida? Con el flag activo, abrir un archivo suelto lo
  /// añade al final y lo reproduce **sin** vaciar lo que ya había.
  bool get queueProtected => _queueProtected;

  set queueProtected(bool value) {
    if (_disposed || value == _queueProtected) return;
    _queueProtected = value;
    _refresh();
  }

  /// Último resultado de [scanDirectory]; la vista de biblioteca lo usa para no
  /// repetir el escaneo al volver de la pantalla de reproducción.
  List<LibraryTrack> get libraryTracks => _libraryTracks;

  /// Pistas que el último escaneo dio por desaparecidas.
  int get libraryRemoved => _player.libraryRemoved;

  List<double> get eqGains => _player.eqGains;

  List<double> get eqBandFrequencies => _player.eqBandFrequencies;

  /// Arranca el bombeo de eventos y posición.
  void start() {
    if (_disposed) return;
    _timer ??= Timer.periodic(_tickInterval, (_) => pump());
    pump();
    _refreshQueue();
  }

  /// Procesa eventos y refresca el estado una vez.
  ///
  /// Lo llama el temporizador; las pruebas pueden llamarlo a mano y así no
  /// dependen de relojes reales.
  void pump() {
    if (_disposed) return;
    _drainEvents();
    position.value = _player.position;
    _refresh();
  }

  void _drainEvents() {
    var processed = 0;
    while (processed < _maxEventsPerTick) {
      final event = _player.pollEvent();
      if (event == null) break;
      processed++;
      // El motor avisa cuando entra una pista nueva (también en gapless o
      // crossfade): hay que releer etiquetas y carátula, porque pueden haber
      // cambiado sin pasar por load().
      switch (event.kind) {
        case PlayerEventKind.track:
          _player.syncTrackInfo();
          position.value = 0;
          _refreshQueue();
        case PlayerEventKind.queue:
          _refreshQueue();
        case PlayerEventKind.state:
        case PlayerEventKind.end:
        case PlayerEventKind.sleep:
        case PlayerEventKind.unknown:
          break;
      }
    }
  }

  /// Relee la cola del motor y notifica solo si cambió.
  ///
  /// Construir `QueueItem`s cuesta (recorre rutas y nombres), así que no se
  /// hace en cada tick de 80 ms: solo cuando llega `EV_QUEUE`/`EV_TRACK` o tras
  /// una mutación nuestra.
  void _refreshQueue() {
    if (_disposed) return;
    final items = _player.queueItems;
    final index = _player.queueIndex;
    if (index == _queueIndex && _sameQueue(items, _queue)) return;
    _queue = items;
    _queueIndex = index;
    _refresh();
  }

  static bool _sameQueue(List<QueueItem> a, List<QueueItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
      repeatMode: _player.repeatMode,
      shuffle: _player.shuffle,
      queue: _queue,
      queueIndex: _queueIndex,
      queueProtected: _queueProtected,
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
    // Con la cola protegida, `load_add` añade al final y reproduce sin vaciar;
    // sin ella, `load` deja la cola con esta única pista.
    final future =
        _queueProtected ? _player.loadAndPlayAsync(path) : _player.loadAsync(path);
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
    _refreshQueue();
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

  void seek(double seconds) {
    if (_disposed) return;
    _player.seek(seconds);
    position.value = seconds;
    _refresh();
  }

  void setVolume(double value) {
    if (_disposed) return;
    _volume = value.clamp(0, 1).toDouble();
    _player.setVolume(_volume);
    _refresh();
  }

  /// Cicla el modo de repetición: apagado → todo → una → apagado.
  void cycleRepeat() {
    if (_disposed) return;
    _player.cycleRepeat();
    _refresh();
  }

  /// Activa o desactiva la reproducción aleatoria.
  void toggleShuffle() {
    if (_disposed) return;
    _player.toggleShuffle();
    _refresh();
  }

  // ---------------------------------------------------------------------
  // Cola
  // ---------------------------------------------------------------------

  /// Salta a la pista `index` de la cola y la reproduce.
  ///
  /// Devuelve `false` si el índice no existe o el motor no pudo abrirla.
  bool playAt(int index) {
    if (_disposed) return false;
    if (index < 0 || index >= _player.queueLength) return false;
    final ok = _player.playAt(index);
    if (ok) {
      position.value = 0;
      _error = null;
      _loading = null;
    } else {
      _error = _player.lastError;
    }
    _refreshQueue();
    _refresh();
    return ok;
  }

  /// Añade `path` al final de la cola sin tocar lo que suena.
  bool enqueue(String path) {
    if (_disposed) return false;
    final ok = _player.enqueue(path);
    _refreshQueue();
    return ok;
  }

  /// Inserta `path` justo después de la pista actual.
  bool playNext(String path) {
    if (_disposed) return false;
    final ok = _player.playNext(path);
    _refreshQueue();
    return ok;
  }

  /// Añade al final y reproduce, conservando la cola.
  Future<bool> loadAndPlay(String path) async {
    if (_disposed) return false;
    final ok = await _player.loadAndPlayAsync(path);
    if (_disposed) return false;
    if (ok) {
      position.value = 0;
      _error = null;
    } else {
      _error = _player.lastError;
    }
    _refreshQueue();
    _refresh();
    return ok;
  }

  bool moveQueueItem(int from, int to) {
    if (_disposed) return false;
    final ok = _player.moveQueueItem(from, to);
    _refreshQueue();
    return ok;
  }

  bool removeQueueItem(int index) {
    if (_disposed) return false;
    final ok = _player.removeQueueItem(index);
    _refreshQueue();
    _refresh();
    return ok;
  }

  void clearQueue() {
    if (_disposed) return;
    _player.clearQueue();
    position.value = 0;
    _refreshQueue();
    _refresh();
  }

  // ---------------------------------------------------------------------
  // Biblioteca
  // ---------------------------------------------------------------------

  /// Escanea `root` de forma recursiva y cachea el resultado.
  Future<List<LibraryTrack>> scanDirectory(String root) async {
    if (_disposed) return const <LibraryTrack>[];
    final tracks = await _player.scanDirectory(root);
    if (_disposed) return tracks;
    _libraryTracks = tracks;
    notifyListeners();
    return tracks;
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
