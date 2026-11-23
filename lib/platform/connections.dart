import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/player_controller.dart';
import 'local_api_server.dart';

class CyberHexConnections extends ChangeNotifier {
  CyberHexConnections({FlutterSecureStorage? storage, http.Client? client})
    : _storage = storage ?? const FlutterSecureStorage(),
      _client = client ?? http.Client();

  static const _apiKeyStorageKey = 'cyberhex.local_api_key';
  static const _studyUrlStorageKey = 'cyberhex.study_mcp_url';
  static const _studyKeyStorageKey = 'cyberhex.study_mcp_key';
  static const defaultStudyMcpUrl = 'http://127.0.0.1:8090/mcp';

  final FlutterSecureStorage _storage;
  final http.Client _client;

  CyberHexLocalApi? _localApi;
  String? _localApiKey;
  String? _localApiError;
  String _studyMcpUrl = defaultStudyMcpUrl;
  String _studyMcpKey = '';
  int _rpcId = 0;
  bool _initialized = false;
  bool _disposed = false;

  bool get initialized => _initialized;
  String? get localApiKey => _localApiKey;
  String? get localApiError => _localApiError;
  String? get localApiUrl => _localApi?.baseUri?.toString();
  String get studyMcpUrl => _studyMcpUrl;
  String get studyMcpKey => _studyMcpKey;
  bool get studyConfigured => _studyMcpKey.isNotEmpty;

  Future<void> initialize(PlayerController controller) async {
    try {
      _localApiKey = await _storage.read(key: _apiKeyStorageKey);
      if (_localApiKey == null || _localApiKey!.isEmpty) {
        _localApiKey = CyberHexLocalApi.generateApiKey();
        await _storage.write(key: _apiKeyStorageKey, value: _localApiKey);
      }
      _studyMcpUrl =
          await _storage.read(key: _studyUrlStorageKey) ?? defaultStudyMcpUrl;
      _studyMcpKey = await _storage.read(key: _studyKeyStorageKey) ?? '';

      final api = CyberHexLocalApi(
        controller: controller,
        apiKey: _localApiKey!,
      );
      await api.start();
      _localApi = api;
    } on SocketException catch (error) {
      _localApiError = 'No se pudo iniciar la API local: ${error.message}';
    } on PlatformException catch (error) {
      _localApiError = 'No se pudo acceder al almacenamiento seguro: $error';
    }
    _initialized = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> saveStudyPlatform({
    required String url,
    required String apiKey,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host) ||
        uri.path != '/mcp' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Usa localhost en una URL http(s) que termine exactamente en /mcp.',
      );
    }
    if (apiKey.trim().isEmpty) {
      throw const FormatException(
        'La API key de Study Platform es obligatoria.',
      );
    }
    await _storage.write(key: _studyUrlStorageKey, value: uri.toString());
    await _storage.write(key: _studyKeyStorageKey, value: apiKey.trim());
    _studyMcpUrl = uri.toString();
    _studyMcpKey = apiKey.trim();
    if (!_disposed) notifyListeners();
  }

  Future<void> testStudyPlatform() async {
    await _rpc('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'cyberhex', 'version': '1.0.0'},
    });
    final result = await _rpc('tools/list', const {});
    if (result['tools'] is! List) {
      throw const HttpException(
        'Study Platform no devolvió una lista de tools.',
      );
    }
  }

  Future<Object?> callStudyTool(
    String name, {
    Map<String, Object?> arguments = const {},
  }) async {
    final result = await _rpc('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    if (result['isError'] == true) {
      final content = result['content'];
      final message = content is List && content.isNotEmpty
          ? (content.first as Map)['text']?.toString()
          : null;
      throw HttpException(message ?? 'La herramienta $name falló.');
    }
    final content = result['content'];
    if (content is List && content.isNotEmpty) {
      final text = (content.first as Map)['text'];
      if (text is String) {
        try {
          return jsonDecode(text);
        } on FormatException {
          return text;
        }
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _rpc(
    String method,
    Map<String, Object?> params,
  ) async {
    final uri = Uri.parse(_studyMcpUrl);
    final response = await _client
        .post(
          uri,
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            'X-API-Key': _studyMcpKey,
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': ++_rpcId,
            'method': method,
            'params': params,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Study Platform devolvió HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respuesta MCP no válida.');
    }
    final error = decoded['error'];
    if (error is Map) {
      throw HttpException(
        error['message']?.toString() ?? 'Error MCP ${error['code']}.',
        uri: uri,
      );
    }
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) {
      throw const FormatException('La respuesta MCP no contiene result.');
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _localApi?.close();
    _client.close();
    super.dispose();
  }
}
