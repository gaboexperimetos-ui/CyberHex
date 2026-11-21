import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// Estadísticas de escucha: qué suena, cuánto y a qué hora.
///
/// Se guarda en un JSON pequeño al lado de la sesión (`stats.json`), con
/// `.tmp` + `rename` y un antirrebote de 800 ms: escribir en cada cambio de
/// pista sería un disco golpeado para nada.
///
/// Lo que **no** hace: medir con precisión de milisegundos. El controlador
/// avisa cada vez que empieza una pista ([StatsStore.record]); la duración
/// contada es la que el motor reporta para la pista, no el tiempo real con
/// pausas.
class TrackStat {
  const TrackStat({
    required this.path,
    this.title = '',
    this.artist = '',
    this.plays = 0,
    this.seconds = 0,
  });

  final String path;
  final String title;
  final String artist;
  final int plays;
  final double seconds;

  /// Minutos escuchados, redondeados a uno.
  double get minutes => (seconds / 60 * 10).round() / 10;

  String get label => title.isNotEmpty ? title : _baseName(path);

  TrackStat merge({
    String? title,
    String? artist,
    int plays = 1,
    double seconds = 0,
  }) {
    return TrackStat(
      path: path,
      title: title != null && title.isNotEmpty ? title : this.title,
      artist: artist != null && artist.isNotEmpty ? artist : this.artist,
      plays: this.plays + plays,
      seconds: this.seconds + seconds,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        if (title.isNotEmpty) 'title': title,
        if (artist.isNotEmpty) 'artist': artist,
        'plays': plays,
        'seconds': seconds,
      };

  static TrackStat? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    if (path is! String || path.isEmpty) return null;
    return TrackStat(
      path: path,
      title: raw['title'] is String ? raw['title']! as String : '',
      artist: raw['artist'] is String ? raw['artist']! as String : '',
      plays: raw['plays'] is num ? (raw['plays']! as num).toInt() : 0,
      seconds: raw['seconds'] is num ? (raw['seconds']! as num).toDouble() : 0,
    );
  }

  @override
  String toString() => 'TrackStat($label, $plays×, ${minutes}m)';
}

/// Una línea del historial.
class HistoryEntry {
  const HistoryEntry({
    required this.path,
    required this.started,
    this.title = '',
    this.artist = '',
    this.seconds = 0,
  });

  final String path;
  final DateTime started;
  final String title;
  final String artist;
  final double seconds;

  String get label => title.isNotEmpty ? title : _baseName(path);

  String get clock =>
      '${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'started': started.toIso8601String(),
        if (title.isNotEmpty) 'title': title,
        if (artist.isNotEmpty) 'artist': artist,
        'seconds': seconds,
      };

  static HistoryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final started = DateTime.tryParse(raw['started'] is String ? raw['started']! as String : '');
    if (path is! String || path.isEmpty || started == null) return null;
    return HistoryEntry(
      path: path,
      started: started,
      title: raw['title'] is String ? raw['title']! as String : '',
      artist: raw['artist'] is String ? raw['artist']! as String : '',
      seconds: raw['seconds'] is num ? (raw['seconds']! as num).toDouble() : 0,
    );
  }
}

/// Almacén de estadísticas. Extiende [ChangeNotifier] porque la pantalla de
/// estadísticas y la fila de la biblioteca se repintan al cambiar.
class StatsStore extends ChangeNotifier {
  StatsStore({File? file})
      : file = file ?? File('${StorageDirectory.current.path}/stats.json');

  /// Sin disco: pruebas y vistas previas.
  StatsStore.memory() : file = null;

  static const int formatVersion = 1;

  /// Tope del historial: mil líneas son ~200 KiB y cubren meses de uso normal.
  static const int historyCap = 1000;

  final File? file;

  final Map<String, TrackStat> _tracks = <String, TrackStat>{};
  final List<HistoryEntry> _history = <HistoryEntry>[];
  final List<int> _hours = List<int>.filled(24, 0);

  Timer? _saveTimer;
  bool _loaded = false;
  bool _dirty = false;

  /// Cambios pendientes de escribir (lo comprueban las pruebas).
  bool get isDirty => _dirty;

  bool get isLoaded => _loaded;

  List<TrackStat> get tracks => List<TrackStat>.unmodifiable(_tracks.values);

  List<HistoryEntry> get history => List<HistoryEntry>.unmodifiable(_history);

  int get totalPlays => _tracks.values.fold<int>(0, (sum, stat) => sum + stat.plays);

  double get totalSeconds =>
      _tracks.values.fold<double>(0, (sum, stat) => sum + stat.seconds);

