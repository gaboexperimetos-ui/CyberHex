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


/// Paisajes sonoros del núcleo (`ch_engine_set_soundscape`).
enum SoundscapePreset {
  /// Sin paisaje: coste cero en el hilo de audio.
  off,

  /// Lluvia: paso alto + paso bajo con ráfagas lentas.
  rain,

  /// Ruido marrón: retumbo de graves suave.
  brown,

  /// Vinilo: hiss filtrado con chasquidos.
  vinyl;

  /// Valor que espera el núcleo (0..3).
  int get code => index;

  static SoundscapePreset fromCode(int code) {
    if (code < 0 || code >= values.length) return SoundscapePreset.off;
    return values[code];
  }
}

/// Niveles de salida para vúmetros, medidos después de EQ y limitador.
class PlayerLevels {
  const PlayerLevels({
    this.rmsLeft = 0,
    this.rmsRight = 0,
    this.peakLeft = 0,
    this.peakRight = 0,
  });

  final double rmsLeft;
  final double rmsRight;
  final double peakLeft;
  final double peakRight;

  static const PlayerLevels silent = PlayerLevels();

  /// ¿Todo a cero? (pausa, sin pista o motor antiguo)
  bool get isSilent =>
      rmsLeft <= 0 && rmsRight <= 0 && peakLeft <= 0 && peakRight <= 0;

  @override
  bool operator ==(Object other) =>
      other is PlayerLevels &&
      other.rmsLeft == rmsLeft &&
      other.rmsRight == rmsRight &&
      other.peakLeft == peakLeft &&
      other.peakRight == peakRight;

  @override
  int get hashCode => Object.hash(rmsLeft, rmsRight, peakLeft, peakRight);

  @override
  String toString() => 'PlayerLevels(rms ${rmsLeft.toStringAsFixed(3)}/'
      '${rmsRight.toStringAsFixed(3)}, pico ${peakLeft.toStringAsFixed(3)}/'
      '${peakRight.toStringAsFixed(3)})';
}

/// Marca de posición dentro de una pista (persistente en el núcleo).
class AudioMarker {
  const AudioMarker({required this.position, this.name = ''});

  /// Segundos desde el inicio de la pista.
  final double position;

  /// Nombre opcional («estribillo», «solo»).
  final String name;

  Map<String, Object?> toJson() => <String, Object?>{
        'position': position,
        'name': name,
      };

  static AudioMarker? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final position = raw['position'];
    if (position is! num || !position.isFinite) return null;
    final name = raw['name'];
    return AudioMarker(
      position: position.toDouble(),
      name: name is String ? name : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioMarker && other.position == position && other.name == name;

  @override
  int get hashCode => Object.hash(position, name);

  @override
  String toString() =>
      'AudioMarker(${position.toStringAsFixed(2)} s, "$name")';
}

/// Dispositivo de salida de audio del sistema.
class AudioDevice {
  const AudioDevice({required this.index, required this.name});

  final int index;
  final String name;

  /// El índice `-1` es el dispositivo predeterminado del sistema.
  bool get isDefault => index < 0;

  String get label => name.isEmpty ? 'Salida ${index + 1}' : name;

  @override
  bool operator ==(Object other) =>
      other is AudioDevice && other.index == index && other.name == name;

  @override
  int get hashCode => Object.hash(index, name);

  @override
  String toString() => 'AudioDevice($index, "$name")';
}

/// Una pista de una hoja `.cue` (una imagen de audio dividida en cortes).
class CueTrack {
  const CueTrack({
    required this.file,
    required this.start,
    this.end = -1,
    this.title = '',
    this.performer = '',
    this.number = 0,
  });

  /// Ruta del audio (el `FILE` del `.cue`, ya resuelta).
  final String file;

  /// Inicio en segundos.
  final double start;

  /// Fin en segundos, o `-1` si es el último corte.
  final double end;

  final String title;
  final String performer;

  /// Número de pista tal como figura en el `.cue`.
  final int number;

  double get duration => end > start ? end - start : 0;

  /// Etiqueta para listas: título, y si no hay, nombre del archivo + número.
  String get label {
    if (title.isNotEmpty) return title;
    final name = file.split(RegExp(r'[/\\]')).last;
    return name.isEmpty ? 'Pista $number' : '$name · $number';
  }

