import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'session_store.dart';

/// Un resultado de búsqueda en Internet Archive.
class ArchiveItem {
  const ArchiveItem({
    required this.identifier,
    required this.title,
    this.creator = '',
    this.year = '',
    this.downloads = 0,
  });

  final String identifier;
  final String title;
  final String creator;
  final String year;
  final int downloads;

  String get subtitle => <String>[
        if (creator.isNotEmpty) creator,
        if (year.isNotEmpty) year,
        if (downloads > 0) '$downloads descargas',
      ].join(' · ');

  @override
  String toString() => 'ArchiveItem($identifier, $title)';
}

/// Un archivo descargable dentro de un ítem.
class AudioCandidate {
  const AudioCandidate({
    required this.url,
    required this.name,
    required this.format,
    this.size = 0,
  });

  final String url;
  final String name;

  /// Formato tal como lo declara el catálogo («VBR MP3», «Flac»…).
  final String format;

  final int size;

  String get sizeLabel {
    if (size <= 0) return 'tamaño desconocido';
    if (size < 1024 * 1024) return '${(size / 1024).round()} KiB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }

  String get label => '$name · $format · $sizeLabel';

  @override
  String toString() => 'AudioCandidate($name, $format)';
}

/// Progreso de descarga, en bytes.
class DownloadProgress {
  const DownloadProgress({required this.received, required this.total});

  final int received;

  /// -1 si el servidor no dijo el tamaño.
  final int total;

  /// 0..1, o `null` si no se conoce el total.
  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;

  @override
  String toString() => 'DownloadProgress($received/$total)';
}

/// Descarga audio de **fuentes abiertas** (Internet Archive) o de una URL
/// directa, sin paquetes: `dart:io` `HttpClient` y ya.
///
/// Todo lo que se puede probar sin red son funciones puras sobre el JSON
/// ([parseSearch], [parseFiles]) y la descarga usa un `HttpClient` inyectable,
/// así que las pruebas levantan un servidor local y descargan de verdad.
class AudioDownloader {
  AudioDownloader({HttpClient? client, String? directory})
      : _client = client ?? HttpClient()..connectionTimeout = const Duration(seconds: 20),
        directory = directory ?? StorageDirectory.current.path;

  /// Dónde se guardan las descargas por defecto.
  final String directory;

  final HttpClient _client;

  static const String searchEndpoint = 'https://archive.org/advancedsearch.php';
  static const String metadataEndpoint = 'https://archive.org/metadata';

  /// Formatos que se ofrecen (el resto del ítem no es audio reproducible).
  static const Set<String> audioFormats = <String>{
    'VBR MP3',
    'MP3',
    '128Kbps MP3',
    '64Kbps MP3',
    'Ogg Vorbis',
    'Flac',
    '24bit Flac',
    '24bit FLAC',
    'AIFF',
    'WAVE',
  };

  /// Busca en el catálogo público. Devuelve lista vacía si algo falla: la UI
  /// enseña «sin resultados» en vez de un error de red críptico.
  Future<List<ArchiveItem>> search(String query, {int rows = 12}) async {
    final clean = query.trim();
    if (clean.isEmpty) return const <ArchiveItem>[];
    final uri = Uri.https('archive.org', '/advancedsearch.php', <String, String>{
      'q': '$clean AND mediatype:(audio)',
      'fl[]': 'identifier',
      'rows': '$rows',
      'page': '1',
      'output': 'json',
    });
    final json = await _getJson(uri);
    return json == null ? const <ArchiveItem>[] : parseSearch(json);
  }

  /// Archivos de audio de un ítem.
  Future<List<AudioCandidate>> files(String identifier) async {
    if (identifier.trim().isEmpty) return const <AudioCandidate>[];
    final uri = Uri.parse('$metadataEndpoint/${Uri.encodeComponent(identifier)}');
    final json = await _getJson(uri);
    return json == null ? const <AudioCandidate>[] : parseFiles(identifier, json);
  }

  /// Descarga [candidate] a [directory] (o al de por defecto).
  ///
  /// Sin barra de progreso propia: llama a [onProgress] con cada bloque.
  Future<File?> download(
    AudioCandidate candidate, {
    void Function(DownloadProgress progress)? onProgress,
    String? directory,
    String? fileName,
    bool overwrite = false,
  }) async {
    final target = File(
      '${directory ?? this.directory}'
      '${Platform.pathSeparator}'
      '${sanitize(fileName ?? candidate.name)}',
    );
    if (target.existsSync() && !overwrite) return target;
    target.parent.createSync(recursive: true);
    final temp = File('${target.path}.part');
    IOSink? sink;
    try {
      final request = await _client.getUrl(Uri.parse(candidate.url));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }
      sink = temp.openWrite();
      var received = 0;
      final total = response.contentLength > 0
          ? response.contentLength
          : candidate.size;
      onProgress?.call(DownloadProgress(received: 0, total: total));
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(DownloadProgress(received: received, total: total));
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (target.existsSync()) target.deleteSync();
      await temp.rename(target.path);
      return target;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {
        // El sink ya podía estar cerrado.
      }
      if (temp.existsSync()) {
        try {
          temp.deleteSync();
        } catch (_) {
          // Nada que hacer.
        }
      }
      return null;
    }
  }

