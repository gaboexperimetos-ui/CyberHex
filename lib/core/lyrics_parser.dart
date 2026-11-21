import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'tag_editor.dart';

// Parser de letras `.lrc` (y de las letras incrustadas en el archivo).
//
// Sin paquetes: el formato es texto y las reglas caben en una pantalla.
//
// * `[mm:ss.xx]texto` — una o **varias** marcas de tiempo por línea
//   (`[00:10.00][01:20.00]estribillo`), que es como se escriben los estribillos.
// * `[ar:...]`, `[ti:...]`, `[al:...]`, `[by:...]`, `[offset:±ms]` — metadatos.
// * **Bilingüe**: dos líneas con la **misma** marca de tiempo se fusionan en
//   texto + traducción, y `texto|traducción` en una sola línea hace lo mismo.
// * Letras **incrustadas**: `USLT` en ID3v2 (MP3) y `LYRICS` /
//   `UNSYNCEDLYRICS` en el Vorbis comment de FLAC.
//
// Las líneas sin marca (texto plano pegado) quedan con `time == -1`: se pueden
// mostrar y editar, pero no saltar a ellas.

/// Una línea de la letra.
class LyricLine {
  const LyricLine({required this.time, required this.text, this.translation = ''});

  /// Segundo al que empieza la línea, o `-1` si no tiene marca.
  final double time;

  final String text;

  /// Segunda línea (traducción o transliteración). Vacía si no hay.
  final String translation;

  bool get isTimed => time >= 0;

  bool get hasTranslation => translation.trim().isNotEmpty;

  LyricLine copyWith({double? time, String? text, String? translation}) {
    return LyricLine(
      time: time ?? this.time,
      text: text ?? this.text,
      translation: translation ?? this.translation,
    );
  }

  /// Marca formateada `mm:ss.xx` (o `--:--` si no tiene).
  String get stamp {
    if (!isTimed) return '--:--';
    final total = time.floor();
    final centis = ((time - total) * 100).round();
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}.'
        '${centis.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      other is LyricLine &&
      other.time == time &&
      other.text == text &&
      other.translation == translation;

  @override
  int get hashCode => Object.hash(time, text, translation);

  @override
  String toString() => 'LyricLine($stamp, "$text"'
      '${hasTranslation ? ' / "$translation"' : ''})';
}

/// Letra completa: líneas ordenadas y metadatos.
class Lyrics {
  const Lyrics({
    required this.lines,
    this.tags = const <String, String>{},
    this.origin = '',
  });

  final List<LyricLine> lines;

  /// Metadatos del `.lrc`, en minúsculas (`ar`, `ti`, `al`, `by`, `offset`…).
  final Map<String, String> tags;

  /// De dónde salió: `lrc`, `embedded` o `plain`.
  final String origin;

  static const Lyrics empty = Lyrics(lines: <LyricLine>[]);

  bool get isEmpty => lines.isEmpty;

  bool get isTimed => lines.any((line) => line.isTimed);

  String get title => tags['ti'] ?? '';

  String get artist => tags['ar'] ?? '';

  String get album => tags['al'] ?? '';

  String get author => tags['by'] ?? '';

  /// Desplazamiento de `[offset:]` en milisegundos (positivo = más tarde).
  int get offsetMs => int.tryParse((tags['offset'] ?? '').replaceAll('+', '')) ?? 0;

  /// Instante de presentación de una línea (aplica `offset`).
  double displayTime(LyricLine line) =>
      line.isTimed ? (line.time + offsetMs / 1000).clamp(0.0, double.infinity).toDouble() : -1;