  @override
  bool operator ==(Object other) =>
      other is CueTrack &&
      other.file == file &&
      other.start == start &&
      other.end == end &&
      other.title == title &&
      other.performer == performer &&
      other.number == number;

  @override
  int get hashCode => Object.hash(file, start, end, title, performer, number);

  @override
  String toString() => 'CueTrack($number, "$title" @ $start)';
}

/// Silencio al principio y al final de un archivo.
class SilenceTrim {
  const SilenceTrim({this.lead = 0, this.tail = 0});

  /// Segundos de silencio antes del primer sonido.
  final double lead;

  /// Segundos de silencio después del último.
  final double tail;

  @override
  bool operator ==(Object other) =>
      other is SilenceTrim && other.lead == lead && other.tail == tail;

  @override
  int get hashCode => Object.hash(lead, tail);

  @override
  String toString() =>
      'SilenceTrim(inicio ${lead.toStringAsFixed(2)} s, fin ${tail.toStringAsFixed(2)} s)';
}


/// Ajustes de audio que la app guarda entre sesiones.
///
/// Vive aquí (y no en `session_store.dart`) para que el controlador y la sesión
/// compartan el modelo sin importarse en círculo. Todo con valores por defecto
/// sensatos: un JSON viejo, incompleto o absurdo se degrada campo a campo.
class AudioSettings {
  const AudioSettings({
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
    this.balance = 0,
    this.channelMode = 0,
    this.replayGainEnabled = true,
    this.replayGainAlbum = false,
    this.crossfade = 0,
    this.gapless = true,
    this.speed = 1,
    this.pitch = 0,
    this.soundscape = SoundscapePreset.off,
    this.soundscapeLevel = 0,
  });

  final bool nineDEnabled;
  final double nineDSpeed;
  final double nineDDepth;
  final double stereoWidth;
  final double bassPunch;
  final double vocalCut;
  final bool crossfeedEnabled;
  final double crossfeedLevel;
  final bool nightModeEnabled;
  final double nightModeAmount;
  final double balance;
  final int channelMode;
  final bool replayGainEnabled;
  final bool replayGainAlbum;
  final double crossfade;
  final bool gapless;
  final double speed;
  final double pitch;
  final SoundscapePreset soundscape;
  final double soundscapeLevel;

  /// Todo apagado y en el centro: sin DSP, sin coste.
  static const AudioSettings neutral = AudioSettings();

  Map<String, Object?> toJson() => <String, Object?>{
        'nineD': <String, Object?>{
          'on': nineDEnabled,
          'speed': nineDSpeed,
          'depth': nineDDepth,
        },
        'stereo': <String, Object?>{'width': stereoWidth, 'punch': bassPunch},
        'vocalCut': vocalCut,
        'crossfeed': <String, Object?>{
          'on': crossfeedEnabled,
          'level': crossfeedLevel,
        },
        'nightMode': <String, Object?>{
          'on': nightModeEnabled,
          'amount': nightModeAmount,
        },
        'balance': balance,
        'channelMode': channelMode,
        'replayGain': <String, Object?>{
          'on': replayGainEnabled,
          'album': replayGainAlbum,
        },
        'crossfade': crossfade,
        'gapless': gapless,
        'speed': speed,
        'pitch': pitch,
        'soundscape': <String, Object?>{
          'preset': soundscape.name,
          'level': soundscapeLevel,
        },
      };

