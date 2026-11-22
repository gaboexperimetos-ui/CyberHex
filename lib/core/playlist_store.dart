import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// Una lista de reproducción: nombre y rutas, nada más.
///
/// Las **listas inteligentes** son [Playlist] normales con [smart] a `true` y un
/// [id] con prefijo `smart:`: se recalculan al abrir, no se guardan ni se editan.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.paths = const <String>[],
    this.updated,
    this.smart = false,
  });

  final String id;
  final String name;
  final List<String> paths;
  final DateTime? updated;

  /// ¿Es una lista calculada (Top 25, nunca escuchadas…)?
  final bool smart;

  int get length => paths.length;

  bool get isEmpty => paths.isEmpty;

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? paths,
    DateTime? updated,
    bool? smart,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      paths: paths ?? this.paths,
      updated: updated ?? this.updated,
      smart: smart ?? this.smart,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'paths': paths,
        if (updated != null) 'updated': updated!.toIso8601String(),
      };

  static Playlist? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final paths = raw['paths'];
    return Playlist(
      id: id,
      name: name,
      paths: <String>[
        if (paths is List)
          for (final path in paths)
            if (path is String && path.isNotEmpty) path,
      ],
      updated: raw['updated'] is String
          ? DateTime.tryParse(raw['updated']! as String)
          : null,
    );
  }

  /// Resumen para la lista de la UI.
  String get summary => smart
      ? 'Inteligente · $length pistas'
      : '$length pistas${updated == null ? '' : ' · ${_ago(updated!)}'}';

  static String _ago(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inHours < 1) return 'hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'hace ${diff.inHours} h';
    if (diff.inDays < 30) return 'hace ${diff.inDays} d';
    return 'hace ${(diff.inDays / 30).floor()} meses';
  }

  @override
  bool operator ==(Object other) =>
      other is Playlist &&
      other.id == id &&
      other.name == name &&
      other.smart == smart &&
      listEquals(other.paths, paths);

  @override
  int get hashCode => Object.hash(id, name, smart, paths.length);

  @override
  String toString() => 'Playlist($name, $length)';
}

/// Listas calculadas que ofrece la app.
enum SmartList {
  top25('smart:top25', 'Top 25 más escuchadas'),
  neverPlayed('smart:never', 'Nunca escuchadas'),
  addedThisMonth('smart:month', 'Añadidas este mes');

  const SmartList(this.id, this.label);

  final String id;
  final String label;
}

/// Almacén de playlists en JSON (`playlists.json`).
///
/// Importa y exporta `.m3u`, `.m3u8` y `.pls` escritos a mano: son formatos de
/// texto con una línea por pista, así que un parser de veinte líneas basta y no
/// hay que añadir paquetes. Las rutas relativas se resuelven contra el
/// directorio del archivo importado, que es como funcionan los `.m3u` de verdad.
class PlaylistStore extends ChangeNotifier {
  PlaylistStore({File? file})
      : file = file ?? File('${StorageDirectory.current.path}/playlists.json');

  PlaylistStore.memory() : file = null;

  static const int formatVersion = 1;

  final File? file;

  final List<Playlist> _playlists = <Playlist>[];

  /// Cuándo entró cada ruta en la app (para «Añadidas este mes»).
  final Map<String, DateTime> _seen = <String, DateTime>{};

  Timer? _saveTimer;
  bool _loaded = false;
  bool _dirty = false;
  int _sequence = 0;

  List<Playlist> get playlists => List<Playlist>.unmodifiable(_playlists);

  bool get isLoaded => _loaded;

  bool get isDirty => _dirty;

