import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// Emisora de radio por Internet.
///
/// [url] puede ser un flujo directo (`https://host/stream.mp3`, Icecast o
/// Shoutcast) o una lista (`.m3u`/`.m3u8`/`.pls`) que apunte a uno; el motor de
/// audio del núcleo **solo abre archivos**, así que el flujo se baja a un
/// archivo temporal con [RadioStore.buffer] y se reproduce desde ahí.
class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.url,
    this.genre = '',
    this.addedAt,
    this.builtin = false,
  });

  final String id;
  final String name;
  final String url;
  final String genre;
  final DateTime? addedAt;

  /// Las sugeridas de fábrica no se guardan ni se pueden editar.
  final bool builtin;

  bool get isPlaylist {
    final lower = url.toLowerCase();
    return lower.endsWith('.m3u') ||
        lower.endsWith('.m3u8') ||
        lower.endsWith('.pls');
  }

  Uri? get uri => Uri.tryParse(url);

  /// Host, para la segunda línea del listado.
  String get host => uri?.host.isNotEmpty == true ? uri!.host : url;

  RadioStation copyWith({String? name, String? url, String? genre}) =>
      RadioStation(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        genre: genre ?? this.genre,
        addedAt: addedAt,
        builtin: builtin,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'url': url,
        'genre': genre,
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
      };

  static RadioStation? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    if (url is! String || url.isEmpty) return null;
    final name = raw['name'];
    return RadioStation(
      id: raw['id'] is String && (raw['id'] as String).isNotEmpty
          ? raw['id'] as String
          : RadioStore.idFor(url),
      name: name is String && name.isNotEmpty ? name : _hostOf(url),
      url: url,
      genre: raw['genre'] is String ? raw['genre'] as String : '',
      addedAt: DateTime.tryParse(raw['addedAt'] is String ? raw['addedAt'] as String : ''),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RadioStation && other.id == id && other.url == url;

  @override
  int get hashCode => Object.hash(id, url);

  @override
  String toString() => 'RadioStation($name, $url)';

  static String _hostOf(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.host.isNotEmpty ? uri.host : url;
  }
}

/// Resultado de bajar un tramo del flujo a disco.
class RadioBuffer {
  const RadioBuffer({
    required this.file,
    required this.source,
    required this.bytes,
    required this.contentType,
    required this.truncated,
    required this.elapsed,
  });

  /// Archivo temporal listo para `openFile`.
  final File file;
  final Uri source;
  final int bytes;
  final String contentType;

  /// `true` si se cortó por ventana o tamaño: el flujo sigue en el servidor.
  final bool truncated;
  final Duration elapsed;

  String get label {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    return '$mb MB · ${contentType.isEmpty ? 'audio' : contentType}';
  }
}

/// Error de red al resolver o bajar una emisora (mensaje para la UI).
class RadioException implements Exception {
  RadioException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Emisoras guardadas, importación de listas y bajada del flujo.
///
/// Mismo patrón que el resto de almacenes: JSON versionado en
/// `StorageDirectory.current/radios.json`, escritura atómica (`.tmp` + `rename`)
/// y aviso a quien escuche con [ChangeNotifier]. `RadioStore.memory()` no toca
/// disco y es lo que usan los tests.
class RadioStore extends ChangeNotifier {
  RadioStore({File? file})
      : file = file ?? File('${StorageDirectory.current.path}/radios.json');

  RadioStore.memory() : file = null;

  static const int formatVersion = 1;

  /// Tope de una lista importada: más de esto es un error, no una radio.
  static const int maxImportEntries = 500;

  /// Ventana de bajada por defecto: 12 s de audio suele bastar para MP3 de
  /// 128 kbps (~190 KB) y siempre cabe en el tope de bytes.
  static const Duration defaultWindow = Duration(seconds: 12);

  static const int maxBufferBytes = 24 << 20;

  final File? file;

  final List<RadioStation> _stations = <RadioStation>[];
  bool _loaded = false;
  bool _dirty = false;
  Timer? _saveTimer;

