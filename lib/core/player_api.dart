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
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(hasTrack, title, artist, album, cover,
      duration, playing, busy, volume, repeatMode, shuffle, queueIndex,
      queueProtected, error);
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