  Playlist? byId(String id) {
    for (final playlist in _playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  int get length => _playlists.length;

  // --- operaciones ---------------------------------------------------------

  Playlist create(String name, {List<String> paths = const <String>[]}) {
    final clean = name.trim().isEmpty ? 'Lista ${_playlists.length + 1}' : name.trim();
    final id = 'pl_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
    final playlist = Playlist(
      id: id,
      name: clean,
      paths: List<String>.unmodifiable(paths),
      updated: DateTime.now(),
    );
    _playlists.add(playlist);
    _touch();
    return playlist;
  }

  bool rename(String id, String name) {
    final index = _indexOf(id);
    if (index < 0 || name.trim().isEmpty) return false;
    _playlists[index] = _playlists[index].copyWith(
      name: name.trim(),
      updated: DateTime.now(),
    );
    _touch();
    return true;
  }

  Playlist? duplicate(String id, {String? name}) {
    final source = byId(id);
    if (source == null) return null;
    final copy = Playlist(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}',
      name: name?.trim().isNotEmpty == true ? name!.trim() : '${source.name} (copia)',
      paths: List<String>.unmodifiable(source.paths),
      updated: DateTime.now(),
    );
    _playlists.insert(_indexOf(id) + 1, copy);
    _touch();
    return copy;
  }

  bool delete(String id) {
    final index = _indexOf(id);
    if (index < 0) return false;
    _playlists.removeAt(index);
    _touch();
    return true;
  }

  bool addPaths(String id, Iterable<String> paths) {
    final index = _indexOf(id);
    if (index < 0) return false;
    final current = _playlists[index];
    final next = <String>[...current.paths];
    var added = 0;
    for (final path in paths) {
      if (path.isEmpty || next.contains(path)) continue;
      next.add(path);
      added += 1;
    }
    if (added == 0) return false;
    _playlists[index] = current.copyWith(
      paths: List<String>.unmodifiable(next),
      updated: DateTime.now(),
    );
    _touch();
    return true;
  }

  bool removeAt(String id, int index) {
    final slot = _indexOf(id);
    if (slot < 0) return false;
    final current = _playlists[slot];
    if (index < 0 || index >= current.paths.length) return false;
    final next = <String>[...current.paths]..removeAt(index);
    _playlists[slot] = current.copyWith(
      paths: List<String>.unmodifiable(next),
      updated: DateTime.now(),
    );
    _touch();
    return true;
  }

  bool move(String id, int from, int to) {
    final slot = _indexOf(id);
    if (slot < 0) return false;
    final current = _playlists[slot];
    if (from < 0 || from >= current.paths.length) return false;
    final target = to.clamp(0, current.paths.length - 1);
    if (target == from) return false;
    final next = <String>[...current.paths];
    final item = next.removeAt(from);
    next.insert(target, item);
    _playlists[slot] = current.copyWith(
      paths: List<String>.unmodifiable(next),
      updated: DateTime.now(),
    );
    _touch();
    return true;
  }

  /// Anota que estas rutas existen (alimenta «Añadidas este mes»).
  void remember(Iterable<String> paths, {DateTime? at}) {
    final now = at ?? DateTime.now();
    var changed = false;
    for (final path in paths) {
      if (path.isEmpty || _seen.containsKey(path)) continue;
      _seen[path] = now;
      changed = true;
    }
    if (changed) _touch();
  }

  /// Listas inteligentes a partir de las reproducciones y la biblioteca.
  ///
  /// [plays] devuelve cuántas veces ha sonado una ruta (lo da `StatsStore`), así
  /// que este archivo no depende de las estadísticas: se puede probar con un
  /// contador cualquiera.
  List<Playlist> smartLists({
    required List<String> library,
    required int Function(String path) plays,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final unique = <String>{...library, ..._seen.keys, ..._playlists.expand((p) => p.paths)}
        .where((path) => path.isNotEmpty)
        .toList();

    final ranked = <String>[
      for (final path in unique)
        if (plays(path) > 0) path,
    ]..sort((a, b) => plays(b).compareTo(plays(a)));

    final never = <String>[
      for (final path in unique)
        if (plays(path) == 0) path,
    ];

    final month = <String>[
      for (final path in unique)
        if (_seen[path] != null &&
            _seen[path]!.year == today.year &&
            _seen[path]!.month == today.month)
          path,
    ];

    return <Playlist>[
      Playlist(
        id: SmartList.top25.id,
        name: SmartList.top25.label,
        paths: List<String>.unmodifiable(ranked.take(25)),
        smart: true,
      ),
      Playlist(
        id: SmartList.neverPlayed.id,
        name: SmartList.neverPlayed.label,
        paths: List<String>.unmodifiable(never.take(200)),
        smart: true,
      ),
      Playlist(
        id: SmartList.addedThisMonth.id,
        name: SmartList.addedThisMonth.label,
        paths: List<String>.unmodifiable(month.take(200)),
        smart: true,
      ),
    ];
  }

  // --- importar / exportar -------------------------------------------------

  /// Lee un `.m3u`, `.m3u8` o `.pls` y crea una lista con lo que haya.
  Future<Playlist?> importFile(File file) async {
    try {
      if (!file.existsSync()) return null;
      final text = await file.readAsString();
      final base = file.parent.path;
      final lower = file.path.toLowerCase();
      final paths = lower.endsWith('.pls')
          ? parsePls(text, baseDir: base)
          : parseM3u(text, baseDir: base);
      if (paths.isEmpty) return null;
      final dot = file.path.lastIndexOf('.');
      final name = file.path
          .substring(file.path.lastIndexOf(Platform.pathSeparator) + 1, dot < 0 ? null : dot);
      return create(name, paths: paths);
    } catch (_) {
      return null;
    }
  }

  /// Exporta a `.m3u8` (UTF-8, extensiones `#EXTINF` incluidas).
  Future<File?> exportPlaylist(Playlist playlist, File target) async {
    try {
      final text = buildM3u(playlist);
      await target.writeAsString(text, flush: true);
      return target;
    } catch (_) {
      return null;
    }
  }

  /// `.m3u`/`.m3u8`: `#EXTM3U`, `#EXTINF:segundos,Título` y la ruta.
  static List<String> parseM3u(String text, {String? baseDir}) {
    final out = <String>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final path = _resolve(line, baseDir);
      if (path.isNotEmpty && !out.contains(path)) out.add(path);
    }
    return out;
  }

  /// `.pls`: `File1=…`, `Title1=…`, `NumberOfEntries=…`.
  static List<String> parsePls(String text, {String? baseDir}) {
    final out = <String>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (!line.toLowerCase().startsWith('file')) continue;
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final path = _resolve(line.substring(eq + 1).trim(), baseDir);
      if (path.isNotEmpty && !out.contains(path)) out.add(path);
    }
    return out;
  }

