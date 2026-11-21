import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'player_api.dart';
import 'player_controller.dart';

/// Foto de la sesión: qué había en la cola, por dónde iba y con qué ajustes.
///
/// Todo inmutable y serializable a JSON plano, para poder inspeccionar el
/// archivo a mano si algo sale mal.
class SessionSnapshot {
  const SessionSnapshot({
    this.queue = const <String>[],
    this.queueIndex = -1,
    this.position = 0,
    this.volume = 1,
    this.repeatMode = 0,
    this.shuffle = false,
    this.audio = AudioSettings.neutral,
  });

  /// Versión del formato; sube si cambia el significado de algún campo.
  ///
  /// 2: la sesión guarda además los ajustes de audio (DSP, balance, paisaje...).
  static const int formatVersion = 2;

  final List<String> queue;
  final int queueIndex;
  final double position;
  final double volume;
  final int repeatMode;
  final bool shuffle;

  /// Ajustes de audio que se restauran al arrancar (decisión del arquitecto:
  /// el DSP se persiste aquí, no en el estado del motor).
  final AudioSettings audio;

  bool get isEmpty => queue.isEmpty && queueIndex < 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': formatVersion,
        'queue': queue,
        'queueIndex': queueIndex,
        'position': position,
        'volume': volume,
        'repeatMode': repeatMode,
        'shuffle': shuffle,
        'audio': audio.toJson(),
      };

  /// Nunca lanza y nunca devuelve algo incoherente: un JSON de otra versión, con
  /// tipos raros o con el índice fuera de la cola se degrada a valores seguros.
  factory SessionSnapshot.fromJson(Map<String, Object?> json) {
    final paths = <String>[];
    final rawQueue = json['queue'];
    if (rawQueue is List) {
      for (final entry in rawQueue) {
        if (entry is String && entry.isNotEmpty) paths.add(entry);
      }
    }

    final rawIndex = json['queueIndex'];
    final index = rawIndex is num ? rawIndex.toInt() : -1;
    final rawRepeat = json['repeatMode'];
    final repeat = rawRepeat is num ? rawRepeat.toInt() : 0;

    return SessionSnapshot(
      queue: List<String>.unmodifiable(paths),
      queueIndex: index >= 0 && index < paths.length ? index : -1,
      position: _double(json['position'], 0),
      volume: _double(json['volume'], 1).clamp(0.0, 1.0).toDouble(),
      repeatMode: repeat < 0 ? 0 : (repeat > 2 ? 2 : repeat),
      shuffle: json['shuffle'] == true,
      // Una sesión de la versión 1 no trae audio: quedan los valores neutros.
      audio: AudioSettings.fromJson(json['audio']),
    );
  }

  static double _double(Object? value, double fallback) {
    if (value is num && value.isFinite) return value.toDouble();
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is SessionSnapshot &&
      other.queueIndex == queueIndex &&
      other.position == position &&
      other.volume == volume &&
      other.repeatMode == repeatMode &&
      other.shuffle == shuffle &&
      other.audio == audio &&
      listEquals(other.queue, queue);

  @override
  int get hashCode => Object.hash(queueIndex, position, volume, repeatMode,
      shuffle, audio, Object.hashAll(queue));

  @override
  String toString() =>
      'SessionSnapshot(${queue.length} pistas, índice $queueIndex, '
      '${position.toStringAsFixed(1)} s)';
}

/// Directorio persistente de datos de la app (sesión, favoritos, ajustes).
///
/// Prioridad:
///  1. `CYBERHEX_DATA_DIR` (pruebas, empaquetado, usuarios avanzados);
///  2. Android: canal `cyberhex/storage` → `context.filesDir`, que **no** se
///     borra como el caché (R14);
///  3. Linux/macOS: `$XDG_DATA_HOME/cyberhex` o `~/.local/share/cyberhex`;
///  4. Windows: `%APPDATA%\CyberHex`;
///  5. resto: `<temporal>/cyberhex`, para no fallar nunca.
///
/// [prepare] se llama una vez en `main()`, antes de montar la UI, porque el
/// canal de Android es asíncrono y el resto de la app construye sus almacenes
/// con constructores síncronos.
class StorageDirectory {
  static const MethodChannel _channel = MethodChannel('cyberhex/storage');

  static Directory? _cached;
  static Future<Directory>? _pending;

  /// Directorio ya resuelto. Si nadie llamó a [prepare], se resuelve en el acto
  /// por la vía síncrona (escritorio o temporal) y **no** se crea nada aquí:
  /// crear directorios es cosa de [prepare] y de los `save()`.
  static Directory get current => _cached ??= resolve(
        environment: Platform.environment,
        tempPath: Directory.systemTemp.path,
        windows: Platform.isWindows,
      );

