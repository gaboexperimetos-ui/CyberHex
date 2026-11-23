import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/player_controller.dart';

class CyberHexLocalApi {
  CyberHexLocalApi({
    required this._controller,
    required this._apiKey,
    int port = defaultPort,
  }) : _requestedPort = port;

  static const int defaultPort = 8765;
  static const int _maxBodyBytes = 16 * 1024;
  static const String _basePath = '/api/v1';

  final PlayerController _controller;
  final String _apiKey;
  final int _requestedPort;
  HttpServer? _server;

  int? get port => _server?.port;

  Uri? get baseUri => _server == null
      ? null
      : Uri(scheme: 'http', host: '127.0.0.1', port: port!);

  static String generateApiKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _requestedPort,
      shared: false,
    );
    _server!.listen((request) {
      unawaited(_handle(request));
    });
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    if (!_authorized(request)) {
      await _respond(request.response, HttpStatus.unauthorized, {
        'error': 'unauthorized',
      });
      return;
    }

    if (request.uri.path == '/mcp') {
      if (request.method != 'POST') {
        await _respond(request.response, HttpStatus.methodNotAllowed, {
          'error': 'method_not_allowed',
        });
        return;
      }
      await _handleMcp(request);
      return;
    }

    final path = request.uri.path;
    if (request.method == 'GET' && path == '$_basePath/status') {
      await _respond(request.response, HttpStatus.ok, _status());
      return;
    }
    if (request.method == 'GET' && path == '$_basePath/library') {
      await _respond(request.response, HttpStatus.ok, _library(request.uri));
      return;
    }
    if (request.method == 'GET' && path == '$_basePath/queue') {
      await _respond(request.response, HttpStatus.ok, _queue());
      return;
    }
    if (request.method != 'POST') {
      await _respond(request.response, HttpStatus.notFound, {
        'error': 'not_found',
      });
      return;
    }

    Object? body;
    try {
      body = await _readBody(request);
    } on _PayloadTooLarge {
      await _respond(request.response, HttpStatus.requestEntityTooLarge, {
        'error': 'request_body_too_large',
      });
      return;
    } on FormatException {
      await _respond(request.response, HttpStatus.badRequest, {
        'error': 'invalid_json',
      });
      return;
    }
    if (body is! Map<String, dynamic>) {
      await _respond(request.response, HttpStatus.badRequest, {
        'error': 'expected_json_object',
      });
      return;
    }
    final result = switch (path) {
      '$_basePath/command' => _command(body),
      '$_basePath/volume' => _volume(body),
      '$_basePath/queue' => _queueCommand(body),
      _ => const _ApiResult(HttpStatus.notFound, {'error': 'not_found'}),
    };
    await _respond(request.response, result.status, result.body);
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Bearer ')) return false;
    final candidate = header.substring(7);
    if (candidate.length != _apiKey.length) return false;
    var difference = 0;
    for (var i = 0; i < _apiKey.length; i++) {
      difference |= candidate.codeUnitAt(i) ^ _apiKey.codeUnitAt(i);
    }
    return difference == 0;
  }

  Map<String, Object?> _status() {
    final snapshot = _controller.snapshot;
    return {
      'hasTrack': snapshot.hasTrack,
      'title': snapshot.title,
      'artist': snapshot.artist,
      'album': snapshot.album,
      'playing': snapshot.playing,
      'positionSeconds': _controller.position.value,
      'durationSeconds': snapshot.duration,
      'volume': snapshot.volume,
      'queueCount': snapshot.queue.length,
      'queueIndex': snapshot.queueIndex,
      'repeatMode': snapshot.repeatMode,
      'shuffle': snapshot.shuffle,
    };
  }

  Map<String, Object?> _library(Uri uri) {
    final query = uri.queryParameters['q']?.trim().toLowerCase() ?? '';
    final tracks = _controller.libraryTracks
        .where((track) {
          return query.isEmpty ||
              track.title.toLowerCase().contains(query) ||
              track.path.toLowerCase().contains(query);
        })
        .map((track) => {'path': track.path, 'title': track.title})
        .toList();
    return {'tracks': tracks};
  }

  Map<String, Object?> _queue() {
    final snapshot = _controller.snapshot;
    return {
      'items': [
        for (final item in snapshot.queue)
          {'path': item.path, 'title': _trackTitle(item.path)},
      ],
      'index': snapshot.queueIndex,
    };
  }

  _ApiResult _command(Map<String, dynamic> body) {
    final action = body['action'];
    switch (action) {
      case 'play':
        _controller.play();
      case 'pause':
        _controller.pause();
      case 'toggle':
        _controller.toggle();
      case 'next':
        _controller.next();
      case 'previous':
        _controller.previous();
      case 'seek':
        final seconds = _number(body['positionSeconds']);
        if (seconds == null || seconds < 0) {
          return const _ApiResult(HttpStatus.badRequest, {
            'error': 'positionSeconds_must_be_nonnegative_number',
          });
        }
        _controller.seek(seconds);
      default:
        return const _ApiResult(HttpStatus.badRequest, {
          'error': 'unsupported_action',
        });
    }
    return const _ApiResult(HttpStatus.ok, {'ok': true});
  }

  _ApiResult _volume(Map<String, dynamic> body) {
    final value = _number(body['value']);
    if (value == null || value < 0 || value > 1) {
      return const _ApiResult(HttpStatus.badRequest, {
        'error': 'value_must_be_between_0_and_1',
      });
    }
    _controller.setVolume(value);
    return const _ApiResult(HttpStatus.ok, {'ok': true});
  }

  _ApiResult _queueCommand(Map<String, dynamic> body) {
    switch (body['action']) {
      case 'add':
        final path = body['path'];
        if (path is! String ||
            !_controller.libraryTracks.any((track) => track.path == path)) {
          return const _ApiResult(HttpStatus.badRequest, {
            'error': 'path_must_be_in_scanned_library',
          });
        }
        if (!_controller.enqueue(path)) {
          return const _ApiResult(HttpStatus.conflict, {
            'error': 'queue_add_failed',
          });
        }
      case 'play_index':
        final index = _integer(body['index']);
        if (index == null || !_controller.playAt(index)) {
          return const _ApiResult(HttpStatus.badRequest, {
            'error': 'invalid_queue_index',
          });
        }
      case 'remove':
        final index = _integer(body['index']);
        if (index == null || !_controller.removeQueueItem(index)) {
          return const _ApiResult(HttpStatus.badRequest, {
            'error': 'invalid_queue_index',
          });
        }
      case 'clear':
        _controller.clearQueue();
      default:
        return const _ApiResult(HttpStatus.badRequest, {
          'error': 'unsupported_action',
        });
    }
    return const _ApiResult(HttpStatus.ok, {'ok': true});
  }

  Future<void> _handleMcp(HttpRequest request) async {
    Object? body;
    try {
      body = await _readBody(request);
    } on _PayloadTooLarge {
      await _respond(request.response, HttpStatus.requestEntityTooLarge, {
        'error': 'request_body_too_large',
      });
      return;
    } on FormatException {
      await _respond(request.response, HttpStatus.badRequest, {
        'error': 'invalid_json',
      });
      return;
    }
    if (body is! Map<String, dynamic> || body['jsonrpc'] != '2.0') {
      await _respond(request.response, HttpStatus.badRequest, {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32600, 'message': 'Invalid Request'},
      });
      return;
    }
    final id = body['id'];
    final method = body['method'];
    if (id == null) {
      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
      return;
    }
    if (method == 'initialize') {
      await _respond(request.response, HttpStatus.ok, {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': '2025-03-26',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'cyberhex', 'version': '1.0.0'},
        },
      });
      return;
    }
    if (method == 'ping') {
      await _respond(request.response, HttpStatus.ok, {
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{},
      });
      return;
    }
    if (method == 'tools/list') {
      await _respond(request.response, HttpStatus.ok, {
        'jsonrpc': '2.0',
        'id': id,
        'result': {'tools': _tools},
      });
      return;
    }
    if (method == 'tools/call') {
      final params = body['params'];
      if (params is! Map<String, dynamic> || params['name'] is! String) {
        await _respond(request.response, HttpStatus.ok, {
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32602, 'message': 'Invalid params'},
        });
        return;
      }
      final arguments = params['arguments'];
      final result = _callTool(
        params['name'] as String,
        arguments is Map<String, dynamic> ? arguments : const {},
      );
      final isError = result.status >= 400;
      await _respond(request.response, HttpStatus.ok, {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'content': [
            {'type': 'text', 'text': jsonEncode(result.body)},
          ],
          'isError': isError,
        },
      });
      return;
    }
    await _respond(request.response, HttpStatus.ok, {
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': -32601, 'message': 'Method not found'},
    });
  }

  _ApiResult _callTool(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'cyberhex_status':
        return _ApiResult(HttpStatus.ok, _status());
      case 'cyberhex_search_library':
        final query = args['query'];
        if (query != null && query is! String) {
          return const _ApiResult(HttpStatus.badRequest, {
            'error': 'query_must_be_string',
          });
        }
        return _ApiResult(
          HttpStatus.ok,
          _library(Uri(queryParameters: {'q': query as String? ?? ''})),
        );
      case 'cyberhex_queue':
        return _ApiResult(HttpStatus.ok, _queue());
      case 'cyberhex_control':
        return _command(args);
      case 'cyberhex_queue_add':
        return _queueCommand({'action': 'add', 'path': args['path']});
      default:
        return const _ApiResult(HttpStatus.badRequest, {
          'error': 'unknown_tool',
        });
    }
  }

  static const List<Map<String, Object?>> _tools = [
    {
      'name': 'cyberhex_status',
      'description': 'Read current playback state and active track metadata.',
      'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
    },
    {
      'name': 'cyberhex_search_library',
      'description':
          'Search tracks in the local library already scanned in CyberHex.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Track title query.'},
        },
      },
    },
    {
      'name': 'cyberhex_queue',
      'description': 'Read the current playback queue.',
      'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
    },
    {
      'name': 'cyberhex_control',
      'description': 'Control playback or seek within the current track.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['play', 'pause', 'toggle', 'next', 'previous', 'seek'],
          },
          'positionSeconds': {
            'type': 'number',
            'description': 'Required only for seek.',
          },
        },
        'required': ['action'],
      },
    },
    {
      'name': 'cyberhex_queue_add',
      'description': 'Add a track from the scanned local library to the queue.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
      },
    },
  ];

  static Future<Object?> _readBody(HttpRequest request) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      if (bytes.length + chunk.length > _maxBodyBytes) {
        throw const _PayloadTooLarge();
      }
      bytes.add(chunk);
    }
    return jsonDecode(utf8.decode(bytes.takeBytes()));
  }

  static Future<void> _respond(
    HttpResponse response,
    int status,
    Object? body,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(jsonEncode(body));
    await response.close();
  }

  static double? _number(Object? value) {
    if (value is! num || !value.isFinite) return null;
    return value.toDouble();
  }

  static int? _integer(Object? value) =>
      value is int && value >= 0 ? value : null;

  static String _trackTitle(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }
}

class _ApiResult {
  const _ApiResult(this.status, this.body);

  final int status;
  final Object body;
}

class _PayloadTooLarge implements Exception {
  const _PayloadTooLarge();
}