  static String buildM3u(Playlist playlist) {
    final out = StringBuffer('#EXTM3U\n');
    for (final path in playlist.paths) {
      out
        ..writeln('#EXTINF:-1,${_baseName(path)}')
        ..writeln(path);
    }
    return out.toString();
  }

  static String _resolve(String value, String? baseDir) {
    final path = value.replaceAll('file://', '');
    if (path.isEmpty) return '';
    if (path.startsWith('/') || path.contains(':')) return path;
    if (baseDir == null) return path;
    return '$baseDir${Platform.pathSeparator}$path';
  }

  static String _baseName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    final name = parts.isEmpty ? path : parts.last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  // --- persistencia --------------------------------------------------------

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final target = file;
    if (target == null) return;
    try {
      if (!target.existsSync()) return;
      final raw = await target.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final list = decoded['playlists'];
      if (list is List) {
        for (final entry in list) {
          final playlist = Playlist.fromJson(entry);
          if (playlist != null) _playlists.add(playlist);
        }
      }
      final seen = decoded['seen'];
      if (seen is Map) {
        seen.forEach((key, value) {
          if (key is! String || value is! String) return;
          final when = DateTime.tryParse(value);
          if (when != null) _seen[key] = when;
        });
      }
      notifyListeners();
    } catch (_) {
      _playlists.clear();
      _seen.clear();
    }
  }

  void _touch() {
    _dirty = true;
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (file == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(save());
    });
  }

  Future<void> save() async {
    final target = file;
    _saveTimer?.cancel();
    _saveTimer = null;
    if (target == null) {
      _dirty = false;
      return;
    }
    try {
      final payload = <String, Object?>{
        'version': formatVersion,
        'playlists': <Map<String, Object?>>[
          for (final playlist in _playlists) playlist.toJson(),
        ],
        'seen': <String, String>{
          for (final entry in _seen.entries) entry.key: entry.value.toIso8601String(),
        },
      };
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
      _dirty = false;
    } catch (_) {
      // Igual que la sesión: si no se puede escribir, seguimos en memoria.
    }
  }

  int _indexOf(String id) {
    for (var i = 0; i < _playlists.length; i++) {
      if (_playlists[i].id == id) return i;
    }
    return -1;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_dirty) unawaited(save());
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Multi-cola
// ---------------------------------------------------------------------------

