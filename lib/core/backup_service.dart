import 'dart:convert';
import 'dart:io';

import 'session_store.dart';

/// Una parte de la copia de seguridad: clave en el JSON, archivo de origen y
/// nombre para la UI.
class BackupSection {
  const BackupSection(this.key, this.filename, this.label);

  final String key;
  final String filename;
  final String label;
}

/// Resultado de importar.
class BackupReport {
  const BackupReport({
    required this.createdAt,
    required this.restored,
    required this.skipped,
    required this.written,
  });

  /// Fecha con la que se creó la copia (si la traía).
  final DateTime? createdAt;
  final List<String> restored;
  final List<String> skipped;

  /// Archivos realmente escritos.
  final List<File> written;

  bool get isEmpty => restored.isEmpty;

  String get summary {
    if (restored.isEmpty) {
      return 'La copia no traía ninguna sección conocida.';
    }
    final parts = StringBuffer('Restaurado: ${restored.join(', ')}.');
    if (skipped.isNotEmpty) {
      parts.write(' Ignorado: ${skipped.join(', ')}.');
    }
    parts.write(' Reinicia la app para cargar los datos.');
    return parts.toString();
  }
}

/// Copia de seguridad **unificada** de todo lo que el usuario ha ido creando.
///
/// Un solo `.json` con las secciones que existan (favoritos, listas, colas,
/// pistas largas, estadísticas, emisoras, ajustes de tema, scrobbling y presets
/// de EQ). No inventa formatos: copia el contenido de los archivos que ya usan
/// los almacenes, así que una copia restaurada queda **idéntica** a la original.
///
/// Escritura atómica en las dos direcciones (`.tmp` + `rename`) y validación
/// mínima al importar: una sección que no sea un objeto JSON se ignora en vez de
/// romper la app.
class BackupService {
  BackupService({Directory? directory, DateTime Function()? clock})
      : directory = directory ?? StorageDirectory.current,
        _clock = clock ?? DateTime.now;

  static const int formatVersion = 1;

  /// Secciones reconocidas. El orden es el que sale en el archivo.
  static const List<BackupSection> sections = <BackupSection>[
    BackupSection('favorites', 'favorites.json', 'Favoritos'),
    BackupSection('playlists', 'playlists.json', 'Listas'),
    BackupSection('queues', 'queues.json', 'Colas'),
    BackupSection('long_tracks', 'long_tracks.json', 'Pistas largas'),
    BackupSection('stats', 'stats.json', 'Estadísticas'),
    BackupSection('radios', 'radios.json', 'Emisoras'),
    BackupSection('theme', 'theme.json', 'Tema y ajustes'),
    BackupSection('scrobbler', 'scrobbler.json', 'Scrobbling'),
    BackupSection('eq', 'eq_presets.json', 'Presets de EQ'),
    BackupSection('session', 'session.json', 'Sesión'),
  ];

  final Directory directory;

  final DateTime Function() _clock;

  /// Lee las secciones presentes y las devuelve ya decodificadas.
  Future<Map<String, Object?>> snapshot() async {
    final now = _clock();
    final content = <String, Object?>{};
    for (final section in sections) {
      final file = File('${directory.path}/${section.filename}');
      if (!file.existsSync()) continue;
      try {
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        content[section.key] = decoded;
      } catch (_) {
        // Un archivo corrupto no puede tumbar la copia entera: se omite.
      }
    }
    return <String, Object?>{
      'app': 'CyberHex',
      'version': formatVersion,
      'createdAt': now.toUtc().toIso8601String(),
      'sections': content,
      'counts': <String, Object?>{
        for (final entry in content.entries) entry.key: _countOf(entry.value),
      },
    };
  }

  /// Número de entradas de una sección (para el resumen de la UI).
  static int _countOf(Object? section) {
    if (section is! Map) return 0;
    for (final key in const <String>[
      'stations',
      'playlists',
      'paths',
      'entries',
      'tracks',
      'history',
      'queues',
      'presets',
    ]) {
      final value = section[key];
      if (value is List) return value.length;
      if (value is Map) return value.length;
    }
    return section.length;
  }

  /// Nombre sugerido: `cyberhex-backup-AAAAMMDD-HHMM.json`.
  String suggestedName([DateTime? now]) {
    final at = (now ?? _clock()).toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'cyberhex-backup-${at.year}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}.json';
  }

  /// Escribe la copia. Si [target] no existe, se crea; nunca deja un archivo a
  /// medias (primero `.tmp`, luego `rename`).
  Future<File> exportTo(File target, {String? note}) async {
    final payload = await snapshot();
    if (note != null && note.trim().isNotEmpty) {
      payload['note'] = note.trim();
    }
    final parent = target.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    final text = const JsonEncoder.withIndent('  ').convert(payload);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(target.path);
    return target;
  }

  /// ¿Este JSON tiene forma de copia de CyberHex?
  static bool looksLikeBackup(Object? decoded) {
    if (decoded is! Map) return false;
    if (decoded['app'] != 'CyberHex') return false;
    final version = decoded['version'];
    return version is num && version >= 1;
  }

  /// Restaura las secciones conocidas que traiga la copia.
  ///
  /// No borra nada de lo que no venga en el archivo. Las secciones
  /// desconocidas o mal formadas se listan en [BackupReport.skipped].
  Future<BackupReport> importFrom(File source) async {
    final raw = await source.readAsString();
    final decoded = jsonDecode(raw);
    if (!looksLikeBackup(decoded)) {
      throw const FormatException('El archivo no es una copia de CyberHex.');
    }
    final map = decoded as Map;
    final content = map['sections'];
    final createdAt = DateTime.tryParse(map['createdAt'] is String ? map['createdAt'] as String : '');

    final restored = <String>[];
    final skipped = <String>[];
    final written = <File>[];

    if (content is Map) {
      for (final entry in content.entries) {
        final key = entry.key;
        final section = sections.where((item) => item.key == key);
        if (section.isEmpty) {
          skipped.add('$key (desconocida)');
          continue;
        }
        if (entry.value is! Map) {
          skipped.add('$key (formato)');
          continue;
        }
        final target = File('${directory.path}/${section.first.filename}');
        try {
          if (!directory.existsSync()) {
            await directory.create(recursive: true);
          }
          final text = const JsonEncoder.withIndent('  ').convert(entry.value);
          final temp = File('${target.path}.tmp');
          await temp.writeAsString(text, flush: true);
          await temp.rename(target.path);
          restored.add(section.first.label);
          written.add(target);
        } catch (_) {
          skipped.add('$key (disco)');
        }
      }
    }

    return BackupReport(
      createdAt: createdAt,
      restored: restored,
      skipped: skipped,
      written: written,
    );
  }

  /// Secciones que hay ahora mismo en disco, con su tamaño.
  Future<List<BackupSummary>> availableSections() async {
    final result = <BackupSummary>[];
    for (final section in sections) {
      final file = File('${directory.path}/${section.filename}');
      if (!file.existsSync()) continue;
      result.add(BackupSummary(
        section: section,
        sizeBytes: await file.length(),
      ));
    }
    return result;
  }
}

/// Estado de una sección en disco, para enseñarlo en Ajustes.
class BackupSummary {
  const BackupSummary({required this.section, required this.sizeBytes});

  final BackupSection section;
  final int sizeBytes;

  String get label => section.label;
}
