import 'dart:convert';

import 'package:http/http.dart' as http;

/// Letra sincronizada de una pista (LRC).
class LrcLine {
  const LrcLine(this.seconds, this.text);

  final double seconds;
  final String text;
}

class LyricsResult {
  const LyricsResult({required this.plain, required this.lrc});

  /// Letra completa en texto plano.
  final String plain;

  /// Líneas sincronizadas (vacío si la fuente no trajo tiempos).
  final List<LrcLine> lrc;

  bool get hasLrc => lrc.isNotEmpty;
}

/// Busca la letra de una pista. Primero en Lrclib (letras reales sincronizadas)
/// y, si no hay, con un respaldo de IA opcional (por ejemplo un modelo local
/// que devuelva texto). Nunca inventa una letra "real": la IA solo se usa como
/// respaldo cuando la API no encuentra nada y el usuario lo tiene activado.
class LyricsService {
  LyricsService({this.aiEndpoint, this.aiApiKey});

  /// Endpoint OpenAI-compatible de respaldo. Por defecto, el router local de
  /// llama.cpp (`http://127.0.0.1:8004/v1/chat/completions`), sin depender de
  /// APIs externas de pago.
  static const String localEndpoint =
      'http://127.0.0.1:8004/v1/chat/completions';

  /// Modelo local que se pide al router.
  static const String localModel = 'deepseek-v4pro';

  /// Endpoint opcional de IA de respaldo (OpenAI-compatible). Si es null, no se
  /// usa IA y solo se consulta Lrclib.
  final String? aiEndpoint;

  /// Clave opcional para el endpoint de IA.
  final String? aiApiKey;

  static const _lrclib = 'https://lrclib.net/api';

  /// Devuelve la letra de `artist - title`. `album` y `durationSeconds` ayudan
  /// a la búsqueda. `useAiFallback` activa el respaldo de IA.
  Future<LyricsResult?> fetch({
    required String title,
    required String artist,
    String album = '',
    double durationSeconds = 0,
    bool useAiFallback = false,
  }) async {
    if (title.trim().isEmpty) return null;

    final byLr = await _fromLrclib(
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
    );
    if (byLr != null && byLr.plain.trim().isNotEmpty) return byLr;

    if (useAiFallback && aiEndpoint != null && aiEndpoint!.isNotEmpty) {
      final byAi = await _fromAi(title: title, artist: artist);
      if (byAi != null && byAi.plain.trim().isNotEmpty) return byAi;
    }
    return byLr;
  }

  Future<LyricsResult?> _fromLrclib({
    required String title,
    required String artist,
    required String album,
    required double durationSeconds,
  }) async {
    try {
      // 1) Búsqueda por pista + artista + duración (más precisa).
      final q = <String, String>{
        'track_name': title,
        'artist_name': artist,
      };
      if (album.isNotEmpty) q['album_name'] = album;
      if (durationSeconds > 0) q['duration'] = durationSeconds.toStringAsFixed(0);

      final searchUri = Uri.parse('$_lrclib/search').replace(queryParameters: q);
      final res = await http.get(searchUri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final list = jsonDecode(res.body) as List;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final plain = (map['plainLyrics'] ?? '') as String;
          final synced = (map['syncedLyrics'] ?? '') as String;
          if (plain.trim().isNotEmpty || synced.trim().isNotEmpty) {
            return LyricsResult(
              plain: plain.trim().isNotEmpty ? plain : synced,
              lrc: parseLrc(synced),
            );
          }
        }
      }

      // 2) Fallback: get directo (si conocemos artista+título exactos).
      final getUri = Uri.parse('$_lrclib/get').replace(queryParameters: {
        'artist_name': artist,
        'track_name': title,
      });
      final res2 = await http.get(getUri).timeout(const Duration(seconds: 8));
      if (res2.statusCode == 200) {
        final map = jsonDecode(res2.body) as Map<String, dynamic>;
        final plain = (map['plainLyrics'] ?? '') as String;
        final synced = (map['syncedLyrics'] ?? '') as String;
        if (plain.trim().isNotEmpty || synced.trim().isNotEmpty) {
          return LyricsResult(
            plain: plain.trim().isNotEmpty ? plain : synced,
            lrc: parseLrc(synced),
          );
        }
      }
    } catch (_) {
      // Sin red o error: se ignora y se prueba el respaldo.
    }
    return null;
  }

  Future<LyricsResult?> _fromAi({
    required String title,
    required String artist,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse(aiEndpoint!),
            headers: {
              'Content-Type': 'application/json',
              if (aiApiKey != null && aiApiKey!.isNotEmpty)
                'Authorization': 'Bearer $aiApiKey',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Devuelve SOLO la letra de la cancion indicada, sin '
                      'comentarios ni formato. Si no la conoces, responde "CANCEL".',
                },
                {
                  'role': 'user',
                  'content': 'Letra de "$title" de "$artist".',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        final choices = map['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content =
              (choices.first['message']['content'] ?? '') as String;
          if (content.trim().isNotEmpty && content.trim() != 'CANCEL') {
            return LyricsResult(plain: content.trim(), lrc: const []);
          }
        }
      }
    } catch (_) {
      // IA no disponible.
    }
    return null;
  }

  /// Parsea un texto LRC (`[mm:ss.xx] texto`) a líneas de tiempo.
  static List<LrcLine> parseLrc(String text) {
    if (text.trim().isEmpty) return const [];
    final out = <LrcLine>[];
    final re = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final matches = re.allMatches(line).toList();
      if (matches.isEmpty) continue;
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final fracStr = m.group(3);
        final frac = fracStr == null
            ? 0.0
            : double.parse('0.${fracStr.padRight(3, '0')}');
        final seconds = min * 60.0 + sec + frac;
        final textAfter = line.substring(m.end).trim();
        out.add(LrcLine(seconds, textAfter));
      }
    }
    out.sort((a, b) => a.seconds.compareTo(b.seconds));
    return out;
  }
}