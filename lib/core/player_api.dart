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

/// Marca de posición persistente de una pista.
class TrackMarker {
  const TrackMarker(this.position, this.name);

  final double position;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is TrackMarker && other.position == position && other.name == name;

  @override
  int get hashCode => Object.hash(position, name);

  @override
  String toString() => 'TrackMarker($position, $name)';
}

/// Una pista dentro de una hoja CUE.
class CueTrack {
  const CueTrack({
    required this.number,
    required this.title,
    required this.performer,
    required this.file,
    required this.start,
    required this.end,
  });

  final int number;
  final String title;
  final String performer;
  final String file;
  final double start;
  final double end;

  double get duration => end - start;
}

/// Hoja CUE leída de disco: una imagen de audio dividida en pistas.
class CueSheet {
  const CueSheet({
    required this.album,
    required this.albumPerformer,
    required this.tracks,
  });

  final String album;
  final String albumPerformer;
  final List<CueTrack> tracks;
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
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(hasTrack, title, artist, album, cover,
      duration, playing, busy, volume, error);
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

  void setBand(int index, double db);
  void resetEq();

  // ---------------------------------------------------------------------------
  // Cola y modos de reproducción
  //
  // Todos los miembros nuevos tienen implementación por defecto: así un doble
  // de pruebas, o un núcleo antiguo, no obligan a implementar 30 métodos para
  // compilar y las funciones no disponibles simplemente no hacen nada.
  // ---------------------------------------------------------------------------

  /// Pistas en la cola.
  int get queueCount => 0;

  /// Índice de la pista que suena dentro de la cola.
  int get queueIndex => 0;

  /// Reproduce la pista `index` de la cola sin vaciarla.
  bool playIndex(int index) => false;

  /// Añade la pista al final de la cola y la reproduce.
  bool loadAdd(String path) => false;

  /// Añade la pista al final de la cola sin cambiar la que suena.
  bool queueAdd(String path) => false;

  /// Inserta la pista en la posición `index` de la cola.
  bool queueInsert(int index, String path) => false;

  bool queueMove(int from, int to) => false;
  bool queueRemove(int index) => false;
  bool queueClear() => false;

  /// Importa una lista M3U/M3U8/PLS. Devuelve cuántas pistas añadió o -1.
  int queueImport(String path) => -1;

  /// Exporta la cola como M3U8.
  bool queueExport(String path) => false;

  /// 0 = apagada, 1 = toda la cola, 2 = pista actual.
  int get repeatMode => 0;
  set repeatMode(int mode) {}

  bool get shuffle => false;
  set shuffle(bool enabled) {}

  /// Semilla del orden aleatorio: la misma semilla da el mismo orden.
  void setShuffleSeed(int seed) {}

  /// Precarga la pista siguiente para que no haya hueco entre pistas.
  bool get gapless => false;
  set gapless(bool enabled) {}

  /// Segundos de cruce entre pistas (0 = sin crossfade).
  double get crossfadeSeconds => 0;
  set crossfadeSeconds(double seconds) {}

  /// Velocidad sin cambiar el tono: 0.25 – 4.0 (1 = normal).
  double get speed => 1;
  set speed(double value) {}

  /// Tono en semitonos sin cambiar la duración: -12 – +12.
  double get pitch => 0;
  set pitch(double value) {}

  /// Pausa la reproducción tras `seconds` con un fundido de `fadeSeconds`.
  /// `seconds <= 0` lo desactiva.
  void setSleepTimer(double seconds, {double fadeSeconds = 5}) {}

  /// Segundos que faltan del temporizador, o -1 si no hay ninguno activo.
  double get sleepRemaining => -1;

  /// Guarda cola, pista, posición y ajustes en un archivo.
  bool saveState(String path) => false;

  /// Restaura el estado guardado y devuelve la posición a la que saltar.
  double? loadState(String path) => null;

  // ---------------------------------------------------------------------------
  // Metadatos completos, letras y carátulas
  // ---------------------------------------------------------------------------

  /// Año/fecha de la pista ("" si no existe).
  String get date => '';

  String get genre => '';

  String get composer => '';

  /// Número de pista dentro del disco (0 si no existe).
  int get trackNumber => 0;

  int get discNumber => 0;

  /// Etiqueta arbitraria del archivo, p. ej. `tag('BPM')`.
  String tag(String key) => '';

  /// Frecuencia de muestreo que reporta el decodificador.
  int get sampleRate => 0;

  /// Canales de la pista abierta.
  int get channels => 2;

