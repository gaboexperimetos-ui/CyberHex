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

  /// Descarga `url` a `destPath`. Si `destPath` no tiene extension o no encaja
  /// con el tipo real (p. ej. MP4/M4A), se corrige. `referer` es opcional.
  /// Devuelve el resultado o null si falla.
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

      final contentType = response.headers['content-type'] ?? 'audio/mpeg';
      final ext = _extensionForContentType(contentType, url);
      final finalPath = _ensureExtension(destPath, ext);

      final file = File(finalPath);
      await file.create(recursive: true);
      final sink = file.openWrite();
      var total = 0;
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        total += chunk.length;
      });
      await sink.close();
      return DownloadResult(
        path: finalPath,
        bytes: total,
        contentType: contentType,
      );
    } catch (_) {
      return null;
    }
  }

  /// Elige extension segun el Content-Type (o la URL si no hay cabecera).
  static String _extensionForContentType(String contentType, String url) {
    final ct = contentType.toLowerCase();
    if (ct.contains('mp4') || ct.contains('m4a') || ct.contains('aac')) {
      // MP4 de solo audio -> m4a; con video -> mp4.
      if (ct.contains('audio') || url.toLowerCase().endsWith('.m4a')) {
        return '.m4a';
      }
      return '.mp4';
    }
    if (ct.contains('mpeg') || ct.contains('mp3')) return '.mp3';
    if (ct.contains('flac')) return '.flac';
    if (ct.contains('ogg')) return '.ogg';
    if (ct.contains('wav')) return '.wav';
    if (ct.contains('webm')) return '.webm';
    // Fallback: extension de la URL.
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot >= 0 && dot > path.length - 6) return path.substring(dot);
    return '.mp3';
  }

  /// Asegura que `path` termina en `ext` (reemplaza la extension si ya tenia).
  static String _ensureExtension(String path, String ext) {
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    if (dot > slash && dot > 0) {
      return path.substring(0, dot) + ext;
    }
    return path + ext;
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