  /// Índice de la línea que suena en [seconds], o -1 antes de la primera.
  ///
  /// Búsqueda binaria sobre las líneas con marca: la letra puede tener cientos
  /// de líneas y esto se llama en cada tick de posición.
  int indexAt(double seconds) {
    var low = 0;
    var high = lines.length - 1;
    var found = -1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final line = lines[mid];
      if (!line.isTimed) {
        low = mid + 1;
        continue;
      }
      if (displayTime(line) <= seconds) {
        found = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

  /// Copia con etiquetas nuevas (para el estudio).
  Lyrics withTags(Map<String, String> tags) =>
      Lyrics(lines: lines, tags: tags, origin: origin);

  @override
  String toString() => 'Lyrics(${lines.length} líneas, $origin)';
}

/// Parser y escritor de `.lrc`.
abstract final class LyricsParser {
  /// Marca de tiempo: `[mm:ss]`, `[mm:ss.xx]` o `[mm:ss.xxx]`.
  static final RegExp timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  /// Metadatos: `[ar:Artista]` en una línea propia.
  static final RegExp metaTag = RegExp(r'^\[([A-Za-z#]+):([^\]]*)\]\s*$');

  /// Interpreta un `.lrc`. Nunca lanza: lo que no entiende lo ignora.
  static Lyrics parse(String source, {String origin = 'lrc'}) {
    if (source.trim().isEmpty) return Lyrics.empty;
    final tags = <String, String>{};
    final entries = <LyricLine>[];

    for (final raw in const LineSplitter().convert(source)) {
      final line = raw.replaceAll('\r', '').trim();
      if (line.isEmpty) continue;

      final meta = metaTag.firstMatch(line);
      if (meta != null) {
        final key = meta.group(1)!.toLowerCase();
        final value = meta.group(2)!.trim();
        // `offset` es lo único que se interpreta; el resto se guarda tal cual.
        tags[key] = key == 'offset' ? value.replaceAll('+', '') : value;
        continue;
      }

      final matches = timeTag.allMatches(line).toList();
      if (matches.isEmpty) {
        _addPlain(entries, line);
        continue;
      }

      var text = line;
      for (final match in matches.reversed) {
        if (match.end > text.length) continue;
        text = text.replaceRange(match.start, match.end, '');
      }
      final parsed = _splitBilingual(text.trim());
      if (parsed.$1.isEmpty) continue;

      for (final match in matches) {
        final time = _secondsOf(match);
        if (time == null) continue;
        _addTimed(entries, time, parsed.$1, parsed.$2);
      }
    }

    entries.sort((a, b) => a.time.compareTo(b.time));
    return Lyrics(
      lines: List<LyricLine>.unmodifiable(entries),
      tags: Map<String, String>.unmodifiable(tags),
      origin: origin,
    );
  }

  /// Texto pegado sin marcas: una línea por renglón, todas sin tiempo.
  static Lyrics parsePlain(String source, {String origin = 'plain'}) {
    final lines = <LyricLine>[];
    for (final raw in const LineSplitter().convert(source)) {
      final line = raw.replaceAll('\r', '').trim();
      if (line.isEmpty) continue;
      final parsed = _splitBilingual(line);
      lines.add(LyricLine(time: -1, text: parsed.$1, translation: parsed.$2));
    }
    return Lyrics(
      lines: List<LyricLine>.unmodifiable(lines),
      origin: origin,
    );
  }

  /// Lee un archivo `.lrc` del disco.
  static Lyrics readFile(File file) {
    try {
      if (!file.existsSync()) return Lyrics.empty;
      return parse(file.readAsStringSync());
    } catch (_) {
      return Lyrics.empty;
    }
  }

  /// Letras incrustadas en los bytes de un audio (sin abrir nada más).
  static Lyrics readEmbedded(Uint8List bytes) {
    final uslt = id3Uslt(bytes);
    if (uslt != null && uslt.trim().isNotEmpty) return parse(uslt, origin: 'embedded');
    final vorbis = flacLyrics(bytes);
    if (vorbis != null && vorbis.trim().isNotEmpty) {
      return parse(vorbis, origin: 'embedded');
    }
    return Lyrics.empty;
  }

  /// Letra `USLT` de una etiqueta ID3v2 (MP3).
  static String? id3Uslt(Uint8List bytes) {
    for ( final frame in Id3v2.frames(bytes)) {
      if (frame.id != 'USLT' || frame.data.length < 5) continue;
      final data = frame.data;
      final encoding = data[0];
      final wide = encoding == 1 || encoding == 2;
      var pos = 4; // codificación + idioma
      // Descriptor de contenido terminado en cero (uno o dos bytes).
      while (pos + 1 < data.length) {
        if (wide) {
          if (data[pos] == 0 && data[pos + 1] == 0) {
            pos += 2;
            break;
          }
          pos += 2;
        } else {
          if (data[pos] == 0) {
            pos += 1;
            break;
          }
          pos += 1;
        }
      }
      if (pos >= data.length) return null;
      return Id3v2.decodeText(Uint8List.sublistView(data, pos), encoding);
    }
    return null;
  }

  /// `LYRICS` (o `UNSYNCEDLYRICS`) del Vorbis comment de un FLAC.
  static String? flacLyrics(Uint8List bytes) {
    if (!Flac.hasHeader(bytes)) return null;
    final comments = Flac.comments(bytes);
    for (final key in const <String>['LYRICS', 'UNSYNCEDLYRICS', 'LYRIC']) {
      final value = comments[key];
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  /// Ruta del `.lrc` compañero de un audio (`/a/b/tema.flac` → `/a/b/tema.lrc`).
  static String lrcPathFor(String audioPath) {
    final dot = audioPath.lastIndexOf('.');
    final slash = audioPath.lastIndexOf(Platform.pathSeparator);
    if (dot <= slash) return '$audioPath.lrc';
    return '${audioPath.substring(0, dot)}.lrc';
  }

  /// Carga la letra de una pista: primero el `.lrc` de al lado, después la
  /// incrustada en el archivo.
  static Future<Lyrics> loadForAudio(String audioPath) async {
    if (audioPath.isEmpty) return Lyrics.empty;
    final sidecar = File(lrcPathFor(audioPath));
    final fromFile = readFile(sidecar);
    if (!fromFile.isEmpty) return fromFile;
    // Mayúsculas: algunos editores guardan `TEMA.LRC`.
    final upper = File(lrcPathFor(audioPath).replaceAll('.lrc', '.LRC'));
    final fromUpper = readFile(upper);
    if (!fromUpper.isEmpty) return fromUpper;
    try {
      final audio = File(audioPath);
      if (!audio.existsSync()) return Lyrics.empty;
      // Solo hacen falta la etiqueta y el primer bloque: 4 MiB bastan para un
      // MP3 con USLT y para toda la cabecera de un FLAC.
      final handle = audio.openSync();
      try {
        final size = handle.lengthSync();
        handle.setPositionSync(0);
        final head = handle.readSync(size < 4 * 1024 * 1024 ? size : 4 * 1024 * 1024);
        return readEmbedded(head);
      } finally {
        handle.closeSync();
      }
    } catch (_) {
      return Lyrics.empty;
    }
  }

  // --- internos ------------------------------------------------------------

  /// Segundos de una marca; `null` si la marca no es válida.
  static double? _secondsOf(RegExpMatch match) {
    final minutes = int.tryParse(match.group(1) ?? '');
    final seconds = int.tryParse(match.group(2) ?? '');
    if (minutes == null || seconds == null) return null;
    if (seconds >= 60) return null;
    final fraction = match.group(3);
    var millis = 0;
    if (fraction != null) {
      final value = int.tryParse(fraction) ?? 0;
      millis = switch (fraction.length) {
        1 => value * 100,
        2 => value * 10,
        _ => value,
      };
    }
    return minutes * 60 + seconds + millis / 1000;
  }

  /// `texto|traducción` → (texto, traducción).
  static (String, String) _splitBilingual(String text) {
    final bar = text.indexOf('|');
    if (bar < 0) return (text, '');
    return (
      text.substring(0, bar).trim(),
      text.substring(bar + 1).trim(),
    );
  }

  static void _addTimed(
    List<LyricLine> entries,
    double time,
    String text,
    String translation,
  ) {
    final key = (time * 100).round();
    for (var i = 0; i < entries.length; i++) {
      final line = entries[i];
      if ((line.time * 100).round() != key) continue;
      if (line.text == text) {
        // La misma línea repetida: solo aporta si trae traducción.
        if (line.translation.isEmpty && translation.isNotEmpty) {
          entries[i] = line.copyWith(translation: translation);
        }
        return;
      }
      if (line.translation.isEmpty) {
        // Dos textos con la misma marca: bilingüe.
        entries[i] = line.copyWith(translation: text);
        return;
      }
    }
    entries.add(LyricLine(time: time, text: text, translation: translation));
  }

  static void _addPlain(List<LyricLine> entries, String text) {
    final parsed = _splitBilingual(text);
    if (entries.isEmpty) {
      entries.add(LyricLine(time: -1, text: parsed.$1, translation: parsed.$2));
      return;
    }
    final last = entries.last;
    if (last.isTimed && last.translation.isEmpty) {
      // La línea siguiente sin marca de una línea con marca es su traducción.
      entries[entries.length - 1] = last.copyWith(translation: parsed.$1);
      return;
    }
    entries.add(LyricLine(time: -1, text: parsed.$1, translation: parsed.$2));
  }
}

/// Escritura de `.lrc`: lo que produce el estudio de letras.
abstract final class LrcWriter {
  /// Texto `.lrc` completo, con metadatos delante y cabecera de CyberHex.
  static String build(
    Lyrics lyrics, {
    Map<String, String> tags = const <String, String>{},
    String? offset,
  }) {
    final merged = <String, String>{...lyrics.tags, ...tags};
    final out = StringBuffer();
    void meta(String key, String value) {
      if (value.trim().isEmpty) return;
      out.writeln('[$key:${value.trim()}]');
    }

    meta('ti', merged['ti'] ?? '');
    meta('ar', merged['ar'] ?? '');
    meta('al', merged['al'] ?? '');
    meta('by', merged['by'] ?? 'CyberHex');
    meta('offset', offset ?? merged['offset'] ?? '');
    if (out.isEmpty) out.writeln('[by:CyberHex]');

    for (final line in lyrics.lines) {
      if (!line.isTimed) continue;
      final stamp = '[${_stamp(line.time)}]';
      out.writeln('$stamp${line.text}');
      if (line.hasTranslation) {
        // Bilingüe: la traducción es otra línea con la misma marca.
        out.writeln('$stamp${line.translation}');
      }
    }
    return out.toString();
  }

  /// Guarda la letra junto al audio (`tema.flac` → `tema.lrc`).
  ///
  /// Devuelve el archivo escrito, o `null` si no se pudo (el motivo queda en
  /// [lastError]).
  static String? lastError;

  static File? saveNextTo(String audioPath, Lyrics lyrics, {bool overwrite = true}) {
    lastError = null;
    if (audioPath.isEmpty) {
      lastError = 'No hay una pista cargada.';
      return null;
    }
    final timed = lyrics.lines.where((line) => line.isTimed).length;
    if (timed == 0) {
      lastError = 'No hay ni una línea con tiempo: marca al menos un verso.';
      return null;
    }
    try {
      final target = File(LyricsParser.lrcPathFor(audioPath));
      if (target.existsSync() && !overwrite) {
        lastError = 'Ya existe ${target.path}.';
        return null;
      }
      target.writeAsStringSync(build(lyrics), flush: true);
      return target;
    } catch (error) {
      lastError = 'No se pudo escribir la letra: $error';
      return null;
    }
  }

  /// `mm:ss.xx` con centésimas (lo que entienden todos los reproductores).
  static String _stamp(double seconds) {
    final safe = seconds.isFinite && seconds > 0 ? seconds : 0.0;
    final total = safe.floor();
    final centis = ((safe - total) * 100).round().clamp(0, 99);
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}.'
        '${centis.toString().padLeft(2, '0')}';
  }
}

/// Atajo de lectura para la UI: letra o vacío, sin lanzar nunca.
Future<Lyrics> loadLyricsFor(String audioPath) => LyricsParser.loadForAudio(audioPath);