  /// Guarda la carátula `index` del archivo actual en `path` (JPEG/PNG).
  bool saveCover(int index, String path) => false;

  /// Líneas de letra sincronizada (LRC) de la pista actual.
  int get lyricsCount => 0;

  /// Línea de letra que corresponde a la posición actual ("" si no hay).
  String get activeLyricLine => '';

  // ---------------------------------------------------------------------------
  // Medición y DSP
  // ---------------------------------------------------------------------------

  /// RMS y pico por canal: `[rmsL, rmsR, peakL, peakR]` (0..1).
  List<double> get levels => const [];

  /// Picos en dBFS: `[peakL, peakR, rms]`.
  List<double> get meterLevels => const [];

  /// Espectro logarítmico de 20 Hz a 20 kHz: `bands` valores (0..1).
  List<double> spectrum(int bands) => const [];

  /// Preamp del EQ en dB (0 a -24, nunca amplifica).
  double get eqPreamp => 0;
  set eqPreamp(double db) {}

  /// Cambia una sola banda del EQ conservando las demás.
  bool setBandGain(int band, double db) => false;

  void setLimiter(bool enabled, {double ceilingDb = -1}) {}
  bool get limiter => false;

  void setCrossfeed(bool enabled, {double strength = 0.5}) {}
  ({bool enabled, double strength}) get crossfeed =>
      (enabled: false, strength: 0);

  /// Ganancia manual en dB (-24 a +24).
  double get gainDb => 0;
  set gainDb(double db) {}

  /// Ancho estéreo: 0 (mono) a 2 (doble).
  double get stereoWidth => 1;
  set stereoWidth(double width) {}

  void setTrimSilence(bool enabled, {double thresholdDb = -60}) {}
  ({bool enabled, double thresholdDb}) get trimSilence =>
      (enabled: false, thresholdDb: -60);

  void setReplayGain(bool enabled) {}
  double get replayGainGainDb => 0;
  double get replayGainPeak => 0;

  void setMono(bool enabled) {}
  bool get mono => false;

  /// Bucle A-B dentro de la pista actual.
  void setAbLoop(double start, double end) {}
  void clearAbLoop() {}
  ({double start, double end}) get abLoop => (start: -1, end: -1);

  /// Sonoridad integrada (LUFS) y pico del archivo actual.
  ({double lufs, double peakDb})? analyzeCurrent() => null;

  /// Normaliza la pista actual a `targetLufs`; devuelve los dB aplicados.
  double? normalizeCurrent(double targetLufs) => null;

  /// Audio decodificado por delante de la posición (segundos).
  double get bufferedSeconds => 0;

  /// Veces que el hilo de audio se quedó sin datos.
  int get bufferUnderflows => 0;

  /// Silencio al principio y al final de un archivo (dBFS).
  ({double lead, double tail})? detectSilence(
          String path, {double thresholdDb = -60}) =>
      null;

  // ---------------------------------------------------------------------------
  // Biblioteca, marcadores, CUE y utilidades de archivo
  // ---------------------------------------------------------------------------

  /// Escanea `root` en busca de audio. Devuelve las rutas encontradas y cuántas
  /// desaparecieron respecto al escaneo anterior, o `null` si falla.
  ({List<String> tracks, int removed})? scanLibrary(String root) => null;

  /// Marcas guardadas para `track` en el archivo `path`.
  List<TrackMarker> loadMarkers(String path, String track) => const [];

  /// Reemplaza las marcas de `track` y guarda el archivo.
  bool saveMarkers(String path, String track, List<TrackMarker> markers) =>
      false;

  bool removeMarker(String path, String track, int index) => false;

  bool clearMarkers(String path, String track) => false;

  /// Lee una hoja CUE (una imagen dividida en pistas).
  CueSheet? readCue(String path) => null;

  /// Nombres de los dispositivos de salida del sistema.
  List<String> get outputDevices => const [];

  /// Dispositivo en uso (-1 = predeterminado del sistema).
  int get outputDevice => -1;
  set outputDevice(int index) {}

  /// Sonoridad integrada (LUFS), pico de muestra y duración de un archivo.
  ({double lufs, double peakDb, double duration})? scanLoudness(String path) =>
      null;

  /// Picos normalizados para dibujar la forma de onda (`buckets` valores).
  List<double> waveform(String path, int buckets) => const [];

  /// Versión del núcleo cargado.
  String get coreVersion => '';

  /// Siguiente evento del motor, o `null` si no hay ninguno pendiente.
  PlayerEvent? pollEvent();

  void dispose();
}