  factory AudioSettings.fromJson(Object? raw) {
    if (raw is! Map) return neutral;
    double number(Object? value, double fallback) =>
        value is num && value.isFinite ? value.toDouble() : fallback;
    bool flag(Object? value, bool fallback) => value is bool ? value : fallback;
    Map? map(Object? value) => value is Map ? value : null;

    final nineD = map(raw['nineD']);
    final stereo = map(raw['stereo']);
    final crossfeed = map(raw['crossfeed']);
    final night = map(raw['nightMode']);
    final rg = map(raw['replayGain']);
    final landscape = map(raw['soundscape']);

    return AudioSettings(
      nineDEnabled: flag(nineD?['on'], false),
      nineDSpeed: number(nineD?['speed'], 0.15).clamp(0.05, 2.0).toDouble(),
      nineDDepth: number(nineD?['depth'], 0.65).clamp(0.0, 1.0).toDouble(),
      stereoWidth: number(stereo?['width'], 1).clamp(0.0, 2.0).toDouble(),
      bassPunch: number(stereo?['punch'], 0).clamp(0.0, 1.0).toDouble(),
      vocalCut: number(raw['vocalCut'], 0).clamp(0.0, 1.0).toDouble(),
      crossfeedEnabled: flag(crossfeed?['on'], false),
      crossfeedLevel: number(crossfeed?['level'], 0.5).clamp(0.0, 1.0).toDouble(),
      nightModeEnabled: flag(night?['on'], false),
      nightModeAmount: number(night?['amount'], 0.5).clamp(0.0, 1.0).toDouble(),
      balance: number(raw['balance'], 0).clamp(-1.0, 1.0).toDouble(),
      channelMode: number(raw['channelMode'], 0).toInt().clamp(0, 2),
      replayGainEnabled: flag(rg?['on'], true),
      replayGainAlbum: flag(rg?['album'], false),
      crossfade: number(raw['crossfade'], 0).clamp(0.0, 12.0).toDouble(),
      gapless: flag(raw['gapless'], true),
      speed: number(raw['speed'], 1).clamp(0.25, 4.0).toDouble(),
      pitch: number(raw['pitch'], 0).clamp(-12.0, 12.0).toDouble(),
      soundscape: _soundscapeFrom(landscape?['preset']),
      soundscapeLevel:
          number(landscape?['level'], 0).clamp(0.0, 1.0).toDouble(),
    );
  }

  static SoundscapePreset _soundscapeFrom(Object? raw) {
    if (raw is String) {
      for (final preset in SoundscapePreset.values) {
        if (preset.name == raw) return preset;
      }
    } else if (raw is num) {
      return SoundscapePreset.fromCode(raw.toInt());
    }
    return SoundscapePreset.off;
  }

