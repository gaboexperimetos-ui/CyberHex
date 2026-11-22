import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Resultado de una descarga.
class DownloadResult {
  const DownloadResult({
    required this.path,
    required this.bytes,
    required this.contentType,
  });

  final String path;
  final int bytes;
  final String contentType;
}

/// Descargador de música desde fuentes legales y sin anuncios.
///
/// Fuentes soportadas:
///  - URL directa que aporta el usuario (lo más simple y sin ToS).
///  - Jamendo (API pública; requiere `client_id`).
///  - Free Music Archive (API pública).
///
/// No implementa YouTube/Spotify/streaming con ToS: eso queda fuera por diseño.
class MusicDownloader {
  MusicDownloader({this.jamendoClientId});

  /// Client ID de Jamendo (opcional; solo para búsquedas por catálogo).
  final String? jamendoClientId;

  static const _jamendo = 'https://api.jamendo.com/v3.0';
  static const _fma = 'https://freemusicarchive.org';

  /// Descarga `url` a `destPath`. `referer` es opcional para fuentes que lo
  /// exijan. Devuelve el resultado o null si falla.
  Future<DownloadResult?> downloadUrl({
    required String url,
    required String destPath,
    String? referer,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (referer != null) request.headers['Referer'] = referer;
      final response = await http.Client().send(request).timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode != 200) return null;

      final file = File(destPath);
      await file.create(recursive: true);
      final sink = file.openWrite();
      var total = 0;
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        total += chunk.length;
      });
      await sink.close();
      return DownloadResult(
        path: destPath,
        bytes: total,
        contentType: response.headers['content-type'] ?? 'audio/mpeg',
      );
    } catch (_) {
      return null;
    }
  }

  /// Busca pistas en Jamendo (si hay `client_id`). Devuelve una lista de
  /// `{title, artist, audioUrl, imageUrl}`.
  Future<List<Map<String, String>>> searchJamendo(String query) async {
    if (jamendoClientId == null || jamendoClientId!.isEmpty) return const [];
    try {
      final uri = Uri.parse('$_jamendo/tracks/').replace(queryParameters: {
        'client_id': jamendoClientId!,
        'format': 'json',
        'search': query,
        'limit': '20',
        'audioformat': 'mp32',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final results = (map['results'] as List?) ?? const [];
      final out = <Map<String, String>>[];
      for (final r in results) {
        final m = r as Map<String, dynamic>;
        final audio = (m['audio'] ?? '') as String;
        if (audio.isEmpty) continue;
        out.add({
          'title': (m['name'] ?? '') as String,
          'artist': (m['artist_name'] ?? '') as String,
          'audioUrl': audio,
          'imageUrl': (m['image'] ?? '') as String,
        });
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Busca pistas en Free Music Archive (sin clave). Devuelve la misma forma.
  Future<List<Map<String, String>>> searchFma(String query) async {
    try {
      final uri = Uri.parse('$_fma/search/?q=${Uri.encodeQueryComponent(query)}');
      // FMA es HTML; se devuelve la URL para que el usuario la abra. Para
      // descarga real se recomienda pasar la URL de audio que aparezca ahí.
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      return [
        {'title': query, 'artist': 'FMA', 'audioUrl': uri.toString()},
      ];
    } catch (_) {
      return const [];
    }
  }
}