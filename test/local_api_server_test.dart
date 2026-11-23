import 'dart:convert';
import 'dart:io';

import 'package:cyberhex/core/player_api.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/platform/local_api_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

void main() {
  test(
    'local API authenticates and controls only indexed library tracks',
    () async {
      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Canción'
        ..duration = 120
        ..library = [LibraryTrack.fromPath('/music/cancion.flac')];
      final controller = PlayerController(fake);
      controller.pump();
      await controller.scanDirectory('/music');
      final api = CyberHexLocalApi(
        controller: controller,
        apiKey: 'secret',
        port: 0,
      );
      final client = HttpClient();
      await api.start();
      addTearDown(() async {
        client.close(force: true);
        await api.close();
        controller.dispose();
      });

      final baseUri = api.baseUri!;
      final unauthenticated = await client.getUrl(
        baseUri.replace(path: '/api/v1/status'),
      );
      final denied = await unauthenticated.close();
      expect(denied.statusCode, HttpStatus.unauthorized);
      await denied.drain<void>();

      final status = await _get(client, baseUri, '/api/v1/status');
      expect(status['title'], 'Canción');
      expect(status['hasTrack'], isTrue);

      final addTrack = await _post(client, baseUri, '/api/v1/queue', {
        'action': 'add',
        'path': '/music/cancion.flac',
      });
      expect(addTrack.statusCode, HttpStatus.ok);
      await addTrack.drain<void>();

      final rejectUnindexed = await _post(client, baseUri, '/api/v1/queue', {
        'action': 'add',
        'path': '/private/other.mp3',
      });
      expect(rejectUnindexed.statusCode, HttpStatus.badRequest);
      await rejectUnindexed.drain<void>();

      final seek = await _post(client, baseUri, '/api/v1/command', {
        'action': 'seek',
        'positionSeconds': 35,
      });
      expect(seek.statusCode, HttpStatus.ok);
      await seek.drain<void>();
      expect(controller.position.value, 35);

      final invalidVolume = await _post(client, baseUri, '/api/v1/volume', {
        'value': 2,
      });
      expect(invalidVolume.statusCode, HttpStatus.badRequest);
      await invalidVolume.drain<void>();
    },
  );

  test('MCP exposes playback, library, queue and control tools', () async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Tema'
      ..library = [LibraryTrack.fromPath('/music/tema.mp3')];
    final controller = PlayerController(fake);
    controller.pump();
    await controller.scanDirectory('/music');
    final api = CyberHexLocalApi(
      controller: controller,
      apiKey: 'secret',
      port: 0,
    );
    final client = HttpClient();
    await api.start();
    addTearDown(() async {
      client.close(force: true);
      await api.close();
      controller.dispose();
    });

    final response = await _mcp(client, api.baseUri!, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
      'params': {},
    });
    final result = response['result'] as Map<String, dynamic>;
    final tools = result['tools'] as List<dynamic>;
    expect(
      tools.map((tool) => (tool as Map<String, dynamic>)['name']),
      containsAll([
        'cyberhex_status',
        'cyberhex_search_library',
        'cyberhex_queue',
        'cyberhex_control',
        'cyberhex_queue_add',
      ]),
    );

    final call = await _mcp(client, api.baseUri!, {
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/call',
      'params': {
        'name': 'cyberhex_control',
        'arguments': {'action': 'play'},
      },
    });
    expect((call['result'] as Map)['isError'], isFalse);
    expect(fake.isPlaying, isTrue);
  });
}

Future<Map<String, dynamic>> _get(
  HttpClient client,
  Uri baseUri,
  String path,
) async {
  final request = await client.getUrl(baseUri.replace(path: path));
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer secret');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  expect(response.statusCode, HttpStatus.ok);
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<HttpClientResponse> _post(
  HttpClient client,
  Uri baseUri,
  String path,
  Map<String, Object?> body,
) async {
  final request = await client.postUrl(baseUri.replace(path: path));
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer secret')
    ..contentType = ContentType.json;
  request.write(jsonEncode(body));
  return request.close();
}

Future<Map<String, dynamic>> _mcp(
  HttpClient client,
  Uri baseUri,
  Map<String, Object?> body,
) async {
  final request = await client.postUrl(baseUri.replace(path: '/mcp'));
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer secret')
    ..contentType = ContentType.json;
  request.write(jsonEncode(body));
  final response = await request.close();
  final content = await response.transform(utf8.decoder).join();
  expect(response.statusCode, HttpStatus.ok);
  return jsonDecode(content) as Map<String, dynamic>;
}
