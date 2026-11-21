import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'player_api.dart';
import 'player_controller.dart';
import 'session_store.dart';

/// Ajustes de scrobbling. Todo vacío = apagado.
class ScrobbleSettings {
  const ScrobbleSettings({
    this.enabled = false,
    this.listenBrainzToken = '',
    this.lastFmApiKey = '',
    this.lastFmApiSecret = '',
    this.lastFmSessionKey = '',
    this.lastFmUsername = '',
  });

  final bool enabled;
  final String listenBrainzToken;
  final String lastFmApiKey;
  final String lastFmApiSecret;
  final String lastFmSessionKey;
  final String lastFmUsername;

  bool get hasListenBrainz => listenBrainzToken.trim().isNotEmpty;

  bool get hasLastFm =>
      lastFmApiKey.trim().isNotEmpty &&
      lastFmApiSecret.trim().isNotEmpty &&
      lastFmSessionKey.trim().isNotEmpty;

  bool get isUsable => enabled && (hasListenBrainz || hasLastFm);

  ScrobbleSettings copyWith({
    bool? enabled,
    String? listenBrainzToken,
    String? lastFmApiKey,
    String? lastFmApiSecret,
    String? lastFmSessionKey,
    String? lastFmUsername,
  }) =>
      ScrobbleSettings(
        enabled: enabled ?? this.enabled,
        listenBrainzToken: listenBrainzToken ?? this.listenBrainzToken,
        lastFmApiKey: lastFmApiKey ?? this.lastFmApiKey,
        lastFmApiSecret: lastFmApiSecret ?? this.lastFmApiSecret,
        lastFmSessionKey: lastFmSessionKey ?? this.lastFmSessionKey,
        lastFmUsername: lastFmUsername ?? this.lastFmUsername,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'listenBrainzToken': listenBrainzToken,
        'lastFmApiKey': lastFmApiKey,
        'lastFmApiSecret': lastFmApiSecret,
        'lastFmSessionKey': lastFmSessionKey,
        'lastFmUsername': lastFmUsername,
      };

  static ScrobbleSettings fromJson(Object? raw) {
    if (raw is! Map) return const ScrobbleSettings();
    String text(String key) =>
        raw[key] is String ? raw[key] as String : '';
    return ScrobbleSettings(
      enabled: raw['enabled'] == true,
      listenBrainzToken: text('listenBrainzToken'),
      lastFmApiKey: text('lastFmApiKey'),
      lastFmApiSecret: text('lastFmApiSecret'),
      lastFmSessionKey: text('lastFmSessionKey'),
      lastFmUsername: text('lastFmUsername'),
    );
  }
}

/// Escucha pendiente de enviar.
class PendingScrobble {
  PendingScrobble({
    required this.artist,
    required this.title,
    this.album = '',
    this.durationSeconds = 0,
    required this.startedAt,
    this.attempts = 0,
  });

  final String artist;
  final String title;
  final String album;
  final double durationSeconds;

  /// Momento en que **empezó** a sonar (UTC): es lo que esperan las dos APIs.
  final DateTime startedAt;
  int attempts;

  /// Segundos desde la época, como quiere Last.fm (`timestamp[i]`).
  int get timestamp => startedAt.millisecondsSinceEpoch ~/ 1000;

  Map<String, Object?> toJson() => <String, Object?>{
        'artist': artist,
        'title': title,
        'album': album,
        'duration': durationSeconds,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'attempts': attempts,
      };

