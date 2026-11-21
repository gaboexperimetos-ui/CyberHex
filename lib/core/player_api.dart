import 'dart:typed_data';

/// Evento emitido por el motor nativo (sondeo sin callbacks).
enum PlayerEventKind { state, track, queue, end, sleep, unknown }

class PlayerEvent {
  const PlayerEvent(this.kind, {this.a = 0, this.b = 0, this.value = 0});

  final PlayerEventKind kind;

  /// `state`: 1 reproduciendo / 0 pausa. `track`: índice de pista.
  /// `queue`: número de pistas.
  final int a;

  /// `track`: número de pistas en la cola al cambiar de pista.
  final int b;

  /// Reservado para valores numéricos del evento.
  final double value;

  @override
  String toString() => 'PlayerEvent($kind, a: $a, b: $b, value: $value)';
}

/// Estado visible del reproductor.
///
/// Es inmutable a propósito: el controlador construye una instancia nueva tras
/// cada cambio y solo notifica si `==` da falso, así que la UI no se repinta
/// por un tick de posición ni por un evento irrelevante.
class PlayerSnapshot {
  const PlayerSnapshot({
    this.hasTrack = false,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.cover,
    this.duration = 0,
    this.playing = false,
    this.busy = false,
    this.volume = 1,
    this.repeatMode = 0,
    this.shuffle = false,
    this.error,
  });

  final bool hasTrack;
  final String title;
  final String artist;
  final String album;
  final Uint8List? cover;
  final double duration;
  final bool playing;
  final bool busy;
  final double volume;

  /// Modo de repetición del motor: 0 = apagado, 1 = repetir todo,
  /// 2 = repetir una.
  final int repeatMode;

  /// ¿Reproducción aleatoria activada?
  final bool shuffle;

  final String? error;

  PlayerSnapshot copyWith({
    bool? hasTrack,
    String? title,
    String? artist,
    String? album,
    Uint8List? cover,
    double? duration,
    bool? playing,
    bool? busy,
    double? volume,
    int? repeatMode,
    bool? shuffle,
    String? error,
    bool clearError = false,
  }) {
    return PlayerSnapshot(
      hasTrack: hasTrack ?? this.hasTrack,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      cover: cover ?? this.cover,
      duration: duration ?? this.duration,
      playing: playing ?? this.playing,
      busy: busy ?? this.busy,
      volume: volume ?? this.volume,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffle: shuffle ?? this.shuffle,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PlayerSnapshot &&
        other.hasTrack == hasTrack &&
        other.title == title &&
        other.artist == artist &&
        other.album == album &&
        identical(other.cover, cover) &&
        other.duration == duration &&
        other.playing == playing &&
        other.busy == busy &&
        other.volume == volume &&
        other.repeatMode == repeatMode &&
        other.shuffle == shuffle &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(hasTrack, title, artist, album, cover,
      duration, playing, busy, volume, repeatMode, shuffle, error);
}

/// Superficie que la UI necesita del motor.
///
/// Existe para poder inyectar un doble en las pruebas: `NativePlayer` la
/// implementa contra la `.so` y los tests usan un `FakePlayer` sin FFI.
abstract class PlayerApi {
  bool get hasTrack;
  String get title;
  String get artist;
  String get album;
  Uint8List? get cover;
  double get duration;
  double get position;
  bool get isPlaying;
  String get lastError;

  List<double> get eqGains;
  List<double> get eqBandFrequencies;

  bool load(String path);
  Future<bool> loadAsync(String path);

  /// Relee etiquetas, carátula y duración de la pista audible.
  ///
  /// Hace falta cuando el motor cambia de pista solo (gapless, crossfade,
  /// siguiente automático) sin pasar por [load].
  void syncTrackInfo();

  void play();
  void pause();
  void toggle();

  /// Salta a la pista siguiente de la cola (si la hay).
  void next();

  /// Vuelve a la pista anterior de la cola (si la hay).
  void previous();

  void seek(double seconds);
  void setVolume(double value);

  /// Modo de repetición: 0 = apagado, 1 = repetir todo, 2 = repetir una.
  int get repeatMode;

  /// ¿Reproducción aleatoria activada?
  bool get shuffle;

  void setRepeatMode(int mode);
  void setShuffle(bool enabled);

  /// Cicla el modo de repetición 0 → 1 → 2 → 0.
  void cycleRepeat();

  /// Invierte el modo aleatorio.
  void toggleShuffle();

  void setBand(int index, double db);
  void resetEq();

  /// Siguiente evento del motor, o `null` si no hay ninguno pendiente.
  PlayerEvent? pollEvent();

  void dispose();
}
