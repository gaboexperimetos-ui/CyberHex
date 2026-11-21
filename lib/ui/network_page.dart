import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../core/session_store.dart';
import '../theme.dart';
import 'mini_player.dart';

/// Tipo de servidor remoto.
enum RemoteKind {
  /// WebDAV (Nextcloud, ownCloud, Apache mod_dav, Synology…): se explora con
  /// `PROPFIND`.
  webdav('WebDAV'),

  /// Enlace directo de nube (Dropbox/Drive/Nextcloud compartido): no se explora,
  /// se descarga lo que apunte.
  cloud('Enlace de nube');

  const RemoteKind(this.label);

  final String label;
}

/// Servidor o enlace guardado.
class RemoteServer {
  const RemoteServer({
    required this.id,
    required this.name,
    required this.url,
    this.kind = RemoteKind.webdav,
    this.username = '',
    this.password = '',
    this.token = '',
  });

  final String id;
  final String name;
  final String url;
  final RemoteKind kind;
  final String username;
  final String password;

  /// Si no está vacío, se usa `Authorization: Bearer`.
  final String token;

  Uri? get uri => Uri.tryParse(url);

  bool get usesBearer => token.trim().isNotEmpty;

  RemoteServer copyWith({String? name, String? url, String? password, String? token}) =>
      RemoteServer(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        kind: kind,
        username: username,
        password: password ?? this.password,
        token: token ?? this.token,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'url': url,
        'kind': kind.name,
        'username': username,
        'password': password,
        'token': token,
      };

  static RemoteServer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    if (url is! String || url.isEmpty) return null;
    return RemoteServer(
      id: raw['id'] is String ? raw['id'] as String : url,
      name: raw['name'] is String && (raw['name'] as String).isNotEmpty
          ? raw['name'] as String
          : Uri.tryParse(url)?.host ?? url,
      url: url,
      kind: RemoteKind.values.firstWhere(
        (kind) => kind.name == raw['kind'],
        orElse: () => RemoteKind.webdav,
      ),
      username: raw['username'] is String ? raw['username'] as String : '',
      password: raw['password'] is String ? raw['password'] as String : '',
      token: raw['token'] is String ? raw['token'] as String : '',
    );
  }

  @override
  String toString() => 'RemoteServer($name, $url)';
}

/// Entrada de una carpeta remota.
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.url,
    required this.isCollection,
    this.size = 0,
  });

  final String name;
  final Uri url;
  final bool isCollection;
  final int size;

  bool get isAudio {
    final path = url.path.toLowerCase();
    for (final extension in const <String>[
      '.mp3',
      '.flac',
      '.wav',
      '.ogg',
      '.opus',
      '.m4a',
      '.aac',
      '.aiff',
    ]) {
      if (path.endsWith(extension)) return true;
    }
    return false;
  }

  String get sizeLabel {
    if (isCollection || size <= 0) return isCollection ? 'Carpeta' : '';
    final mb = size / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(size / 1024).round()} KB';
  }
}