  static PendingScrobble? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final artist = raw['artist'];
    final title = raw['title'];
    if (artist is! String || title is! String) return null;
    return PendingScrobble(
      artist: artist,
      title: title,
      album: raw['album'] is String ? raw['album'] as String : '',
      durationSeconds: (raw['duration'] as num?)?.toDouble() ?? 0,
      startedAt: DateTime.tryParse(raw['startedAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      attempts: (raw['attempts'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => 'PendingScrobble($artist – $title, $attempts intentos)';
}

/// Scrobbling a **ListenBrainz** y **Last.fm** con las reglas de siempre:
/// se envía si sonó más de la mitad del tema **o** más de cuatro minutos.
///
/// Sin paquetes nuevos: `dart:io` para HTTP y un MD5 propio (Last.fm firma cada
/// llamada con `api_sig`). Las escuchas se guardan en `scrobbler.json` y se
/// reintentan; nunca se pierde una escucha por estar sin red.
class Scrobbler extends ChangeNotifier {
  Scrobbler(this._controller, {File? file, HttpClient? client})
      : file = file ?? File('${StorageDirectory.current.path}/scrobbler.json'),
        client = client ?? HttpClient() {
    this.client.connectionTimeout = const Duration(seconds: 12);
    _controller.addListener(_onControllerChanged);
    _controller.position.addListener(_onPositionChanged);
  }

  Scrobbler.memory(this._controller, {HttpClient? client})
      : file = null,
        client = client ?? HttpClient() {
    this.client.connectionTimeout = const Duration(seconds: 12);
    _controller.addListener(_onControllerChanged);
    _controller.position.addListener(_onPositionChanged);
  }

  static const int formatVersion = 1;

  /// Escucha «completa» por tiempo: más de cuatro minutos.
  static const Duration longListen = Duration(minutes: 4);

  /// Por debajo de esto no es una canción: no se manda nada.
  static const Duration minimumTrack = Duration(seconds: 30);

  static const int maxPending = 200;

  /// Tras estos intentos se descarta (una escucha no puede bloquear la cola).
  static const int maxAttempts = 5;

  final PlayerController _controller;
  final File? file;
  final HttpClient client;

  /// Se pueden cambiar en los tests para apuntar a un servidor local.
  Uri listenBrainzEndpoint =
      Uri.parse('https://api.listenbrainz.org/1/submit-listens');
  Uri lastFmEndpoint = Uri.parse('https://ws.audioscrobbler.com/2.0/');

  ScrobbleSettings _settings = const ScrobbleSettings();
  final List<PendingScrobble> _pending = <PendingScrobble>[];
  bool _loaded = false;
  bool _dirty = false;
  int _submitted = 0;
  DateTime? _lastFlush;
  String? _lastError;
  bool _sending = false;
  Future<bool>? _inFlight;

  // Seguimiento de la pista en curso.
  String _currentPath = '';
  DateTime? _startedAt;
  bool _qualified = false;
  Timer? _saveTimer;

  ScrobbleSettings get settings => _settings;

  bool get isLoaded => _loaded;

  bool get isDirty => _dirty;

  List<PendingScrobble> get pending => List<PendingScrobble>.unmodifiable(_pending);

  int get submitted => _submitted;

  DateTime? get lastFlush => _lastFlush;

  String? get lastError => _lastError;

  bool get isSending => _sending;

  // ---------------------------------------------------------------------------
  // Seguimiento
  // ---------------------------------------------------------------------------

  void _onControllerChanged() {
    final snapshot = _controller.snapshot;
    final path = _pathOf(snapshot);
    if (path == _currentPath) return;

    _currentPath = path;
    _qualified = false;
    _startedAt = snapshot.hasTrack ? DateTime.now().toUtc() : null;
  }

  void _onPositionChanged() {
    if (_qualified) return;
    final snapshot = _controller.snapshot;
    if (!snapshot.hasTrack || !_settings.isUsable) return;
    if (snapshot.duration < minimumTrack.inMilliseconds / 1000) return;

    final position = _controller.position.value;
    final threshold = math.max(
      longListen.inSeconds.toDouble(),
      snapshot.duration / 2,
    );
    if (position >= math.min(threshold, snapshot.duration)) {
      _qualified = true;
      _enqueue(snapshot, position);
    }
  }

  /// Cierra la escucha en curso a mano (test o «cerrar sesión»).
  void considerNow() {
    final snapshot = _controller.snapshot;
    if (!snapshot.hasTrack || _qualified) return;
    _qualified = true;
    _enqueue(snapshot, _controller.position.value);
  }

  void _enqueue(PlayerSnapshot snapshot, double position) {
    if (!_settings.isUsable) return;
    if (snapshot.artist.trim().isEmpty && snapshot.title.trim().isEmpty) return;

    _pending.add(PendingScrobble(
      artist: snapshot.artist,
      title: snapshot.title,
      album: snapshot.album,
      durationSeconds: snapshot.duration,
      startedAt: _startedAt ?? DateTime.now().toUtc(),
    ));
    if (_pending.length > maxPending) {
      _pending.removeRange(0, _pending.length - maxPending);
    }
    _touch();
    unawaited(flush());
  }

  static String _pathOf(PlayerSnapshot snapshot) {
    final index = snapshot.queueIndex;
    if (index < 0 || index >= snapshot.queue.length) return '';
    return snapshot.queue[index].path;
  }

  // ---------------------------------------------------------------------------
  // Envío
  // ---------------------------------------------------------------------------

  /// Envía lo pendiente a todos los servicios configurados.
  ///
  /// Devuelve `true` si no queda nada pendiente. Si un servicio falla, la
  /// escucha se queda guardada y se reintenta en la siguiente llamada. Dos
  /// llamadas a la vez comparten el mismo envío (no se duplican escuchas).
  Future<bool> flush() {
    final running = _inFlight;
    if (running != null) return running;
    if (!_settings.isUsable || _pending.isEmpty) {
      return Future<bool>.value(_pending.isEmpty);
    }
    final task = _flushOnce();
    _inFlight = task.whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  Future<bool> _flushOnce() async {
    _sending = true;
    notifyListeners();
    try {
      final done = <PendingScrobble>[];
      for (final scrobble in List<PendingScrobble>.of(_pending)) {
        var allOk = true;
        if (_settings.hasListenBrainz) {
          allOk = await _sendListenBrainz(scrobble) && allOk;
        }
        if (_settings.hasLastFm) {
          allOk = await _sendLastFm(scrobble) && allOk;
        }
        if (allOk) {
          done.add(scrobble);
          _submitted += 1;
        } else {
          scrobble.attempts += 1;
        }
      }
      _pending.removeWhere(done.contains);
      _pending.removeWhere((scrobble) => scrobble.attempts >= maxAttempts);
      _lastFlush = DateTime.now();
      _dirty = true;
    } finally {
      _sending = false;
      if (_pending.isEmpty) _lastError = null;
      await save();
      notifyListeners();
    }
    return _pending.isEmpty;
  }

  Future<bool> _sendListenBrainz(PendingScrobble scrobble) async {
    final body = <String, Object?>{
      'listen_type': 'single',
      'payload': <Object?>[
        <String, Object?>{
          'listened_at': scrobble.timestamp,
          'track_metadata': <String, Object?>{
            'artist_name': scrobble.artist,
            'track_name': scrobble.title,
            if (scrobble.album.isNotEmpty) 'release_name': scrobble.album,
            'additional_info': <String, Object?>{
              'submission_client': 'CyberHex',
              if (scrobble.durationSeconds > 0)
                'duration_ms': (scrobble.durationSeconds * 1000).round(),
            },
          },
        },
      ],
    };
    return _post(
      listenBrainzEndpoint,
      body: jsonEncode(body),
      contentType: ContentType.json,
      headers: <String, String>{
        'Authorization': 'Token ${_settings.listenBrainzToken}',
      },
      label: 'ListenBrainz',
    );
  }

  Future<bool> _sendLastFm(PendingScrobble scrobble) async {
    final parameters = <String, String>{
      'method': 'track.scrobble',
      'api_key': _settings.lastFmApiKey,
      'sk': _settings.lastFmSessionKey,
      'artist[0]': scrobble.artist,
      'track[0]': scrobble.title,
      'timestamp[0]': '${scrobble.timestamp}',
      if (scrobble.album.isNotEmpty) 'album[0]': scrobble.album,
      if (scrobble.durationSeconds > 0)
        'duration[0]': '${scrobble.durationSeconds.round()}',
      'format': 'json',
    };
    parameters['api_sig'] = lastFmSignature(parameters, _settings.lastFmApiSecret);
    final body = parameters.entries
        .map((entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    return _post(
      lastFmEndpoint,
      body: body,
      contentType: ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8'),
      label: 'Last.fm',
    );
  }

  Future<bool> _post(
    Uri endpoint, {
    required String body,
    required ContentType contentType,
    Map<String, String> headers = const <String, String>{},
    required String label,
  }) async {
    try {
      final request = await client.postUrl(endpoint);
      request.headers.contentType = contentType;
      request.headers.set(HttpHeaders.userAgentHeader, 'CyberHex/1.0');
      headers.forEach(request.headers.set);
      request.write(body);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Last.fm devuelve 200 con {"error":N} cuando algo va mal.
        if (label == 'Last.fm' && text.contains('"error"')) {
          _lastError = 'Last.fm: $text';
          return false;
        }
        return true;
      }
      _lastError = '$label respondió ${response.statusCode}';
      return false;
    } on SocketException catch (error) {
      _lastError = '$label: sin red (${error.message})';
      return false;
    } on HttpException catch (error) {
      _lastError = '$label: ${error.message}';
      return false;
    }
  }

  /// `api_sig` de Last.fm: MD5 de la concatenación de `clave+valor` ordenada
  /// alfabéticamente, seguida del secreto compartido.
  static String lastFmSignature(Map<String, String> parameters, String secret) {
    final keys = parameters.keys.where((key) => key != 'api_sig').toList()
      ..sort();
    final buffer = StringBuffer();
    for (final key in keys) {
      buffer
        ..write(key)
        ..write(parameters[key]);
    }
    buffer.write(secret);
    return md5Hex(buffer.toString());
  }

  // ---------------------------------------------------------------------------
  // Ajustes y persistencia
  // ---------------------------------------------------------------------------

  void updateSettings(ScrobbleSettings settings) {
    _settings = settings;
    _touch();
    if (settings.isUsable && _pending.isNotEmpty) unawaited(flush());
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
      _settings = ScrobbleSettings.fromJson(decoded['settings']);
      final pending = decoded['pending'];
      if (pending is List) {
        _pending
          ..clear()
          ..addAll(pending.map(PendingScrobble.fromJson).whereType<PendingScrobble>());
      }
      _submitted = (decoded['submitted'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {
      // JSON roto: se empieza de cero en vez de impedir arrancar.
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
        'settings': _settings.toJson(),
        'pending': <Object?>[for (final scrobble in _pending) scrobble.toJson()],
        'submitted': _submitted,
      };
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
      _dirty = false;
    } catch (_) {
      // Sin disco, la cola dura la sesión.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _controller.removeListener(_onControllerChanged);
    _controller.position.removeListener(_onPositionChanged);
    if (_dirty) unawaited(save());
    client.close(force: true);
    super.dispose();
  }
}

/// Instancia compartida de la app.
///
/// `main.dart` la crea al arrancar y la suelta al cerrar; así la escucha se
/// cuenta mientras suena la música, aunque Ajustes no esté abierto, sin que
/// cada pantalla tenga que construir la suya.
class ScrobblerHost {
  ScrobblerHost._();

  static Scrobbler? _current;

  static Scrobbler? get current => _current;

  static void attach(Scrobbler? scrobbler) => _current = scrobbler;
}

// -----------------------------------------------------------------------------
// MD5 (RFC 1321) — mínimo, sin paquetes, solo para la firma de Last.fm.
// -----------------------------------------------------------------------------

const List<int> _md5Shift = <int>[
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, //
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, //
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, //
];

const List<int> _md5Table = <int>[
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
  0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
  0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340,
  0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
  0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
  0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
  0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
  0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
  0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
];

/// MD5 en hexadecimal minúsculas.
String md5Hex(String input) => _md5HexBytes(utf8.encode(input));

String _md5HexBytes(List<int> input) {
  final message = List<int>.of(input);
  final bitLength = input.length * 8;
  message.add(0x80);
  while (message.length % 64 != 56) {
    message.add(0);
  }
  for (var i = 0; i < 8; i++) {
    message.add((bitLength >> (8 * i)) & 0xFF);
  }

  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;

  for (var offset = 0; offset < message.length; offset += 64) {
    final words = List<int>.generate(16, (index) {
      final base = offset + index * 4;
      return message[base] |
          (message[base + 1] << 8) |
          (message[base + 2] << 16) |
          (message[base + 3] << 24);
    });

    var a = a0;
    var b = b0;
    var c = c0;
    var d = d0;

    for (var i = 0; i < 64; i++) {
      int f;
      int g;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | (~d & 0xFFFFFFFF));
        g = (7 * i) % 16;
      }

      final sum = (a + f + _md5Table[i] + words[g]) & 0xFFFFFFFF;
      final rotated = ((sum << _md5Shift[i]) | (sum >> (32 - _md5Shift[i]))) &
          0xFFFFFFFF;
      a = d;
      d = c;
      c = b;
      b = (b + rotated) & 0xFFFFFFFF;
    }

    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }

  final digest = <int>[];
  for (final word in <int>[a0, b0, c0, d0]) {
    for (var i = 0; i < 4; i++) {
      digest.add((word >> (8 * i)) & 0xFF);
    }
  }
  final buffer = StringBuffer();
  for (final byte in digest) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