  /// Sugerencias de fábrica (no se guardan): emisoras públicas conocidas.
  static const List<RadioStation> builtinStations = <RadioStation>[
    RadioStation(
      id: 'soma-groove',
      name: 'SomaFM Groove Salad',
      url: 'https://ice1.somafm.com/groovesalad-128-mp3',
      genre: 'Ambient',
      builtin: true,
    ),
    RadioStation(
      id: 'soma-lush',
      name: 'SomaFM Lush',
      url: 'https://ice1.somafm.com/lush-128-mp3',
      genre: 'Vocal chill',
      builtin: true,
    ),
    RadioStation(
      id: 'radioparadise',
      name: 'Radio Paradise Main Mix',
      url: 'https://stream.radioparadise.com/aac-128',
      genre: 'Eclectic',
      builtin: true,
    ),
    RadioStation(
      id: 'fip',
      name: 'FIP',
      url: 'https://icecast.radiofrance.fr/fip-midfi.mp3',
      genre: 'Eclectic',
      builtin: true,
    ),
  ];

  List<RadioStation> get stations => List<RadioStation>.unmodifiable(_stations);

  bool get isEmpty => _stations.isEmpty;

  int get length => _stations.length;

  bool get isLoaded => _loaded;

  bool get isDirty => _dirty;

  static String idFor(String url) => 'r${_stableHash(url)}';

  /// Id estable a partir de la URL (FNV-1a, igual que el acento de reserva).
  static int _stableHash(String text) {
    var hash = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      hash ^= unit & 0xFF;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  // ---------------------------------------------------------------------------
  // Alta, baja y cambios
  // ---------------------------------------------------------------------------

  /// Añade una emisora (idempotente por URL). Devuelve la existente si ya está.
  RadioStation add({required String name, required String url, String genre = ''}) {
    final cleanUrl = url.trim();
    final existing = _stations.where((station) => station.url == cleanUrl);
    if (existing.isNotEmpty) return existing.first;

    final station = RadioStation(
      id: idFor(cleanUrl),
      name: name.trim().isEmpty ? RadioStation._hostOf(cleanUrl) : name.trim(),
      url: cleanUrl,
      genre: genre.trim(),
      addedAt: DateTime.now(),
    );
    _stations.add(station);
    _touch();
    return station;
  }

  bool remove(String id) {
    final before = _stations.length;
    _stations.removeWhere((station) => station.id == id);
    if (_stations.length == before) return false;
    _touch();
    return true;
  }

  bool rename(String id, String name) {
    final index = _stations.indexWhere((station) => station.id == id);
    if (index < 0) return false;
    _stations[index] = _stations[index].copyWith(name: name.trim());
    _touch();
    return true;
  }

  void clear() {
    if (_stations.isEmpty) return;
    _stations.clear();
    _touch();
  }

  // ---------------------------------------------------------------------------
  // Importar / exportar listas
  // ---------------------------------------------------------------------------

  /// Importa `.m3u`, `.m3u8` o `.pls` y añade las emisoras que falten.
  ///
  /// Devuelve solo las **nuevas**; las repetidas por URL se ignoran en silencio
  /// (importar dos veces la misma lista no debe duplicar nada).
  Future<List<RadioStation>> importPlaylist(File file) async {
    final text = await file.readAsString();
    final base = Uri.file(file.path);
    final seeds = parsePlaylistText(text, base: base);
    final added = <RadioStation>[];
    for (final seed in seeds.take(maxImportEntries)) {
      final before = _stations.length;
      final station = add(name: seed.name, url: seed.url, genre: seed.genre);
      if (_stations.length > before) added.add(station);
    }
    return added;
  }

  /// Exporta las emisoras como `.m3u` (sin las de fábrica).
  Future<File> exportM3u(File target) async {
    final buffer = StringBuffer('#EXTM3U\n');
    for (final station in _stations) {
      buffer
        ..writeln('#EXTINF:-1,${station.name}')
        ..writeln(station.url);
    }
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(buffer.toString(), flush: true);
    await temp.rename(target.path);
    return target;
  }

  /// Entradas de una lista de radio (m3u/m3u8/pls/texto con una URL por línea).
  static List<RadioSeed> parsePlaylistText(String text, {Uri? base}) {
    final seeds = <RadioSeed>[];
    final trimmed = text.trimLeft();
    final isPls = trimmed.toLowerCase().startsWith('[playlist]');
    final isExtinf = text.contains('#EXTINF');
    if (isPls) {
      final titles = <String, String>{};
      final files = <String, String>{};
      for (final line in const LineSplitter().convert(text)) {
        final entry = line.split('=');
        if (entry.length < 2) continue;
        final key = entry.first.trim().toLowerCase();
        final value = entry.sublist(1).join('=').trim();
        if (key == 'title' || key.startsWith('title')) {
          titles[key] = value;
        } else if (key.startsWith('file')) {
          files[key] = value;
        }
      }
      final keys = files.keys.toList()..sort();
      for (final key in keys) {
        final url = _absolute(files[key], base);
        if (url == null) continue;
        final index = key.replaceAll(RegExp('[^0-9]'), '');
        seeds.add(RadioSeed(
          name: titles['title$index'] ?? '',
          url: url,
        ));
      }
      return seeds;
    }

    String? pendingName;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF')) {
        // #EXTINF:-1,Nombre  |  #EXTINF:-1 tvg-name="X",Nombre
        final comma = line.indexOf(',');
        pendingName = comma >= 0 ? line.substring(comma + 1).trim() : '';
        continue;
      }
      if (line.startsWith('#')) continue;
      final url = _absolute(line, base);
      if (url == null) continue;
      seeds.add(RadioSeed(name: pendingName ?? '', url: url, fromExtinf: isExtinf));
      pendingName = null;
    }
    return seeds;
  }

