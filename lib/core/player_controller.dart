import 'dart:async';

import 'package:flutter/foundation.dart';

import 'player_api.dart';
import 'services/lyrics_service.dart';
import 'services/music_downloader.dart';

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
  List<String> _libraryTracks = const [];
  double? _pendingRestorePosition;
  DateTime? _restoreStartedAt;

  PlayerSnapshot get snapshot => _snapshot;

  List<String> get libraryTracks => _libraryTracks;

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
    if (!restarted) {
      final nativePosition = _player.position;
      final restoreTarget = _pendingRestorePosition;
      if (restoreTarget == null) {
        position.value = nativePosition;
      } else if ((nativePosition - restoreTarget).abs() < 0.5 ||
          DateTime.now().difference(_restoreStartedAt!) >
              const Duration(seconds: 3)) {
        _pendingRestorePosition = null;
        _restoreStartedAt = null;
        position.value = nativePosition;
      } else {
        position.value = restoreTarget;
      }
    }
    _refresh(force: restarted);
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
        if (_pendingRestorePosition == null) position.value = 0;
        restarted = true;
      }
    }
    return restarted;
  }

  void _refresh({bool force = false}) {
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
    if (force || next != _snapshot) {
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
    _pendingRestorePosition = null;
    _restoreStartedAt = null;
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
    _refresh(force: ok);
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
    _pendingRestorePosition = null;
    _restoreStartedAt = null;
    _player.next();
    _refresh();
  }

  /// Pista anterior de la cola.
  ///
  /// Si ya se han escuchado más de [_restartThreshold] segundos, primero
  /// reinicia la pista actual: es lo que espera cualquiera que venga de
  /// Spotify, Strawberry o Tauon.
  void previous() {
    if (_disposed) return;
    _pendingRestorePosition = null;
    _restoreStartedAt = null;
    if (position.value > _restartThreshold) {
      seek(0);
      return;
    }
    _player.previous();
    _refresh();
  }

  static const double _restartThreshold = 3;

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
    _pendingRestorePosition = null;
    _restoreStartedAt = null;
    position.value = target;
    _refresh();
  }

  void setVolume(double value) {
    if (_disposed) return;
    _volume = value.clamp(0, 1).toDouble();
    _player.setVolume(_volume);
    _refresh();
  }

  /// Volumen efectivo del motor; puede diferir del pedido si el núcleo acota.
  double get volume => _player.volume;

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

  String get currentTrackPath {
    final index = queueIndex;
    if (index < 0 || index >= queueCount) return '';
    return queueItem(index);
  }

  String queueItem(int index) => _player.queueItem(index);

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
    _pendingRestorePosition = null;
    _restoreStartedAt = null;
    final ok = _player.loadAdd(path);
    if (ok) {
      position.value = 0;
      _error = null;
      _refresh(force: true);
    }
    return ok;
  }

  /// Salta a una pista de la cola. El título nuevo llega por `CH_EVENT_TRACK`.
  bool playIndex(int index) {
    if (_disposed) return false;
    _pendingRestorePosition = null;
    _restoreStartedAt = null;
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
  // Medición y DSP
  // ---------------------------------------------------------------------------

  List<double> get levels => _player.levels;

  List<double> get meterLevels => _player.meterLevels;

  List<double> spectrum(int bands) => _player.spectrum(bands);

  double get eqPreamp => _player.eqPreamp;

  set eqPreamp(double db) {
    if (_disposed) return;
    _player.eqPreamp = db;
  }

  bool setBandGain(int band, double db) =>
      _disposed ? false : _player.setBandGain(band, db);

  void setLimiter(bool enabled, {double ceilingDb = -1}) {
    if (_disposed) return;
    _player.setLimiter(enabled, ceilingDb: ceilingDb);
  }

  bool get limiter => _player.limiter;

  void setCrossfeed(bool enabled, {double strength = 0.5}) {
    if (_disposed) return;
    _player.setCrossfeed(enabled, strength: strength);
  }

  ({bool enabled, double strength}) get crossfeed => _player.crossfeed;

  double get gainDb => _player.gainDb;

  set gainDb(double db) {
    if (_disposed) return;
    _player.gainDb = db;
  }

  double get stereoWidth => _player.stereoWidth;

  set stereoWidth(double width) {
    if (_disposed) return;
    _player.stereoWidth = width;
  }

  void setTrimSilence(bool enabled, {double thresholdDb = -60}) {
    if (_disposed) return;
    _player.setTrimSilence(enabled, thresholdDb: thresholdDb);
  }

  ({bool enabled, double thresholdDb}) get trimSilence => _player.trimSilence;

  void setReplayGain(bool enabled) {
    if (_disposed) return;
    _player.setReplayGain(enabled);
  }

  double get replayGainGainDb => _player.replayGainGainDb;

  double get replayGainPeak => _player.replayGainPeak;

  void setMono(bool enabled) {
    if (_disposed) return;
    _player.setMono(enabled);
  }

  bool get mono => _player.mono;

  void setAbLoop(double start, double end) {
    if (_disposed) return;
    _player.setAbLoop(start, end);
  }

  void clearAbLoop() {
    if (_disposed) return;
    _player.clearAbLoop();
  }

  ({double start, double end}) get abLoop => _player.abLoop;

  ({double lufs, double peakDb})? analyzeCurrent() =>
      _disposed ? null : _player.analyzeCurrent();

  double? normalizeCurrent(double targetLufs) =>
      _disposed ? null : _player.normalizeCurrent(targetLufs);

  double get bufferedSeconds => _player.bufferedSeconds;

  int get bufferUnderflows => _player.bufferUnderflows;

  // ---------------------------------------------------------------------------
  // Biblioteca, marcadores, CUE y utilidades de archivo
  // ---------------------------------------------------------------------------

  ({List<String> tracks, int removed})? scanLibrary(String root) {
    if (_disposed) return null;
    final result = _player.scanLibrary(root);
    if (result != null) {
      _libraryTracks = List.unmodifiable(result.tracks);
      notifyListeners();
    }
    return result;
  }

  List<TrackMarker> loadMarkers(String path, String track) =>
      _disposed ? const [] : _player.loadMarkers(path, track);

  bool saveMarkers(String path, String track, List<TrackMarker> markers) =>
      _disposed ? false : _player.saveMarkers(path, track, markers);

  bool removeMarker(String path, String track, int index) =>
      _disposed ? false : _player.removeMarker(path, track, index);

  bool clearMarkers(String path, String track) =>
      _disposed ? false : _player.clearMarkers(path, track);

  CueSheet? readCue(String path) => _disposed ? null : _player.readCue(path);

  List<String> get outputDevices => _player.outputDevices;

  int get outputDevice => _player.outputDevice;

  set outputDevice(int index) {
    if (_disposed) return;
    _player.outputDevice = index;
  }

  ({double lufs, double peakDb, double duration})? scanLoudness(String path) =>
      _disposed ? null : _player.scanLoudness(path);

  List<double> waveform(String path, int buckets) =>
      _disposed ? const [] : _player.waveform(path, buckets);

  Future<List<double>> waveformAsync(String path, int buckets) =>
      _disposed ? Future.value(const []) : _player.waveformAsync(path, buckets);

  String get coreVersion => _player.coreVersion;

  ({double lead, double tail})? detectSilence(
    String path, {
    double thresholdDb = -60,
  }) =>
      _disposed ? null : _player.detectSilence(path, thresholdDb: thresholdDb);

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

  // ---------------------------------------------------------------------------
  // Letras y descarga (servicios Dart; requieren red)
  // ---------------------------------------------------------------------------

  /// Busca la letra de la pista actual en Lrclib y, si [useAiFallback] y hay un
  /// [aiEndpoint] configurado, usa IA de respaldo. Devuelve null si no hay.
  Future<LyricsResult?> fetchLyrics({
    bool useAiFallback = false,
    String? aiEndpoint,
    String? aiApiKey,
  }) async {
    final service = LyricsService(aiEndpoint: aiEndpoint, aiApiKey: aiApiKey);
    return service.fetch(
      title: _player.title,
      artist: _player.artist,
      album: _player.album,
      durationSeconds: _player.duration,
      useAiFallback: useAiFallback,
    );
  }

  /// Descarga `url` a `destPath`. `referer` opcional. Devuelve el resultado o
  /// null si falla.
  Future<DownloadResult?> downloadTrack({
    required String url,
    required String destPath,
    String? referer,
  }) {
    final dl = MusicDownloader(jamendoClientId: null);
    return dl.downloadUrl(url: url, destPath: destPath, referer: referer);
  }

  /// Restaura el estado y deja la posición en la pista recuperada.
  double? loadState(String path) {
    if (_disposed) return null;
    final seconds = _player.loadState(path);
    if (seconds == null) return null;
    var restoredPosition = seconds.isFinite ? seconds : 0.0;
    if (restoredPosition < 0) restoredPosition = 0;
    final duration = _player.duration;
    if (duration > 0 && restoredPosition > duration) {
      restoredPosition = duration;
    }
    _pendingRestorePosition = restoredPosition > 0 ? restoredPosition : null;
    _restoreStartedAt = restoredPosition > 0 ? DateTime.now() : null;
    position.value = restoredPosition;
    _refresh(force: true);
    return restoredPosition;
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