  /// Resuelve (y crea) el directorio de datos. Idempotente y sin excepciones.
  static Future<Directory> prepare() {
    return _pending ??= _prepare();
  }

  static Future<Directory> _prepare() async {
    var directory = await _platformDirectory() ?? current;
    directory = await ensure(directory);
    _cached = directory;
    return directory;
  }

  /// En Android pregunta al canal; en el resto de plataformas devuelve `null`
  /// para que decida [resolve]. Un canal ausente o con error no es un fallo:
  /// simplemente no hay `filesDir` al que ir.
  static Future<Directory?> _platformDirectory() async {
    if (!Platform.isAndroid) return null;
    try {
      final path = await _channel.invokeMethod<String>('getAppDataDir');
      if (path != null && path.isNotEmpty) return Directory(path);
    } on MissingPluginException {
      debugPrint('StorageDirectory: sin canal nativo, se usa el temporal');
    } on PlatformException catch (error) {
      debugPrint('StorageDirectory: el canal falló ($error)');
    }
    return null;
  }

  /// Crea `directory` si hace falta. Si no se puede, devuelve el temporal.
  static Future<Directory> ensure(Directory directory) async {
    try {
      if (!directory.existsSync()) directory.createSync(recursive: true);
      return directory;
    } catch (error) {
      debugPrint('StorageDirectory: no se pudo crear ${directory.path} ($error)');
      final fallback = Directory('${Directory.systemTemp.path}/cyberhex');
      try {
        if (!fallback.existsSync()) fallback.createSync(recursive: true);
      } catch (_) {
        // Si ni el temporal se puede crear, se devuelve igual: los `save()`
        // fallarán sin romper nada.
      }
      return fallback;
    }
  }

  /// Resolución por entorno, sin tocar el disco. Pura a propósito: así se puede
  /// probar con cualquier combinación de variables y plataforma.
  static Directory resolve({
    required Map<String, String> environment,
    required String tempPath,
    required bool windows,
  }) {
    final override = environment['CYBERHEX_DATA_DIR'];
    if (override != null && override.isNotEmpty) return Directory(override);
    if (windows) {
      final appData = environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory('$appData\\CyberHex');
      }
    } else {
      final xdg = environment['XDG_DATA_HOME'];
      if (xdg != null && xdg.isNotEmpty) return Directory('$xdg/cyberhex');
      final home = environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/.local/share/cyberhex');
      }
    }
    return Directory('$tempPath/cyberhex');
  }
}

/// Persiste la sesión en un JSON pequeño con escritura atómica.
///
/// `save` escribe primero `<archivo>.tmp` y luego renombra: un corte de luz a
/// mitad deja el archivo anterior intacto, nunca uno a medias.
///
/// Nunca lanza: si el directorio no se puede escribir (permisos, sandbox), se
/// avisa una vez por consola y la app sigue funcionando sin sesión.
class SessionStore {
  SessionStore({File? file})
      : file = file ?? File('${StorageDirectory.current.path}/session.json');

  /// Lee la sesión. `null` si no hay archivo, está vacío o está corrupto.
  Future<SessionSnapshot?> load() async {
    try {
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final snapshot = SessionSnapshot.fromJson(decoded);
      return snapshot.isEmpty ? null : snapshot;
    } catch (error) {
      debugPrint('SessionStore: sesión ilegible, se ignora ($error)');
      return null;
    }
  }

  /// Guarda la sesión. Devuelve `false` si no se pudo escribir.
  Future<bool> save(SessionSnapshot snapshot) async {
    File? temp;
    try {
      final directory = file.parent;
      if (!directory.existsSync()) directory.createSync(recursive: true);
      temp = File('${file.path}.tmp');
      // flush: true baja el contenido a disco antes del rename.
      await temp.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await temp.rename(file.path);
      return true;
    } catch (error) {
      if (!_warned) {
        _warned = true;
        debugPrint('SessionStore: no se pudo guardar la sesión ($error)');
      }
      // Un .tmp huérfano no debe quedarse por ahí.
      try {
        if (temp != null && temp.existsSync()) temp.deleteSync();
      } catch (_) {
        // Si ni esto funciona, no hay nada más que hacer.
      }
      return false;
    }
  }

  Future<bool> clear() async {
    try {
      if (file.existsSync()) file.deleteSync();
      return true;
    } catch (error) {
      debugPrint('SessionStore: no se pudo borrar la sesión ($error)');
      return false;
    }
  }
}