  static String? _absolute(String? value, Uri? base) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.hasScheme) {
      if (uri.scheme != 'http' && uri.scheme != 'https') return null;
      return uri.toString();
    }
    if (base == null) return null;
    return base.resolve(trimmed).toString();
  }

  // ---------------------------------------------------------------------------
  // Red: resolver el flujo y bajar un tramo
  // ---------------------------------------------------------------------------

  /// Sigue una lista de radio hasta una URL de audio.
  ///
  /// Si [url] ya es un flujo devuelve lo mismo. Acepta una redirección de
  /// lista (`.m3u`/`.pls`) y como mucho [maxHops] saltos.
  Future<Uri> resolve(Uri url, {HttpClient? client, int maxHops = 2}) async {
    if (!url.hasScheme || (url.scheme != 'http' && url.scheme != 'https')) {
      throw RadioException('La URL no empieza por http:// o https://.');
    }
    var current = url;
    for (var hop = 0; hop <= maxHops; hop++) {
      final path = current.path.toLowerCase();
      final looksPlaylist = path.endsWith('.m3u') ||
          path.endsWith('.m3u8') ||
          path.endsWith('.pls');
      if (!looksPlaylist) return current;

      final text = await _fetchText(current, client: client);
      final seeds = parsePlaylistText(text, base: current);
      if (seeds.isEmpty) {
        throw RadioException('La lista ${current.host} no tiene emisoras.');
      }
      final next = Uri.tryParse(seeds.first.url);
      if (next == null) {
        throw RadioException('La lista ${current.host} apunta a una URL inválida.');
      }
      current = next;
    }
    throw RadioException('Demasiadas listas encadenadas en ${url.host}.');
  }

  /// Baja un tramo del flujo a un archivo temporal y devuelve qué quedó.
  ///
  /// No es un reproductor de directo: el núcleo abre **archivos**, así que se
  /// capturan [window] segundos (o [maxBytes]) y se reproduce esa ventana.
  Future<RadioBuffer> buffer(
    Uri url, {
    Duration window = defaultWindow,
    int maxBytes = maxBufferBytes,
    HttpClient? client,
    Directory? directory,
    void Function(int bytes)? onProgress,
  }) async {
    final clock = Stopwatch()..start();
    final resolved = await resolve(url, client: client);
    final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 12));
    try {
      final request = await http.getUrl(resolved);
      request.followRedirects = true;
      request.headers.set(HttpHeaders.userAgentHeader, 'CyberHex/1.0');
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw RadioException(
          'La emisora respondió ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }

      final contentType = (response.headers.contentType?.mimeType ?? '').toLowerCase();
      final extension = _extensionFor(contentType, resolved);
      final target = _targetFile(resolved, extension, directory);
      await target.parent.create(recursive: true);
      final part = File('${target.path}.part');

      var bytes = 0;
      var truncated = true;
      try {
        final sink = part.openWrite();
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            bytes += chunk.length;
            onProgress?.call(bytes);
            if (bytes >= maxBytes) break;
            if (clock.elapsed >= window) break;
          }
          if (bytes < maxBytes && clock.elapsed < window) {
            // El servidor cerró el flujo: no hay ventana cortada.
            truncated = false;
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        if (bytes == 0) {
          throw RadioException('La emisora no envió audio (${resolved.host}).');
        }

        await part.rename(target.path);
        return RadioBuffer(
          file: target,
          source: resolved,
          bytes: bytes,
          contentType: contentType,
          truncated: truncated,
          elapsed: clock.elapsed,
        );
      } catch (_) {
        // Ni archivos a medias ni .part huérfanos en el temporal.
        await part.delete().catchError((_) => part);
        rethrow;
      }
    } on RadioException {
      rethrow;
    } on SocketException catch (error) {
      throw RadioException('Sin conexión con ${resolved.host}: ${error.message}');
    } on HttpException catch (error) {
      throw RadioException('Error HTTP con ${resolved.host}: ${error.message}');
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  Future<String> _fetchText(Uri url, {HttpClient? client, int limit = 256 << 10}) async {
    final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 12));
    try {
      final request = await http.getUrl(url);
      request.followRedirects = true;
      request.headers.set(HttpHeaders.userAgentHeader, 'CyberHex/1.0');
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw RadioException(
          'La lista respondió ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      final buffer = <int>[];
      await for (final chunk in response) {
        buffer.addAll(chunk);
        if (buffer.length >= limit) break;
      }
      return utf8.decode(buffer, allowMalformed: true);
    } on RadioException {
      rethrow;
    } on SocketException catch (error) {
      throw RadioException('Sin conexión con ${url.host}: ${error.message}');
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  static String _extensionFor(String contentType, Uri url) {
    if (contentType.contains('mpeg')) return 'mp3';
    if (contentType.contains('ogg')) return 'ogg';
    if (contentType.contains('opus')) return 'opus';
    if (contentType.contains('flac')) return 'flac';
    if (contentType.contains('aac') || contentType.contains('mp4')) return 'aac';
    final path = url.path.toLowerCase();
    for (final extension in const <String>['mp3', 'ogg', 'opus', 'flac', 'aac', 'm4a']) {
      if (path.endsWith('.$extension')) return extension;
    }
    return 'mp3';
  }

  static File _targetFile(Uri url, String extension, Directory? directory) {
    final root = directory ?? Directory('${Directory.systemTemp.path}/cyberhex_radio');
    final host = url.host.isEmpty ? 'radio' : url.host.replaceAll(RegExp('[^A-Za-z0-9.-]'), '_');
    return File('${root.path}/$host-${_stableHash(url.toString())}.$extension');
  }

  // ---------------------------------------------------------------------------
  // Persistencia
  // ---------------------------------------------------------------------------

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
      final stations = decoded['stations'];
      if (stations is! List) return;
      _stations
        ..clear()
        ..addAll(stations.map(RadioStation.fromJson).whereType<RadioStation>());
      notifyListeners();
    } catch (_) {
      // Un JSON roto no debe impedir usar la app: se empieza sin emisoras.
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
    _saveTimer = Timer(const Duration(milliseconds: 300), () => unawaited(save()));
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
        'stations': <Object?>[for (final station in _stations) station.toJson()],
      };
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
      _dirty = false;
    } catch (_) {
      // Sin disco, las emisoras duran la sesión.
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

/// Entrada de una lista antes de convertirse en [RadioStation].
class RadioSeed {
  const RadioSeed({required this.name, required this.url, this.genre = '', this.fromExtinf = false});

  final String name;
  final String url;
  final String genre;
  final bool fromExtinf;
}