  double get totalMinutes => (totalSeconds / 60 * 10).round() / 10;

  /// Veces que ha sonado [path].
  int playsOf(String path) => _tracks[path]?.plays ?? 0;

  TrackStat? statOf(String path) => _tracks[path];

  /// Reparto por hora del día (0..23) de los arranques de pista.
  Map<int, int> get byHour => <int, int>{
        for (var hour = 0; hour < 24; hour++)
          if (_hours[hour] > 0) hour: _hours[hour],
      };

  /// Hora favorita, o -1 si aún no hay datos.
  int get favoriteHour {
    var best = -1;
    var bestCount = 0;
    for (var hour = 0; hour < 24; hour++) {
      if (_hours[hour] > bestCount) {
        best = hour;
        bestCount = _hours[hour];
      }
    }
    return best;
  }

  /// «Escuchas por la tarde» — texto de la pantalla.
  String get favoriteSlot {
    final hour = favoriteHour;
    if (hour < 0) return 'sin datos';
    if (hour < 6) return 'de madrugada';
    if (hour < 12) return 'por la mañana';
    if (hour < 18) return 'por la tarde';
    return 'por la noche';
  }

  List<TrackStat> topTracks([int limit = 10]) {
    final list = _tracks.values.toList()
      ..sort((a, b) {
        final byPlays = b.plays.compareTo(a.plays);
        return byPlays != 0 ? byPlays : b.seconds.compareTo(a.seconds);
      });
    return List<TrackStat>.unmodifiable(list.take(limit));
  }

  List<MapEntry<String, int>> topArtists([int limit = 10]) {
    final counts = <String, int>{};
    for (final stat in _tracks.values) {
      final artist = stat.artist.trim();
      if (artist.isEmpty) continue;
      counts[artist] = (counts[artist] ?? 0) + stat.plays;
    }
    final list = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return List<MapEntry<String, int>>.unmodifiable(list.take(limit));
  }

  /// Apunta una reproducción. [seconds] es la duración de la pista (o el rato
  /// escuchado, si se pasa menos).
  void record({
    required String path,
    String title = '',
    String artist = '',
    double seconds = 0,
    DateTime? at,
  }) {
    if (path.isEmpty) return;
    final when = at ?? DateTime.now();
    final previous = _tracks[path] ??
        TrackStat(path: path, title: title, artist: artist);
    _tracks[path] = previous.merge(
      title: title,
      artist: artist,
      seconds: seconds.isFinite && seconds > 0 ? seconds : 0,
    );
    _history.insert(
      0,
      HistoryEntry(
        path: path,
        started: when,
        title: title,
        artist: artist,
        seconds: seconds,
      ),
    );
    if (_history.length > historyCap) _history.removeRange(historyCap, _history.length);
    _hours[when.hour] = _hours[when.hour] + 1;
    _dirty = true;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> clear() async {
    _tracks.clear();
    _history.clear();
    for (var hour = 0; hour < 24; hour++) {
      _hours[hour] = 0;
    }
    _dirty = true;
    notifyListeners();
    await save();
  }

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
      final tracks = decoded['tracks'];
      if (tracks is List) {
        for (final entry in tracks) {
          final stat = TrackStat.fromJson(entry);
          if (stat != null) _tracks[stat.path] = stat;
        }
      }
      final history = decoded['history'];
      if (history is List) {
        for (final entry in history) {
          final line = HistoryEntry.fromJson(entry);
          if (line != null) _history.add(line);
        }
      }
      final hours = decoded['hours'];
      if (hours is List) {
        for (var hour = 0; hour < 24 && hour < hours.length; hour++) {
          final value = hours[hour];
          _hours[hour] = value is num && value > 0 ? value.toInt() : 0;
        }
      }
      notifyListeners();
    } catch (_) {
      // Un JSON roto no impide arrancar: se empieza de cero y se reescribe.
      _tracks.clear();
      _history.clear();
    }
  }

  void _scheduleSave() {
    if (file == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(save());
    });
  }

  Future<void> save() async {
    final target = file;
    if (target == null) {
      _dirty = false;
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      final payload = <String, Object?>{
        'version': formatVersion,
        'tracks': <Map<String, Object?>>[
          for (final stat in _tracks.values) stat.toJson(),
        ],
        'history': <Map<String, Object?>>[
          for (final line in _history) line.toJson(),
        ],
        'hours': _hours,
      };
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
      _dirty = false;
    } catch (_) {
      // Sin disco seguimos vivos en memoria; el siguiente cambio reintenta.
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

String _baseName(String path) {
  final parts = path.split(RegExp(r'[/\\]'));
  final name = parts.isEmpty ? path : parts.last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