/// Une un [PlayerController] con un [SessionStore]: restaura al arrancar y
/// guarda cuando la reproducción se pausa o cambia de pista (con antirrebote,
/// porque el controlador avisa varias veces por segundo).
class SessionKeeper {
  SessionKeeper({required this.controller, SessionStore? store})
      : store = store ?? SessionStore();

  final PlayerController controller;
  final SessionStore store;

  static const Duration _saveDelay = Duration(milliseconds: 600);

  Timer? _saveTimer;
  bool _restored = false;
  bool _disposed = false;

  // Lo último que se guardó, para no reescribir el archivo sin motivo.
  bool? _lastPlaying;
  int? _lastQueueIndex;
  String? _lastTitle;

  /// Restaura la sesión anterior. No bloquea el arranque: si el archivo no está
  /// o está roto, se sigue con lo que haya.
  Future<void> restore() async {
    if (_disposed || _restored) return;
    _restored = true;

    try {
      final session = await store.load();
      if (session == null || _disposed) return;

      // Ajustes primero: son baratos y no dependen de abrir archivos.
      controller.setVolume(session.volume);
      controller.setRepeatMode(session.repeatMode);
      controller.setShuffle(session.shuffle);
      controller.applyAudioSettings(session.audio);

      if (session.queue.isEmpty) return;
      for (final path in session.queue) {
        controller.enqueue(path);
      }

      final index = session.queueIndex;
      if (index >= 0 && index < session.queue.length) {
        // playAt abre el decodificador; se pausa en el acto para no soltar
        // audio solo por abrir la app, y luego se recoloca la posición.
        controller.playAt(index);
        controller.pause();
        if (session.position > 0) controller.seek(session.position);
      }
    } finally {
      // Se escucha tanto si había sesión como si no: el primer guardado debe
      // cubrir también una cola que el usuario monte desde cero.
      if (!_disposed) listen();
    }
  }

  /// Se llama cuando ya se restauró (o no había nada): a partir de aquí se
  /// escucha al controlador.
  void listen() {
    if (_disposed) return;
    controller.removeListener(_onControllerChanged);
    controller.addListener(_onControllerChanged);
    controller.removeAudioListener(_onAudioChanged);
    controller.addAudioListener(_onAudioChanged);
    _rememberCurrent();
  }

  void _rememberCurrent() {
    final snapshot = controller.snapshot;
    _lastPlaying = snapshot.playing;
    _lastQueueIndex = snapshot.queueIndex;
    _lastTitle = snapshot.title;
  }

  void _onControllerChanged() {
    if (_disposed) return;
    final snapshot = controller.snapshot;
    final trackChanged = snapshot.queueIndex != _lastQueueIndex ||
        snapshot.title != _lastTitle;
    final paused = !snapshot.playing && (_lastPlaying ?? false);

    _lastPlaying = snapshot.playing;
    _lastQueueIndex = snapshot.queueIndex;
    _lastTitle = snapshot.title;

    if (trackChanged || paused) _scheduleSave();
  }

  /// Un cambio de DSP o de mezcla se guarda con el mismo antirrebote que un
  /// cambio de pista: la UI avisa muchas veces mientras se arrastra un mando.
  void _onAudioChanged() {
    if (_disposed) return;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, saveNow);
  }

  /// Escribe la sesión ya mismo. También la llama `dispose()`.
  Future<bool> saveNow() async {
    if (_disposed) return false;
    _saveTimer?.cancel();
    _saveTimer = null;
    final snapshot = controller.snapshot;
    // Las pistas sin ruta (cola que el motor conoce y esta capa no) no se
    // guardan; el índice se recoloca para que siga apuntando a la misma.
    final paths = <String>[];
    var index = -1;
    for (var i = 0; i < snapshot.queue.length; i++) {
      final item = snapshot.queue[i];
      if (!item.isPlayable) continue;
      if (i == snapshot.queueIndex) index = paths.length;
      paths.add(item.path);
    }
    final session = SessionSnapshot(
      queue: List<String>.unmodifiable(paths),
      queueIndex: index,
      position: controller.position.value,
      volume: snapshot.volume,
      repeatMode: snapshot.repeatMode,
      shuffle: snapshot.shuffle,
      audio: controller.audioSettings(),
    );
    return store.save(session);
  }

  /// Guarda el estado final y suelta el controlador.
  Future<void> dispose() async {
    if (_disposed) return;
    final pending = _saveTimer != null;
    _saveTimer?.cancel();
    _saveTimer = null;
    controller.removeListener(_onControllerChanged);
    controller.removeAudioListener(_onAudioChanged);
    // Si había algo programado, se escribe ahora: cerrar la app no debe perder
    // la pista en la que ibas.
    if (pending) {
      await saveNow();
    }
    _disposed = true;
  }
}
