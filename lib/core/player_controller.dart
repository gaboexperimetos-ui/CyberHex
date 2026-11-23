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
  PlayerController(this._player) {
    // El primer snapshot se construye aquí: sin esto, quien lo consulte antes
    // del primer `pump()` ve un `PlayerSnapshot()` vacío (sin pista ni cola).
    _refreshQueue();
    _refresh();
  }

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

  /// Se avisa cuando cambia un ajuste que hay que persistir (DSP, mezcla,
  /// paisaje, ReplayGain, crossfade, velocidad, tono). El `SessionKeeper` lo
  /// escucha para guardar sin esperar a que cambie de pista.
  final List<void Function()> _audioListeners = <void Function()>[];

  void addAudioListener(void Function() listener) =>
      _audioListeners.add(listener);

  void removeAudioListener(void Function() listener) =>
      _audioListeners.remove(listener);

  void _audioChanged() {
    for (final listener in List<void Function()>.of(_audioListeners)) {
      listener();
    }
    _refresh();
  }

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
  /// `true` si en este tick entró una pista nueva: la posición ya se puso a 0
  /// y no hay que pisarla con la que aún reporta el motor.
  bool _trackJustChanged = false;

  void pump() {
    if (_disposed) return;
    _trackJustChanged = false;
    _drainEvents();
    if (!_trackJustChanged) position.value = _player.position;
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
          _trackJustChanged = true;
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
      nineDEnabled: _player.nineDEnabled,
      nineDSpeed: _player.nineDSpeed,
      nineDDepth: _player.nineDDepth,
      stereoWidth: _player.stereoWidth,
      bassPunch: _player.bassPunch,
      vocalCut: _player.vocalCut,
      crossfeedEnabled: _player.crossfeedEnabled,
      crossfeedLevel: _player.crossfeedLevel,
      nightModeEnabled: _player.nightModeEnabled,
      nightModeAmount: _player.nightModeAmount,
      s16Output: _player.s16Output,
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
    _audioChanged();
  }

  /// Fija el modo de repetición (0 apagado, 1 todo, 2 una).
  void setRepeatMode(int mode) {
    if (_disposed) return;
    _player.setRepeatMode(mode);
    _refresh();
  }

  /// Fija el aleatorio sin alternarlo (lo usa la restauración de sesión).
  void setShuffle(bool enabled) {
    if (_disposed) return;
    _player.setShuffle(enabled);
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
  // Fase 2: núcleo DSP audiófilo
  // ---------------------------------------------------------------------

  /// 9D espacial. Solo se envía lo que cambia: `null` deja el valor del motor.
  void set9D({bool? enabled, double? speed, double? depth}) {
    if (_disposed) return;
    _player.set9D(
      enabled ?? _player.nineDEnabled,
      speed ?? _player.nineDSpeed,
      depth ?? _player.nineDDepth,
    );
    _audioChanged();
  }

  void toggle9D() => set9D(enabled: !_player.nineDEnabled);

  /// Potenciador estéreo: ancho (0..2) y punch de graves (0..1).
  void setStereoEnhance({double? width, double? bassPunch}) {
    if (_disposed) return;
    _player.setStereoEnhance(
      width ?? _player.stereoWidth,
      bassPunch ?? _player.bassPunch,
    );
    _audioChanged();
  }

  /// Karaoke: 0 apagado, 1 voz fuera (los subgraves se conservan).
  void setVocalCut(double amount) {
    if (_disposed) return;
    _player.setVocalCut(amount);
    _audioChanged();
  }

  void toggleVocalCut() => setVocalCut(_player.vocalCut > 0 ? 0 : 0.85);

  void setCrossfeed({bool? enabled, double? level}) {
    if (_disposed) return;
    _player.setCrossfeed(
      enabled ?? _player.crossfeedEnabled,
      level ?? _player.crossfeedLevel,
    );
    _audioChanged();
  }

  void toggleCrossfeed() =>
      setCrossfeed(enabled: !_player.crossfeedEnabled);

  void setNightMode({bool? enabled, double? amount}) {
    if (_disposed) return;
    _player.setNightMode(
      enabled ?? _player.nightModeEnabled,
      amount ?? _player.nightModeAmount,
    );
    _audioChanged();
  }

  void toggleNightMode() =>
      setNightMode(enabled: !_player.nightModeEnabled);

  /// Salida S16 con dither TPDF (por defecto, f32).
  void setS16Output(bool enabled) {
    if (_disposed) return;
    _player.setS16Output(enabled);
    _audioChanged();
  }

  // ---------------------------------------------------------------------
  // Fase 3: medición, mezcla fina y ajustes que se guardan
  // ---------------------------------------------------------------------

  /// Niveles de salida para el vúmetro.
  PlayerLevels levels() => _player.levels();

  /// Espectro de 20 Hz a 20 kHz, `bands` valores 0..1.
  List<double> spectrum([int bands = 32]) => _player.spectrum(bands);

  double get balance => _player.balance;

  void setBalance(double value) {
    if (_disposed) return;
    _player.setBalance(value);
    _audioChanged();
  }

  int get channelMode => _player.channelMode;

  void setChannelMode(int mode) {
    if (_disposed) return;
    _player.setChannelMode(mode);
    _audioChanged();
  }

  bool get replayGainEnabled => _player.replayGainEnabled;

  void setReplayGain(bool enabled) {
    if (_disposed) return;
    _player.setReplayGain(enabled);
    _audioChanged();
  }

  bool get replayGainAlbum => _player.replayGainAlbum;

  void setReplayGainAlbum(bool album) {
    if (_disposed) return;
    _player.setReplayGainAlbum(album);
    _audioChanged();
  }

  double get replayGainGainDb => _player.replayGainGainDb;

  double get replayGainPeak => _player.replayGainPeak;

  double get speed => _player.speed;

  void setSpeed(double value) {
    if (_disposed) return;
    _player.setSpeed(value);
    _audioChanged();
  }

  double get pitch => _player.pitch;

  void setPitch(double semitones) {
    if (_disposed) return;
    _player.setPitch(semitones);
    _audioChanged();
  }

  double get crossfade => _player.crossfade;

  void setCrossfade(double seconds) {
    if (_disposed) return;
    _player.setCrossfade(seconds);
    _audioChanged();
  }

  bool get gapless => _player.gapless;

  void setGapless(bool enabled) {
    if (_disposed) return;
    _player.setGapless(enabled);
    _audioChanged();
  }

  bool get loopActive => _player.loopActive;

  double get loopStart => _player.loopStart;

  double get loopEnd => _player.loopEnd;

  /// Loop A-B en segundos. `end <= start` lo desactiva.
  void setLoop(double start, double end) {
    if (_disposed) return;
    _player.setLoop(start, end);
    _refresh();
  }

  void clearLoop() {
    if (_disposed) return;
    _player.clearLoop();
    _refresh();
  }

  /// Paisaje sonoro bajo la música.
  SoundscapePreset get soundscape => _player.soundscape;

  double get soundscapeLevel => _player.soundscapeLevel;

  void setSoundscape(SoundscapePreset preset, {double? level}) {
    if (_disposed) return;
    _player.setSoundscape(preset, level: level);
    _audioChanged();
  }

  /// Cicla los paisajes: off → lluvia → marrón → vinilo → off.
  void cycleSoundscape() {
    final next = SoundscapePreset.values[
        (soundscape.index + 1) % SoundscapePreset.values.length];
    setSoundscape(next, level: next == SoundscapePreset.off ? 0 : null);
  }

  // Marcadores

  bool loadMarkers(String path) => _player.loadMarkers(path);

  bool saveMarkers(String path) {
    final ok = _player.saveMarkers(path);
    if (ok) _audioChanged();
    return ok;
  }

  List<AudioMarker> markersOf(String trackPath) => _player.markersOf(trackPath);

  bool addMarker(String trackPath, double position, String name) {
    final ok = _player.addMarker(trackPath, position, name);
    if (ok) _audioChanged();
    return ok;
  }

  bool removeMarker(String trackPath, int index) {
    final ok = _player.removeMarker(trackPath, index);
    if (ok) _audioChanged();
    return ok;
  }

  void clearMarkers(String trackPath) {
    _player.clearMarkers(trackPath);
    _audioChanged();
  }

  /// Marca la posición actual de la pista audible.
  bool addMarkerHere([String name = '']) {
    final path = snapshot.queueIndex >= 0 &&
            snapshot.queueIndex < snapshot.queue.length
        ? snapshot.queue[snapshot.queueIndex].path
        : '';
    if (path.isEmpty) return false;
    return addMarker(path, position.value, name);
  }

  // Temporizador, silencio y dispositivo

  void setSleepTimer(double seconds, {double fadeSeconds = 8}) {
    if (_disposed) return;
    _player.setSleepTimer(seconds, fadeSeconds: fadeSeconds);
    _refresh();
  }

  double get sleepRemaining => _player.sleepRemaining;

  Future<SilenceTrim?> detectSilence(String path, {double thresholdDb = -60}) =>
      _player.detectSilence(path, thresholdDb: thresholdDb);

  List<AudioDevice> get outputDevices => _player.outputDevices;

  int get outputDevice => _player.outputDevice;

  bool setOutputDevice(int index) {
    if (_disposed) return false;
    final ok = _player.setOutputDevice(index);
    if (ok) _refresh();
    return ok;
  }

  int get lyricLineCount => _player.lyricLineCount;

  String get currentLyricLine => _player.currentLyricLine;

  // Análisis y exportación

  Future<double> detectBpm(String path) => _player.detectBpm(path);

  Future<bool> renderWav(
    String sourcePath,
    String destinationPath, {
    double start = 0,
    double end = 0,
    bool withDsp = true,
  }) async {
    if (_disposed) return false;
    final ok = await _player.renderWav(
      sourcePath,
      destinationPath,
      start: start,
      end: end,
      withDsp: withDsp,
    );
    if (_disposed) return ok;
    if (!ok) _error = _player.lastError;
    _refresh();
    return ok;
  }

  List<CueTrack> readCue(String path) => _player.readCue(path);

  List<CueTrack> parseCue(String text) => _player.parseCue(text);

  /// Ajustes que se guardan en la sesión (decisión del arquitecto,
  /// 2026-11-21: el DSP vive en `SessionStore`, no en el estado del motor).
  AudioSettings audioSettings() => AudioSettings(
        nineDEnabled: _player.nineDEnabled,
        nineDSpeed: _player.nineDSpeed,
        nineDDepth: _player.nineDDepth,
        stereoWidth: _player.stereoWidth,
        bassPunch: _player.bassPunch,
        vocalCut: _player.vocalCut,
        crossfeedEnabled: _player.crossfeedEnabled,
        crossfeedLevel: _player.crossfeedLevel,
        nightModeEnabled: _player.nightModeEnabled,
        nightModeAmount: _player.nightModeAmount,
        balance: _player.balance,
        channelMode: _player.channelMode,
        replayGainEnabled: _player.replayGainEnabled,
        replayGainAlbum: _player.replayGainAlbum,
        crossfade: _player.crossfade,
        gapless: _player.gapless,
        speed: _player.speed,
        pitch: _player.pitch,
        soundscape: _player.soundscape,
        soundscapeLevel: _player.soundscapeLevel,
      );

  /// Vuelca unos ajustes al motor con una sola notificación.
  void applyAudioSettings(AudioSettings settings) {
    if (_disposed) return;
    _player.set9D(settings.nineDEnabled, settings.nineDSpeed, settings.nineDDepth);
    _player.setStereoEnhance(settings.stereoWidth, settings.bassPunch);
    _player.setVocalCut(settings.vocalCut);
    _player.setCrossfeed(settings.crossfeedEnabled, settings.crossfeedLevel);
    _player.setNightMode(settings.nightModeEnabled, settings.nightModeAmount);
    _player.setBalance(settings.balance);
    _player.setChannelMode(settings.channelMode);
    _player.setReplayGain(settings.replayGainEnabled);
    _player.setReplayGainAlbum(settings.replayGainAlbum);
    _player.setCrossfade(settings.crossfade);
    _player.setGapless(settings.gapless);
    _player.setSpeed(settings.speed);
    _player.setPitch(settings.pitch);
    _player.setSoundscape(settings.soundscape, level: settings.soundscapeLevel);
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