  /// Cierra el cliente HTTP (lo llama la pantalla al salir).
  void close() => _client.close(force: true);

  Future<Object?> _getJson(Uri uri) async {
    try {
      final request = await _client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  // --- parsers (puros) -----------------------------------------------------

  /// `{response: {docs: […]}}` del buscador.
  static List<ArchiveItem> parseSearch(Object? json) {
    if (json is! Map) return const <ArchiveItem>[];
    final response = json['response'];
    if (response is! Map) return const <ArchiveItem>[];
    final docs = response['docs'];
    if (docs is! List) return const <ArchiveItem>[];
    final out = <ArchiveItem>[];
    for (final doc in docs) {
      if (doc is! Map) continue;
      final identifier = _string(doc['identifier']);
      if (identifier.isEmpty) continue;
      final creator = doc['creator'];
      out.add(
        ArchiveItem(
          identifier: identifier,
          title: _string(doc['title']).isEmpty ? identifier : _string(doc['title']),
          creator: creator is List
              ? creator.whereType<String>().take(2).join(', ')
              : _string(creator),
          year: _string(doc['year']),
          downloads: doc['downloads'] is num ? (doc['downloads']! as num).toInt() : 0,
        ),
      );
    }
    return List<ArchiveItem>.unmodifiable(out);
  }

  /// `{files: [{name, format, size}], …}` de la metadata del ítem.
  static List<AudioCandidate> parseFiles(String identifier, Object? json) {
    if (json is! Map) return const <AudioCandidate>[];
    final files = json['files'];
    if (files is! List) return const <AudioCandidate>[];
    final out = <AudioCandidate>[];
    for (final entry in files) {
      if (entry is! Map) continue;
      final name = _string(entry['name']);
      if (name.isEmpty || !_looksLikeAudio(name)) continue;
      final format = _string(entry['format']);
      if (format.isNotEmpty && !audioFormats.contains(format)) {
        // Un .mp3 declarado «Metadata» no se ofrece; el resto sí.
        if (!_looksLikeAudio(name)) continue;
      }
      out.add(
        AudioCandidate(
          url: 'https://archive.org/download/${Uri.encodeComponent(identifier)}'
              '/${Uri.encodeComponent(name)}',
          name: name,
          format: format.isEmpty ? _extension(name).toUpperCase() : format,
          size: entry['size'] is num ? (entry['size']! as num).toInt() : 0,
        ),
      );
    }
    // Los FLAC y MP3 primero, y cada grupo por nombre.
    out.sort((a, b) {
      final byFormat = _rank(b.format).compareTo(_rank(a.format));
      return byFormat != 0 ? byFormat : a.name.compareTo(b.name);
    });
    return List<AudioCandidate>.unmodifiable(out);
  }

  /// Nombre seguro: sin separadores ni caracteres que el sistema no acepte.
  static String sanitize(String name) {
    var clean = name.split(RegExp(r'[/\\]')).last;
    clean = clean.replaceAll(RegExp(r'[<>:"|?*\x00-\x1F]'), '_').trim();
    if (clean.isEmpty) clean = 'descarga.mp3';
    // Android/Linux: 255 bytes por nombre.
    if (clean.length > 180) {
      final dot = clean.lastIndexOf('.');
      final extension = dot > 0 ? clean.substring(dot) : '';
      clean = clean.substring(0, 180 - extension.length) + extension;
    }
    return clean;
  }

  static bool _looksLikeAudio(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aiff');
  }

  static int _rank(String format) {
    final lower = format.toLowerCase();
    if (lower.contains('flac')) return 3;
    if (lower.contains('mp3')) return 2;
    if (lower.contains('ogg') || lower.contains('opus')) return 1;
    return 0;
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? 'audio' : name.substring(dot + 1);
  }

  static String _string(Object? value) {
    if (value is String) return value.trim();
    if (value is num) return '$value';
    return '';
  }
}

/// Atajo para la UI: pegar una URL directa y bajarla con el nombre del enlace.
AudioCandidate candidateFromUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  final name = uri == null || uri.pathSegments.isEmpty
      ? 'descarga.mp3'
      : Uri.decodeComponent(uri.pathSegments.last);
  return AudioCandidate(
    url: url.trim(),
    name: AudioDownloader.sanitize(name),
    format: 'URL directa',
  );
}