/// Error de red o de protocolo con mensaje para la UI.
class RemoteException implements Exception {
  RemoteException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Cliente WebDAV mínimo sobre `dart:io`.
///
/// Sin paquetes: `PROPFIND` con `Depth: 1`, autenticación Basic o Bearer y un
/// lector de XML por expresiones regulares que solo busca `href` y
/// `resourcetype/collection` (los servidores reales meten namespaces distintos y
/// un parser completo sería más frágil, no menos).
class WebDavClient {
  WebDavClient({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Map<String, String> _authHeaders(RemoteServer server) {
    if (server.usesBearer) {
      return <String, String>{'Authorization': 'Bearer ${server.token}'};
    }
    if (server.username.isNotEmpty || server.password.isNotEmpty) {
      final raw = '${server.username}:${server.password}';
      final encoded = base64Encode(utf8.encode(raw));
      return <String, String>{'Authorization': 'Basic $encoded'};
    }
    return const <String, String>{};
  }

  /// Lista una carpeta (`PROPFIND Depth: 1`).
  Future<List<RemoteEntry>> list(RemoteServer server, Uri url) async {
    final request = await _client.openUrl('PROPFIND', url);
    request.followRedirects = true;
    request.headers.set(HttpHeaders.userAgentHeader, 'CyberHex/1.0');
    request.headers.set('Depth', '1');
    request.headers.contentType =
        ContentType('application', 'xml', charset: 'utf-8');
    _authHeaders(server).forEach(request.headers.set);
    request.write('<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:displayname/><d:getcontentlength/><d:resourcetype/>'
        '</d:prop></d:propfind>');

    final response = await request.close();
    if (response.statusCode == 401) {
      throw RemoteException('El servidor pide usuario y contraseña (401).',
          statusCode: 401);
    }
    if (response.statusCode != 207 && response.statusCode != 200) {
      throw RemoteException(
        'El servidor respondió ${response.statusCode} a PROPFIND.',
        statusCode: response.statusCode,
      );
    }
    final text = await response.transform(utf8.decoder).join();
    return parseMultiStatus(text, base: url).where((entry) {
      // El propio directorio viene en la respuesta: se filtra.
      final self = url.path.endsWith('/') ? url.path : '${url.path}/';
      final path = entry.url.path.endsWith('/') ? entry.url.path : '${entry.url.path}/';
      return path != self;
    }).toList();
  }

  /// Interpreta un `207 Multi-Status`.
  static List<RemoteEntry> parseMultiStatus(String xml, {required Uri base}) {
    final entries = <RemoteEntry>[];
    final responsePattern =
        RegExp(r'<(?:[A-Za-z0-9]+:)?response\b[^>]*>([\s\S]*?)</(?:[A-Za-z0-9]+:)?response>');
    final hrefPattern =
        RegExp(r'<(?:[A-Za-z0-9]+:)?href\b[^>]*>([\s\S]*?)</(?:[A-Za-z0-9]+:)?href>');

    for (final match in responsePattern.allMatches(xml)) {
      final block = match.group(1) ?? '';
      final hrefMatch = hrefPattern.firstMatch(block);
      if (hrefMatch == null) continue;
      final rawHref = (hrefMatch.group(1) ?? '').trim();
      if (rawHref.isEmpty) continue;

      Uri? url;
      try {
        url = base.resolve(rawHref);
      } catch (_) {
        url = Uri.tryParse(rawHref);
      }
      if (url == null) continue;

      final isCollection = block.contains(':collection') ||
          RegExp(r'<collection\b').hasMatch(block);
      final segments = url.pathSegments.where((segment) => segment.isNotEmpty);
      final name = segments.isEmpty
          ? '/'
          : Uri.decodeComponent(segments.last);
      final lengthMatch = RegExp(
        r'<(?:[A-Za-z0-9]+:)?getcontentlength\b[^>]*>(\d+)<',
      ).firstMatch(block);

      entries.add(RemoteEntry(
        name: name,
        url: url,
        isCollection: isCollection,
        size: int.tryParse(lengthMatch?.group(1) ?? '') ?? 0,
      ));
    }
    return entries;
  }

  /// Baja un archivo remoto a [directory] y devuelve el archivo.
  Future<File> download(
    RemoteServer server,
    Uri url, {
    required Directory directory,
    void Function(int bytes)? onProgress,
  }) async {
    final request = await _client.getUrl(url);
    request.followRedirects = true;
    request.headers.set(HttpHeaders.userAgentHeader, 'CyberHex/1.0');
    _authHeaders(server).forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode >= 400) {
      throw RemoteException(
        'No se pudo descargar ${url.pathSegments.isEmpty ? url.host : url.pathSegments.last} '
        '(${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final name = url.pathSegments.isEmpty
        ? 'remoto-${url.host}'
        : Uri.decodeComponent(url.pathSegments.last);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final target = File('${directory.path}/$safe');
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    var bytes = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        bytes += chunk.length;
        onProgress?.call(bytes);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (bytes == 0) {
      await part.delete().catchError((_) => part);
      throw RemoteException('El servidor devolvió un archivo vacío.');
    }
    await part.rename(target.path);
    return target;
  }

  void close() => _client.close(force: true);
}

/// Servidores y enlaces guardados (`network.json`, escritura atómica).
class NetworkStore extends ChangeNotifier {
  NetworkStore({File? file})
      : file = file ?? File('${StorageDirectory.current.path}/network.json');

  NetworkStore.memory() : file = null;

  static const int formatVersion = 1;

  final File? file;

  final List<RemoteServer> _servers = <RemoteServer>[];
  bool _loaded = false;
  bool _dirty = false;
  Timer? _saveTimer;

  List<RemoteServer> get servers => List<RemoteServer>.unmodifiable(_servers);

  bool get isLoaded => _loaded;

  bool get isEmpty => _servers.isEmpty;

  RemoteServer add({
    required String name,
    required String url,
    RemoteKind kind = RemoteKind.webdav,
    String username = '',
    String password = '',
    String token = '',
  }) {
    final server = RemoteServer(
      id: 'n${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? (Uri.tryParse(url)?.host ?? url) : name.trim(),
      url: url.trim(),
      kind: kind,
      username: username.trim(),
      password: password,
      token: token.trim(),
    );
    _servers.add(server);
    _touch();
    return server;
  }

  bool remove(String id) {
    final before = _servers.length;
    _servers.removeWhere((server) => server.id == id);
    if (_servers.length == before) return false;
    _touch();
    return true;
  }

  bool update(RemoteServer server) {
    final index = _servers.indexWhere((item) => item.id == server.id);
    if (index < 0) return false;
    _servers[index] = server;
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
      final raw = await target.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final servers = decoded['servers'];
      if (servers is! List) return;
      _servers
        ..clear()
        ..addAll(servers.map(RemoteServer.fromJson).whereType<RemoteServer>());
      notifyListeners();
    } catch (_) {
      // JSON roto: se empieza sin servidores.
    }
  }

  void _touch() {
    _dirty = true;
    notifyListeners();
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
        'servers': <Object?>[for (final server in _servers) server.toJson()],
      };
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
      _dirty = false;
    } catch (_) {
      // Sin disco, los servidores duran la sesión.
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

/// Explorador de carpetas WebDAV y enlaces de nube.
///
/// Todo lo descargado se cachea en `StorageDirectory.current/cloud_cache` para
/// que el motor (que solo abre archivos) pueda reproducirlo.
class NetworkPage extends StatefulWidget {
  const NetworkPage({
    super.key,
    required this.store,
    required this.controller,
    this.client,
  });

  final NetworkStore store;
  final PlayerController controller;

  /// Inyectable en tests (apunta a un servidor local).
  final WebDavClient? client;

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  late final WebDavClient _client = widget.client ?? WebDavClient();
  late final Directory _cache =
      Directory('${StorageDirectory.current.path}/cloud_cache');

  RemoteServer? _server;
  Uri? _current;
  List<RemoteEntry> _entries = const <RemoteEntry>[];
  bool _loading = false;
  String? _message;
  String? _busyEntry;

  NetworkStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    if (widget.client == null) _client.close();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _say(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  Future<void> _open(RemoteServer server) async {
    final uri = server.uri;
    if (uri == null) {
      _say('La URL de ${server.name} no es válida.');
      return;
    }
    setState(() {
      _server = server;
      _current = uri;
      _entries = const <RemoteEntry>[];
      _message = null;
    });
    if (server.kind == RemoteKind.cloud) {
      _say('Enlace de nube: pulsa para descargar y reproducir.');
      return;
    }
    await _list(uri);
  }

  Future<void> _list(Uri uri) async {
    final server = _server;
    if (server == null) return;
    setState(() {
      _loading = true;
      _current = uri;
      _message = null;
    });
    try {
      final entries = await _client.list(server, uri);
      entries.sort((a, b) {
        if (a.isCollection != b.isCollection) return a.isCollection ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() => _entries = entries);
      if (entries.isEmpty) _say('Carpeta vacía.');
    } on RemoteException catch (error) {
      _say(error.message);
    } on SocketException catch (error) {
      _say('Sin conexión con ${server.uri?.host}: ${error.message}');
    } catch (error) {
      _say('No se pudo listar: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadAndPlay(RemoteEntry entry) async {
    final server = _server;
    if (server == null) return;
    setState(() {
      _busyEntry = entry.url.toString();
      _message = 'Descargando ${entry.name}…';
    });
    try {
      final file = await _client.download(server, entry.url, directory: _cache);
      final error = await widget.controller.openFile(file.path);
      if (error != null) {
        _say('El motor no pudo abrir ${entry.name}: $error');
        return;
      }
      widget.controller.play();
      _say('Sonando ${entry.name} (en caché).');
    } on RemoteException catch (error) {
      _say(error.message);
    } on SocketException catch (error) {
      _say('Sin conexión: ${error.message}');
    } catch (error) {
      _say('No se pudo descargar ${entry.name}: $error');
    } finally {
      if (mounted) setState(() => _busyEntry = null);
    }
  }

  Future<void> _openCloudLink() async {
    final server = _server;
    final uri = server?.uri;
    if (server == null || uri == null) return;
    await _downloadAndPlay(RemoteEntry(
      name: uri.pathSegments.isEmpty ? server.name : uri.pathSegments.last,
      url: uri,
      isCollection: false,
    ));
  }

  Future<void> _addServer() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final userController = TextEditingController();
    final passwordController = TextEditingController();
    final tokenController = TextEditingController();
    var kind = RemoteKind.webdav;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Servidor o enlace'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<RemoteKind>(
                  segments: [
                    for (final option in RemoteKind.values)
                      ButtonSegment<RemoteKind>(
                        value: option,
                        label: Text(option.label, style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                  selected: <RemoteKind>{kind},
                  onSelectionChanged: (selection) =>
                      setDialogState(() => kind = selection.first),
                ),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                TextField(
                  controller: urlController,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: kind == RemoteKind.cloud
                        ? 'Enlace de descarga'
                        : 'URL de la carpeta WebDAV',
                    hintText: kind == RemoteKind.cloud
                        ? 'https://host/s/abc123/download'
                        : 'https://nube.ejemplo/remote.php/dav/files/usuario/Música',
                  ),
                ),
                if (kind == RemoteKind.webdav) ...[
                  TextField(
                    controller: userController,
                    decoration: const InputDecoration(labelText: 'Usuario'),
                  ),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña o clave de aplicación',
                    ),
                  ),
                ],
                TextField(
                  controller: tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Token Bearer (opcional; sustituye a usuario)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (accepted == true && urlController.text.trim().isNotEmpty) {
      _store.add(
        name: nameController.text,
        url: urlController.text,
        kind: kind,
        username: userController.text,
        password: passwordController.text,
        token: tokenController.text,
      );
    }
    nameController.dispose();
    urlController.dispose();
    userController.dispose();
    passwordController.dispose();
    tokenController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final server = _server;
    return Scaffold(
      appBar: AppBar(
        title: Text(server == null ? 'Red y nube' : server.name),
        leading: server == null
            ? null
            : IconButton(
                tooltip: 'Volver a servidores',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() {
                  _server = null;
                  _entries = const <RemoteEntry>[];
                  _message = null;
                }),
              ),
        actions: [
          if (server != null && server.kind == RemoteKind.webdav)
            IconButton(
              tooltip: 'Subir un nivel',
              onPressed: () {
                final current = _current;
                if (current == null) return;
                final segments = current.pathSegments.where((s) => s.isNotEmpty).toList();
                if (segments.length <= 1) return;
                final parentPath = '/${segments.take(segments.length - 1).join('/')}/';
                unawaited(_list(current.replace(path: parentPath)));
              },
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          IconButton(
            tooltip: 'Añadir servidor o enlace',
            onPressed: _addServer,
            icon: const Icon(Icons.add_link_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) LinearProgressIndicator(minHeight: 2, color: palette.accent),
          Expanded(child: server == null ? _serversView(palette) : _browserView(palette, server)),
          MiniPlayer(
            controller: widget.controller,
            onOpen: () => Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
    );
  }

  Widget _serversView(CyberHexPalette palette) {
    final servers = _store.servers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (_message != null) _messageLine(palette),
        if (servers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Text(
              'Sin servidores. Añade una carpeta WebDAV (Nextcloud, ownCloud, '
              'Synology…) o un enlace directo de nube.',
              style: TextStyle(fontSize: 12, color: palette.muted, height: 1.5),
            ),
          ),
        for (final item in servers)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            leading: Icon(
              item.kind == RemoteKind.cloud ? Icons.cloud_rounded : Icons.dns_rounded,
              color: palette.accent,
            ),
            title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${item.kind.label} · ${item.uri?.host ?? item.url}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'Más',
              onSelected: (value) {
                if (value == 'open') unawaited(_open(item));
                if (value == 'delete') _store.remove(item.id);
              },
              itemBuilder: (context) => const [
                PopupMenuItem<String>(value: 'open', child: Text('Abrir')),
                PopupMenuItem<String>(value: 'delete', child: Text('Quitar')),
              ],
            ),
            onTap: () => unawaited(_open(item)),
          ),
        const SizedBox(height: 12),
        Text(
          'Las credenciales se guardan en `network.json` en claro: usa una clave '
          'de aplicación del servidor, no la contraseña principal.',
          style: TextStyle(fontSize: 11, color: palette.muted, height: 1.5),
        ),
      ],
    );
  }

  Widget _browserView(CyberHexPalette palette, RemoteServer server) {
    if (server.kind == RemoteKind.cloud) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (_message != null) _messageLine(palette),
          ListTile(
            leading: Icon(Icons.cloud_download_rounded, color: palette.accent),
            title: const Text('Descargar y reproducir'),
            subtitle: Text(
              server.url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
            onTap: _busyEntry == null ? () => unawaited(_openCloudLink()) : null,
          ),
          if (_busyEntry != null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (_message != null) _messageLine(palette),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(
            _current?.path ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: palette.muted),
          ),
        ),
        for (final entry in _entries)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 6),
            leading: Icon(
              entry.isCollection
                  ? Icons.folder_rounded
                  : entry.isAudio
                      ? Icons.audio_file_rounded
                      : Icons.insert_drive_file_outlined,
              color: entry.isAudio ? palette.accent : palette.muted,
            ),
            title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: entry.sizeLabel.isEmpty
                ? null
                : Text(
                    entry.sizeLabel,
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
            trailing: _busyEntry == entry.url.toString()
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: () {
              if (entry.isCollection) {
                unawaited(_list(entry.url));
              } else if (entry.isAudio) {
                unawaited(_downloadAndPlay(entry));
              } else {
                _say('${entry.name} no es un formato de audio conocido.');
              }
            },
          ),
        if (_entries.isEmpty && !_loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Text(
              'Nada que mostrar aquí.',
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ),
      ],
    );
  }

  Widget _messageLine(CyberHexPalette palette) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          _message!,
          style: TextStyle(fontSize: 12, color: palette.accent),
        ),
      );
}
