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

/// Quita la carpeta y la extensión de una ruta, para usarla como título cuando
/// el motor todavía no tiene etiquetas de esa pista (cola y biblioteca solo dan
/// rutas: no hay `ch_engine_queue_path` que devuelva tags).
String titleFromPath(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Extensión sin punto y en minúsculas (`flac`, `mp3`...). Cadena vacía si no
/// hay punto.
String extensionOf(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1).toLowerCase();
}

/// Una entrada de la cola de reproducción.
///
/// Inmutable a propósito: la UI compara listas por contenido y necesita que dos
/// lecturas iguales no provoquen repintados.
class QueueItem {
  const QueueItem({required this.path, required this.title, this.artist = ''});

  /// Ruta real del archivo. Vacía si el motor tiene una pista que este lado no
  /// conoce (por ejemplo una cola importada por fuera de la app).
  final String path;

  /// Etiqueta legible: del tag si es la pista audible, si no del nombre.
  final String title;

  /// Artista, solo conocido para la pista que suena.
  final String artist;

  bool get isPlayable => path.isNotEmpty;

  QueueItem copyWith({String? path, String? title, String? artist}) {
    return QueueItem(
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QueueItem &&
      other.path == path &&
      other.title == title &&
      other.artist == artist;

  @override
  int get hashCode => Object.hash(path, title, artist);

  @override
  String toString() => 'QueueItem($title · $path)';
}

/// Una pista encontrada por el escáner de biblioteca del núcleo.
///
/// `ch_library_*` devuelve rutas, no etiquetas: el título sale del nombre y la
/// duración solo se conoce cuando la pista se abre.
class LibraryTrack {
  const LibraryTrack({
    required this.path,
    required this.title,
    required this.extension,
  });

  factory LibraryTrack.fromPath(String path) {
    return LibraryTrack(
      path: path,
      title: titleFromPath(path),
      extension: extensionOf(path),
    );
  }

  final String path;
  final String title;

  /// Sin punto, en minúsculas.
  final String extension;

  /// Carpeta contenedora (para la pestaña "Carpetas").
  String get directory {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut <= 0 ? path : path.substring(0, cut);
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryTrack &&
      other.path == path &&
      other.title == title &&
      other.extension == extension;

  @override
  int get hashCode => Object.hash(path, title, extension);

  @override
  String toString() => 'LibraryTrack($title.$extension)';
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
    this.queue = const <QueueItem>[],
    this.queueIndex = -1,
    this.queueProtected = false,
    this.nineDEnabled = false,
    this.nineDSpeed = 0.15,
    this.nineDDepth = 0.65,
    this.stereoWidth = 1,
    this.bassPunch = 0,
    this.vocalCut = 0,
    this.crossfeedEnabled = false,
    this.crossfeedLevel = 0.5,
    this.nightModeEnabled = false,
    this.nightModeAmount = 0.5,
    this.s16Output = false,
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

  /// Copia inmutable de la cola. Se reemplaza entera cuando cambia, así que la
  /// igualdad de snapshots puede compararla por identidad.
  final List<QueueItem> queue;

  /// Índice audible dentro de [queue], o -1.
  final int queueIndex;

  /// Con la cola protegida, abrir un archivo suelto lo añade sin vaciar la cola.
  final bool queueProtected;

  // --- Fase 2: núcleo DSP audiófilo (todo del motor, nada inventado aquí) ---

  /// Audio 9D espacial: giro azimutal continuo para auriculares.
  final bool nineDEnabled;

  /// Vueltas por segundo del 9D (0.05 .. 2.0).
  final double nineDSpeed;

  /// Profundidad del 9D (0 = apagado de hecho, 1 = giro completo).
  final double nineDDepth;

  /// Ancho estéreo por matriz Mid/Side: 0 = mono, 1 = natural, 2 = ultra.
  final double stereoWidth;

  /// Realce armónico de graves (0 .. 1).
  final double bassPunch;

  /// Modo karaoke: atenuación del centro por encima de ~130 Hz (0 .. 1).
  final double vocalCut;

  /// Crossfeed Bauer para auriculares.
  final bool crossfeedEnabled;

  /// Cantidad de alimentación cruzada (0 .. 1).
  final double crossfeedLevel;

  /// Compresor de modo noche.
  final bool nightModeEnabled;

  /// Cantidad de compresión del modo noche (0 .. 1).
  final double nightModeAmount;

  /// Salida S16 con dither TPDF (si está apagada se entrega f32).
  final bool s16Output;

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
    List<QueueItem>? queue,
    int? queueIndex,
    bool? queueProtected,
    bool? nineDEnabled,
    double? nineDSpeed,
    double? nineDDepth,
    double? stereoWidth,
    double? bassPunch,
    double? vocalCut,
    bool? crossfeedEnabled,
    double? crossfeedLevel,
    bool? nightModeEnabled,
    double? nightModeAmount,
    bool? s16Output,
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
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      queueProtected: queueProtected ?? this.queueProtected,
      nineDEnabled: nineDEnabled ?? this.nineDEnabled,
      nineDSpeed: nineDSpeed ?? this.nineDSpeed,
      nineDDepth: nineDDepth ?? this.nineDDepth,
      stereoWidth: stereoWidth ?? this.stereoWidth,
      bassPunch: bassPunch ?? this.bassPunch,
      vocalCut: vocalCut ?? this.vocalCut,
      crossfeedEnabled: crossfeedEnabled ?? this.crossfeedEnabled,
      crossfeedLevel: crossfeedLevel ?? this.crossfeedLevel,
      nightModeEnabled: nightModeEnabled ?? this.nightModeEnabled,
      nightModeAmount: nightModeAmount ?? this.nightModeAmount,
      s16Output: s16Output ?? this.s16Output,
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
        identical(other.queue, queue) &&
        other.queueIndex == queueIndex &&
        other.queueProtected == queueProtected &&
        other.nineDEnabled == nineDEnabled &&
        other.nineDSpeed == nineDSpeed &&
        other.nineDDepth == nineDDepth &&
        other.stereoWidth == stereoWidth &&
        other.bassPunch == bassPunch &&
        other.vocalCut == vocalCut &&
        other.crossfeedEnabled == crossfeedEnabled &&
        other.crossfeedLevel == crossfeedLevel &&
        other.nightModeEnabled == nightModeEnabled &&
        other.nightModeAmount == nightModeAmount &&
        other.s16Output == s16Output &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        hasTrack,
        title,
        artist,
        album,
        cover,
        duration,
        playing,
        busy,
        volume,
        repeatMode,
        shuffle,
        queueIndex,
        queueProtected,
        nineDEnabled,
        nineDSpeed,
        nineDDepth,
        stereoWidth,
        bassPunch,
        vocalCut,
        crossfeedEnabled,
        crossfeedLevel,
        nightModeEnabled,
        nightModeAmount,
        s16Output,
        error,
      ]);
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

  // ---------------------------------------------------------------------
  // Fase 2: núcleo DSP audiófilo
  // ---------------------------------------------------------------------

  /// Audio 9D espacial: `speedHz` vueltas por segundo (0.05..2) y `depth` 0..1.
  void set9D(bool enabled, double speedHz, double depth);

  bool get nineDEnabled;

  /// Vueltas por segundo del giro azimutal.
  double get nineDSpeed;

  double get nineDDepth;

  /// Potenciador estéreo: ancho Mid/Side (0..2) y punch de graves (0..1).
  void setStereoEnhance(double width, double bassPunch);

  void setStereoWidth(double width);

  double get stereoWidth;

  double get bassPunch;

  /// Modo karaoke: atenúa el centro por encima de ~130 Hz (0 apagado, 1 fuera).
  void setVocalCut(double amount);

  double get vocalCut;

  /// Crossfeed Bauer para auriculares: `level` 0..1.
  void setCrossfeed(bool enabled, double level);

  bool get crossfeedEnabled;

  double get crossfeedLevel;

  /// Compresor de modo noche: `amount` 0..1.
  void setNightMode(bool enabled, double amount);

  bool get nightModeEnabled;

  double get nightModeAmount;

  /// Salida S16 con dither TPDF (por defecto se entrega f32).
  void setS16Output(bool enabled);

  bool get s16Output;

  // ---------------------------------------------------------------------
  // Cola de reproducción
  // ---------------------------------------------------------------------

  /// Número de pistas en la cola, según el motor.
  int get queueLength;

  /// Índice audible actual, o -1 si no hay ninguna pista sonando.
  int get queueIndex;

  /// Copia inmutable de la cola, en el orden del motor.
  List<QueueItem> get queueItems;

  /// Reproduce la pista `index` de la cola **sin vaciarla**.
  bool playAt(int index);

  /// Añade al final de la cola sin cambiar lo que suena.
  bool enqueue(String path);

  /// Inserta justo después de la pista actual (o al final si no hay).
  bool playNext(String path);

  /// Añade al final y reproduce (la cola se conserva). Es el "abrir con cola
  /// protegida"; en el núcleo es `ch_engine_load_add`.
  Future<bool> loadAndPlayAsync(String path);

  /// Mueve la pista `from` a la posición `to` sin cortar el audio.
  bool moveQueueItem(int from, int to);

  /// Quita la pista `index`; si era la que sonaba, el motor sigue con la
  /// siguiente.
  bool removeQueueItem(int index);

  /// Vacía la cola y detiene la reproducción.
  void clearQueue();

  /// Importa un M3U/M3U8/PLS y devuelve cuántas pistas añadió.
  int importQueue(String playlistPath);

  /// Exporta la cola como M3U8.
  bool exportQueue(String playlistPath);

  // ---------------------------------------------------------------------
  // Biblioteca
  // ---------------------------------------------------------------------

  /// Escanea `root` de forma recursiva y devuelve las pistas de audio.
  Future<List<LibraryTrack>> scanDirectory(String root);

  /// Pistas que el último escaneo dio por desaparecidas.
  int get libraryRemoved;

  void setBand(int index, double db);
  void resetEq();

  /// Siguiente evento del motor, o `null` si no hay ninguno pendiente.
  PlayerEvent? pollEvent();

  void dispose();
}