/// Una de las cinco colas simultáneas.
class QueueSlot {
  const QueueSlot({this.name = '', this.paths = const <String>[], this.index = 0});

  final String name;
  final List<String> paths;

  /// Pista audible de esta cola (para poder retomarla).
  final int index;

  bool get isEmpty => paths.isEmpty;

  String get label => name.trim().isEmpty ? 'Cola' : name.trim();

  QueueSlot copyWith({String? name, List<String>? paths, int? index}) => QueueSlot(
        name: name ?? this.name,
        paths: paths ?? this.paths,
        index: index ?? this.index,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'paths': paths,
        'index': index,
      };

  static QueueSlot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final paths = raw['paths'];
    return QueueSlot(
      name: raw['name'] is String ? raw['name']! as String : '',
      paths: <String>[
        if (paths is List)
          for (final path in paths)
            if (path is String && path.isNotEmpty) path,
      ],
      index: raw['index'] is num ? (raw['index']! as num).toInt() : 0,
    );
  }
}

/// Cinco colas independientes (estilo Musicolet) que sobreviven al cierre.
///
/// Solo la **activa** suena; las demás se guardan con su posición para poder
/// saltar de una a otra sin perder el sitio.
class MultiQueueStore extends ChangeNotifier {
  MultiQueueStore({File? file})
      : file = file ?? File('${StorageDirectory.current.path}/queues.json');

  MultiQueueStore.memory() : file = null;

  static const int slotCount = 5;
  static const int formatVersion = 1;

  final File? file;

  final List<QueueSlot> _slots = List<QueueSlot>.generate(
    slotCount,
    (index) => QueueSlot(name: index == 0 ? 'Principal' : 'Cola ${index + 1}'),
  );

  int _active = 0;
  bool _loaded = false;
  bool _dirty = false;

  List<QueueSlot> get slots => List<QueueSlot>.unmodifiable(_slots);

  int get active => _active;

  QueueSlot get activeSlot => _slots[_active];

  bool get isDirty => _dirty;

  /// ¿Hay algo guardado en otra cola que no sea la activa?
  bool get hasStored {
    for (var i = 0; i < _slots.length; i++) {
      if (i != _active && !_slots[i].isEmpty) return true;
    }
    return false;
  }

  void setActive(int index) {
    if (index < 0 || index >= slotCount || index == _active) return;
    _active = index;
    _touch();
  }

  /// Guarda el estado de una cola (lo que la UI ve en el motor).
  bool capture(int slot, List<String> paths, int index) {
    if (slot < 0 || slot >= slotCount) return false;
    final current = _slots[slot];
    if (listEquals(current.paths, paths) && current.index == index) return false;
    _slots[slot] = current.copyWith(
      paths: List<String>.unmodifiable(paths),
      index: index,
    );
    _touch();
    return true;
  }

  bool rename(int slot, String name) {
    if (slot < 0 || slot >= slotCount) return false;
    if (name.trim().isEmpty) return false;
    _slots[slot] = _slots[slot].copyWith(name: name.trim());
    _touch();
    return true;
  }

