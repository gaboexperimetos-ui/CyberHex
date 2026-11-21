import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

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
  });

  /// Versión del formato; sube si cambia el significado de algún campo.
  static const int formatVersion = 1;

  final List<String> queue;
  final int queueIndex;
  final double position;
  final double volume;
  final int repeatMode;
  final bool shuffle;

  bool get isEmpty => queue.isEmpty && queueIndex < 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': formatVersion,
        'queue': queue,
        'queueIndex': queueIndex,
        'position': position,
        'volume': volume,
        'repeatMode': repeatMode,
        'shuffle': shuffle,
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
      listEquals(other.queue, queue);

  @override
  int get hashCode => Object.hash(queueIndex, position, volume, repeatMode,
      shuffle, Object.hashAll(queue));

  @override
  String toString() =>
      'SessionSnapshot(${queue.length} pistas, índice $queueIndex, '
      '${position.toStringAsFixed(1)} s)';
}

/// Persiste la sesión en un JSON pequeño con escritura atómica.
///
/// `save` escribe primero `<archivo>.tmp` y luego renombra: un corte de luz a
/// mitad deja el archivo anterior intacto, nunca uno a medias.
///
/// Nunca lanza: si el directorio no se puede escribir (permisos, sandbox), se
/// avisa una vez por consola y la app sigue funcionando sin sesión.
class SessionStore {
  SessionStore({File? file}) : file = file ?? File(_defaultPath());

  final File file;

  bool _warned = false;

  /// Directorio de datos:
  ///  * `CYBERHEX_DATA_DIR` si está definido (útil en tests y para empaquetar);
  ///  * Linux/macOS: `$XDG_CONFIG_HOME/cyberhex` o `~/.config/cyberhex`;
  ///  * Windows: `%APPDATA%\CyberHex`;
  ///  * resto (Android): el temporal del sistema.
  ///
  /// En Android puro en Dart no hay forma de llegar al directorio privado de la
  /// app (`getFilesDir()`) sin un canal nativo o `path_provider`; ver R14 en
  /// docs/INFORME.md.
  static String _defaultPath() => '${defaultDirectory().path}/session.json';

  static Directory defaultDirectory() {
    final override = Platform.environment['CYBERHEX_DATA_DIR'];
    if (override != null && override.isNotEmpty) return Directory(override);
    if (Platform.isLinux || Platform.isMacOS) {
      final xdg = Platform.environment['XDG_CONFIG_HOME'];
      if (xdg != null && xdg.isNotEmpty) return Directory('$xdg/cyberhex');
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory('$home/.config/cyberhex');
      }
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory('$appData\\CyberHex');
      }
    }
    return Directory('${Directory.systemTemp.path}/cyberhex');
  }

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
    // Si había algo programado, se escribe ahora: cerrar la app no debe perder
    // la pista en la que ibas.
    if (pending) {
      await saveNow();
    }
    _disposed = true;
  }
}