  AudioSettings copyWith({
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
    double? balance,
    int? channelMode,
    bool? replayGainEnabled,
    bool? replayGainAlbum,
    double? crossfade,
    bool? gapless,
    double? speed,
    double? pitch,
    SoundscapePreset? soundscape,
    double? soundscapeLevel,
  }) {
    return AudioSettings(
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
      balance: balance ?? this.balance,
      channelMode: channelMode ?? this.channelMode,
      replayGainEnabled: replayGainEnabled ?? this.replayGainEnabled,
      replayGainAlbum: replayGainAlbum ?? this.replayGainAlbum,
      crossfade: crossfade ?? this.crossfade,
      gapless: gapless ?? this.gapless,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      soundscape: soundscape ?? this.soundscape,
      soundscapeLevel: soundscapeLevel ?? this.soundscapeLevel,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioSettings &&
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
      other.balance == balance &&
      other.channelMode == channelMode &&
      other.replayGainEnabled == replayGainEnabled &&
      other.replayGainAlbum == replayGainAlbum &&
      other.crossfade == crossfade &&
      other.gapless == gapless &&
      other.speed == speed &&
      other.pitch == pitch &&
      other.soundscape == soundscape &&
      other.soundscapeLevel == soundscapeLevel;

  @override
  int get hashCode => Object.hashAll(<Object?>[
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
        balance,
        channelMode,
        replayGainEnabled,
        replayGainAlbum,
        crossfade,
        gapless,
        speed,
        pitch,
        soundscape,
        soundscapeLevel,
      ]);

  @override
  String toString() => 'AudioSettings(9D: $nineDEnabled, ancho: $stereoWidth, '
      'karaoke: $vocalCut, crossfeed: $crossfeedEnabled, noche: $nightModeEnabled, '
      'balance: $balance, paisaje: ${soundscape.name} @ $soundscapeLevel)';
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

  // ---------------------------------------------------------------------
  // Fase 3: medición, mezcla fina y transporte extendido
  // ---------------------------------------------------------------------

  /// Niveles de salida (RMS y pico por canal), medidos post-EQ y post-limitador.
  ///
  /// Se leen a 10-30 Hz desde la UI; en pausa bajan a cero.
  PlayerLevels levels();

  /// Espectro del audio que suena: `bands` valores 0..1 de 20 Hz a 20 kHz
  /// (-80 dB .. 0 dB). Lista vacía si la librería no lo expone.
  List<double> spectrum([int bands = 32]);

  /// Balance estéreo: -1 todo a la izquierda, 0 centro, +1 a la derecha.
  double get balance;
  void setBalance(double value);

  /// Modo de canales: 0 estéreo, 1 mono, 2 canales intercambiados.
  int get channelMode;
  void setChannelMode(int mode);

  /// ReplayGain activado (aplica la ganancia de la pista al abrirla).
  bool get replayGainEnabled;
  void setReplayGain(bool enabled);

  /// Ganancia ReplayGain aplicada a la pista audible, en dB.
  double get replayGainGainDb;

  /// Pico ReplayGain de la pista audible (0..1), para saber si limita.
  double get replayGainPeak;

  /// ReplayGain por álbum (`true`) o por pista (`false`).
  bool get replayGainAlbum;
  void setReplayGainAlbum(bool album);

  /// Velocidad sin cambiar el tono (0.25..4, 1 = normal).
  double get speed;
  void setSpeed(double value);

  /// Tono en semitonos sin cambiar la duración (-12..+12, 0 = normal).
  double get pitch;
  void setPitch(double semitones);

  /// Crossfade entre pistas en segundos (0 = desactivado).
  double get crossfade;
  void setCrossfade(double seconds);

  /// Avance sin silencio entre pistas.
  bool get gapless;
  void setGapless(bool enabled);

  /// Loop A-B en segundos; `end <= start` lo desactiva.
  void setLoop(double start, double end);

  /// Quita el loop A-B.
  void clearLoop();

  double get loopStart;
  double get loopEnd;

  /// ¿Hay un tramo A-B válido ahora mismo?
  bool get loopActive;

  // Marcadores: el núcleo los guarda por ruta de pista en un JSON propio.

  /// Carga los marcadores de un archivo (`ch_markers_load`).
  bool loadMarkers(String path);

  /// Los guarda (`ch_markers_save`).
  bool saveMarkers(String path);

  /// Marcadores de `trackPath`, en orden de posición.
  List<AudioMarker> markersOf(String trackPath);

  /// Añade una marca; devuelve `false` si la posición no es válida.
  bool addMarker(String trackPath, double position, String name);

  bool removeMarker(String trackPath, int index);

  void clearMarkers(String trackPath);

  /// Temporizador de apagado: pausa tras `seconds` con fundido final.
  /// `seconds <= 0` lo cancela.
  void setSleepTimer(double seconds, {double fadeSeconds = 8});

  /// Segundos que faltan para que se apague, o -1 si no hay temporizador.
  double get sleepRemaining;

  /// Silencio al principio y al final de un archivo (dBFS). `null` si no se
  /// pudo analizar.
  Future<SilenceTrim?> detectSilence(String path, {double thresholdDb = -60});

  /// Dispositivos de salida disponibles.
  List<AudioDevice> get outputDevices;

  /// Índice del dispositivo en uso (-1 = predeterminado).
  int get outputDevice;

  /// Cambia de dispositivo en caliente (mantiene la reproducción).
  bool setOutputDevice(int index);

  /// Número de líneas de la letra LRC de la pista audible (0 si no hay).
  int get lyricLineCount;

  /// Línea de letra que toca ahora (cadena vacía si no hay).
  String get currentLyricLine;

  /// Paisaje sonoro bajo la música.
  SoundscapePreset get soundscape;

  /// Nivel del paisaje (0..1).
  double get soundscapeLevel;

  /// Cambia el paisaje y, si se indica, su nivel. Con [SoundscapePreset.off]
  /// el coste en el hilo de audio es cero.
  void setSoundscape(SoundscapePreset preset, {double? level});

  /// Pulso del archivo en BPM (60..200), o 0 si no hay pulso claro.
  /// Analiza como mucho 30 s y corre fuera del hilo de UI.
  Future<double> detectBpm(String path);

  /// Exporta [start, end) a un WAV 48 kHz estéreo S16 con dither TPDF.
  ///
  /// Con [withDsp] aplica el DSP que tenga puesto el motor (EQ, 9D, ancho,
  /// crossfeed, noche, paisaje y balance); sin él exporta plano con la
  /// ganancia ReplayGain y un limitador de seguridad. `end <= start` = hasta el
  /// final. Devuelve `false` si no pudo.
  Future<bool> renderWav(
    String sourcePath,
    String destinationPath, {
    double start = 0,
    double end = 0,
    bool withDsp = true,
  });

  /// Cortes de una hoja `.cue` (rutas resueltas contra su carpeta).
  List<CueTrack> readCue(String path);

  /// Igual que [readCue] pero sobre el texto ya cargado.
  List<CueTrack> parseCue(String text);

  void dispose();
}