  bool clear(int slot) {
    if (slot < 0 || slot >= slotCount) return false;
    _slots[slot] = QueueSlot(name: _slots[slot].name);
    _touch();
    return true;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final target = file;
    if (target == null) return;
    try {
      if (!target.existsSync()) return;
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map) return;
      final slots = decoded['slots'];
      if (slots is List) {
        for (var i = 0; i < slotCount && i < slots.length; i++) {
          final slot = QueueSlot.fromJson(slots[i]);
          if (slot != null) _slots[i] = slot;
        }
      }
      final active = decoded['active'];
      if (active is num && active >= 0 && active < slotCount) {
        _active = active.toInt();
      }
      notifyListeners();
    } catch (_) {
      // JSON roto: cinco colas vacías.
    }
  }

  void _touch() {
    _dirty = true;
    notifyListeners();
    if (file == null) return;
    // Antirrebote: arrastrar una cola dispara decenas de cambios y no hace
    // falta escribir el archivo en cada uno.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () => unawaited(save()));
  }

  Timer? _saveTimer;

  /// Escribe las cinco colas. La llama el antirrebote, la UI al cerrar y
  /// [dispose]; siempre deja el archivo escrito antes de devolver.
  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final target = file;
    if (target == null) {
      _dirty = false;
      return;
    }
    try {
      final payload = <String, Object?>{
        'version': formatVersion,
        'active': _active,
        'slots': <Map<String, Object?>>[for (final slot in _slots) slot.toJson()],
      };
      // Nombre único: dos guardados seguidos compartían el `.tmp` y el segundo
      // `rename` podía encontrárselo ya movido.
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final temp = File('${target.path}.$stamp.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
      _dirty = false;
    } catch (_) {
      // Sin disco no pasa nada: las colas viven en memoria.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_dirty) unawaited(save());
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Posición en pistas largas
// ---------------------------------------------------------------------------

/// Recuerda por dónde ibas en las pistas **largas** (más de 15 minutos).
///
/// Un audiolibro o un directo no se retoman desde el principio: al abrirlos otra
/// vez, la UI pregunta [positionFor] y salta ahí. Para las pistas cortas no se
/// guarda nada (no tiene sentido y llenaría el archivo).
class LongTrackMemory extends ChangeNotifier {
  LongTrackMemory({File? file})
      : file = file ?? File('${StorageDirectory.current.path}/long_tracks.json');

  LongTrackMemory.memory() : file = null;

  /// A partir de aquí se considera «larga».
  static const double longTrackSeconds = 15 * 60;

  /// Por debajo de esto no merece la pena recordar (ni reanudar).
  static const double minimumSeconds = 30;

  static const int formatVersion = 1;

  final File? file;

  final Map<String, double> _positions = <String, double>{};
  Timer? _saveTimer;
  bool _loaded = false;

  Map<String, double> get positions => Map<String, double>.unmodifiable(_positions);

  int get length => _positions.length;

  double? positionFor(String path) {
    final value = _positions[path];
    return value == null || value < minimumSeconds ? null : value;
  }

  /// ¿Es una pista de las que se retoman?
  static bool isLong(double duration) =>
      duration.isFinite && duration >= longTrackSeconds;

  /// Guarda la posición si la pista es larga y ya pasó el mínimo.
  bool remember(String path, double position, double duration) {
    if (path.isEmpty || !isLong(duration)) return false;
    if (!position.isFinite || position < minimumSeconds) return false;
    // Casi al final: mejor empezar de cero la próxima vez.
    if (duration > 0 && position > duration - 20) return forget(path);
    if ((_positions[path] ?? -1) == position) return false;
    _positions[path] = position;
    _touch();
    return true;
  }

  bool forget(String path) {
    if (_positions.remove(path) == null) return false;
    _touch();
    return true;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final target = file;
    if (target == null) return;
    try {
      if (!target.existsSync()) return;
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map) return;
      final positions = decoded['positions'];
      if (positions is Map) {
        positions.forEach((key, value) {
          if (key is String && value is num) {
            _positions[key] = value.toDouble();
          }
        });
      }
      notifyListeners();
    } catch (_) {
      _positions.clear();
    }
  }

  void _touch() {
    notifyListeners();
    if (file == null) return;
    // Antirrebote: la posición se apunta en cada tick de la UI.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () => unawaited(save()));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    super.dispose();
  }

  Future<void> save() async {
    final target = file;
    if (target == null) return;
    try {
      final payload = <String, Object?>{
        'version': formatVersion,
        'positions': _positions,
      };
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
    } catch (_) {
      // Sin disco, la memoria dura la sesión.
    }
  }
}
