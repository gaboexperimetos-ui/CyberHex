import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Lectura y escritura de etiquetas sin dependencias externas.
//
// El núcleo solo expone *lo que suena*, no lo que hay escrito en el archivo:
// para leer la carátula, el título incrustado o las letras `USLT` hay que abrir
// el contenedor a mano. Aquí están las dos familias que usa la app:
//
// * **ID3v2** (`.mp3`): marcos `TIT2`, `TPE1`, `TALB`, `TYER`/`TDRC`, `TCON`,
//   `TRCK`, `APIC` y `USLT`. Se lee v2.3 y v2.4 (tamaño de marco *syncsafe*).
// * **Vorbis comment** dentro de FLAC (`.flac`): bloques `VORBIS_COMMENT` y
//   `PICTURE`.
//
// Al escribir **no** se reescribe el audio: se sustituye la etiqueta entera y
// se copia el resto tal cual (`.tmp` + `rename`, como la sesión). Eso implica
// tener el archivo en memoria: es aceptable para pistas de decenas de MB y
// está dicho en la UI.

// ---------------------------------------------------------------------------
// Primitivas compartidas
// ---------------------------------------------------------------------------

/// Marco de una etiqueta ID3v2.
class Id3v2Frame {
  const Id3v2Frame(this.id, this.data);

  /// Identificador de cuatro letras (`TIT2`, `APIC`, `USLT`…).
  final String id;

  /// Cuerpo del marco, sin cabecera.
  final Uint8List data;

  @override
  String toString() => 'Id3v2Frame($id, ${data.length} B)';
}

/// Acceso de bajo nivel a una etiqueta ID3v2.
abstract final class Id3v2 {
  /// ¿Los bytes empiezan con una cabecera `ID3`?
  static bool hasTag(Uint8List bytes) =>
      bytes.length >= 10 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33;

  /// Tamaño total de la etiqueta (cabecera incluida), o `null` si no hay.
  static int? totalSize(Uint8List bytes) {
    if (!hasTag(bytes)) return null;
    final body = syncsafe(bytes, 6);
    final footer = (bytes[5] & 0x10) != 0 ? 10 : 0;
    return 10 + body + footer;
  }

  /// Entero *syncsafe* de 4 bytes (7 bits por byte), como en la cabecera ID3v2.
  static int syncsafe(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return (bytes[offset] & 0x7F) << 21 |
        (bytes[offset + 1] & 0x7F) << 14 |
        (bytes[offset + 2] & 0x7F) << 7 |
        (bytes[offset + 3] & 0x7F);
  }

  /// Entero big-endian de 4 bytes (tamaño de marco en ID3v2.3).
  static int be32(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return bytes[offset] << 24 |
        bytes[offset + 1] << 16 |
        bytes[offset + 2] << 8 |
        bytes[offset + 3];
  }

  /// Versión mayor de la etiqueta (3 o 4 normalmente).
  static int version(Uint8List bytes) => hasTag(bytes) ? bytes[3] : 0;

  /// Marcos de la etiqueta, en orden. Un marco truncado corta la lectura en
  /// lugar de lanzar: un archivo mal etiquetado no debe romper la app.
  static List<Id3v2Frame> frames(Uint8List bytes) {
    if (!hasTag(bytes)) return const <Id3v2Frame>[];
    final major = bytes[3];
    final flags = bytes[5];
    var pos = 10;
    if ((flags & 0x40) != 0 && pos + 4 <= bytes.length) {
      // Cabecera extendida: su tamaño ya es syncsafe en v2.4 y plano en v2.3.
      final size = major >= 4 ? syncsafe(bytes, pos) : be32(bytes, pos);
      pos += 4 + (size > 0 ? size : 0);
    }
    final end = _min(
      10 + syncsafe(bytes, 6),
      bytes.length,
    );
    final out = <Id3v2Frame>[];
    while (pos + 10 <= end) {
      final id = ascii.decode(bytes.sublist(pos, pos + 4), allowInvalid: true);
      if (id.trim().isEmpty || bytes[pos] == 0) break; // relleno
      final size = major >= 4 ? syncsafe(bytes, pos + 4) : be32(bytes, pos + 4);
      final start = pos + 10;
      final stop = start + size;
      if (size <= 0 || stop > end) break;
      out.add(Id3v2Frame(id, Uint8List.sublistView(bytes, start, stop)));
      pos = stop;
    }
    return out;
  }

  /// Decodifica un texto ID3v2 según su byte de codificación.
  static String decodeText(Uint8List data, int encoding) {
    if (data.isEmpty) return '';
    switch (encoding) {
      case 0:
        return _trimNul(latin1.decode(data, allowInvalid: true));
      case 3:
        return _trimNul(utf8.decode(data, allowMalformed: true));
      case 1:
      case 2:
        return _decodeUtf16(data, bigEndian: encoding == 2);
      default:
        return _trimNul(latin1.decode(data, allowInvalid: true));
    }
  }

  static String _decodeUtf16(Uint8List data, {required bool bigEndian}) {
    var start = 0;
    var be = bigEndian;
    if (data.length >= 2) {
      if (data[0] == 0xFF && data[1] == 0xFE) {
        be = false;
        start = 2;
      } else if (data[0] == 0xFE && data[1] == 0xFF) {
        be = true;
        start = 2;
      }
    }
    final units = <int>[];
    for (var i = start; i + 1 < data.length; i += 2) {
      final unit = be ? data[i] << 8 | data[i + 1] : data[i] | data[i + 1] << 8;
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }

  static String _trimNul(String value) {
    final index = value.indexOf('\u0000');
    return index < 0 ? value : value.substring(0, index);
  }

  /// Texto de un marco de texto (`TIT2`…), o `null` si no existe.
  static String? text(Uint8List bytes, String id) {
    for (final frame in frames(bytes)) {
      if (frame.id != id || frame.data.isEmpty) continue;
      return decodeText(frame.data.sublist(1), frame.data[0]);
    }
    return null;
  }
}

/// Bloque de metadatos FLAC.
class FlacBlock {
  const FlacBlock(this.type, this.data);

  /// Tipo de bloque (0 STREAMINFO, 4 VORBIS_COMMENT, 6 PICTURE…).
  final int type;
  final Uint8List data;

  @override
  String toString() => 'FlacBlock($type, ${data.length} B)';
}

/// Acceso de bajo nivel a un FLAC (`fLaC` + bloques de metadatos).
abstract final class Flac {
  static bool hasHeader(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x66 &&
      bytes[1] == 0x4C &&
      bytes[2] == 0x61 &&
      bytes[3] == 0x43;

  /// Bloques de metadatos y desplazamiento donde empiezan los frames de audio.
  static (List<FlacBlock>, int) parse(Uint8List bytes) {
    if (!hasHeader(bytes)) return (const <FlacBlock>[], 0);
    final blocks = <FlacBlock>[];
    var pos = 4;
    while (pos + 4 <= bytes.length) {
      final header = bytes[pos];
      final type = header & 0x7F;
      final last = (header & 0x80) != 0;
      final length = bytes[pos + 1] << 16 | bytes[pos + 2] << 8 | bytes[pos + 3];
      final start = pos + 4;
      final stop = start + length;
      if (stop > bytes.length) break;
      blocks.add(FlacBlock(type, Uint8List.sublistView(bytes, start, stop)));
      pos = stop;
      if (last) break;
    }
    return (blocks, pos);
  }

  /// Comentarios `CLAVE=valor` del primer bloque VORBIS_COMMENT.
  static Map<String, String> comments(Uint8List bytes) {
    final (blocks, _) = parse(bytes);
    for (final block in blocks) {
      if (block.type == 4) return parseComments(block.data);
    }
    return const <String, String>{};
  }

  /// Vorbis comment en crudo (`vendor` + lista `CLAVE=valor`).
  static Map<String, String> parseComments(Uint8List data) {
    final out = <String, String>{};
    if (data.length < 8) return out;
    var pos = 0;
    final vendorLength = _le32(data, pos);
    pos += 4;
    if (vendorLength < 0 || pos + vendorLength > data.length) return out;
    pos += vendorLength;
    if (pos + 4 > data.length) return out;
    final count = _le32(data, pos);
    pos += 4;
    for (var i = 0; i < count && pos + 4 <= data.length; i++) {
      final length = _le32(data, pos);
      pos += 4;
      if (length < 0 || pos + length > data.length) break;
      final entry = utf8.decode(
        data.sublist(pos, pos + length),
        allowMalformed: true,
      );
      pos += length;
      final eq = entry.indexOf('=');
      if (eq <= 0) continue;
      out[entry.substring(0, eq).toUpperCase()] = entry.substring(eq + 1);
    }
    return out;
  }

  /// Imagen del primer bloque PICTURE (tipo 3 = portada frontal).
  static Uint8List? picture(Uint8List bytes) {
    final (blocks, _) = parse(bytes);
    for (final block in blocks) {
      if (block.type != 6) continue;
      final data = block.data;
      var pos = 0;
      if (data.length < 8) continue;
      pos += 4; // tipo de imagen
      final mimeLength = _be32At(data, pos);
      pos += 4;
      if (mimeLength < 0 || pos + mimeLength > data.length) continue;
      pos += mimeLength;
      if (pos + 4 > data.length) continue;
      final descLength = _be32At(data, pos);
      pos += 4;
      if (descLength < 0 || pos + descLength > data.length) continue;
      pos += descLength;
      pos += 16; // ancho, alto, profundidad y colores
      if (pos + 4 > data.length) continue;
      final dataLength = _be32At(data, pos);
      pos += 4;
      if (dataLength <= 0 || pos + dataLength > data.length) continue;
      return Uint8List.fromList(data.sublist(pos, pos + dataLength));
    }
    return null;
  }

  static int _le32(Uint8List data, int offset) {
    if (offset + 4 > data.length) return 0;
    return data[offset] |
        data[offset + 1] << 8 |
        data[offset + 2] << 16 |
        data[offset + 3] << 24;
  }

  static int _be32At(Uint8List data, int offset) {
    if (offset + 4 > data.length) return 0;
    return data[offset] << 24 |
        data[offset + 1] << 16 |
        data[offset + 2] << 8 |
        data[offset + 3];
  }
}

// ---------------------------------------------------------------------------
// Modelo de etiquetas
// ---------------------------------------------------------------------------

/// Etiquetas editables de una pista.
///
/// Todos los campos son texto libre menos [track], que es un número (0 cuando
/// no hay). [cover] son los bytes tal cual del JPEG/PNG incrustado: no se
/// re-codifica nada.
class TrackTags {
  const TrackTags({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.year = '',
    this.genre = '',
    this.track = 0,
    this.cover,
  });

  final String title;
  final String artist;
  final String album;
  final String year;
  final String genre;
  final int track;
  final Uint8List? cover;

  static const TrackTags empty = TrackTags();

  bool get isEmpty =>
      title.isEmpty &&
      artist.isEmpty &&
      album.isEmpty &&
      year.isEmpty &&
      genre.isEmpty &&
      track == 0 &&
      cover == null;

  bool get hasCover => cover != null && cover!.isNotEmpty;

  TrackTags copyWith({
    String? title,
    String? artist,
    String? album,
    String? year,
    String? genre,
    int? track,
    Uint8List? cover,
    bool dropCover = false,
  }) {
    return TrackTags(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      track: track ?? this.track,
      cover: dropCover ? null : (cover ?? this.cover),
    );
  }

  /// Etiqueta legible de una línea, para el resumen de la hoja.
  String get summary {
    final parts = <String>[
      if (title.isNotEmpty) title,
      if (artist.isNotEmpty) artist,
      if (album.isNotEmpty) album,
      if (year.isNotEmpty) year,
    ];
    return parts.isEmpty ? 'sin etiquetas' : parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is TrackTags &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.year == year &&
      other.genre == genre &&
      other.track == track &&
      _sameBytes(other.cover, cover);

  @override
  int get hashCode => Object.hash(
        title,
        artist,
        album,
        year,
        genre,
        track,
        cover == null ? 0 : cover!.length,
      );

  @override
  String toString() => 'TrackTags($summary${hasCover ? ', con carátula' : ''})';
}

bool _sameBytes(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Resultado de escribir etiquetas en varios archivos.
class TagWriteReport {
  const TagWriteReport({required this.written, required this.failed, this.error});

  final int written;
  final List<String> failed;
  final String? error;

  bool get ok => failed.isEmpty && error == null;

  @override
  String toString() => ok
      ? '$written archivo(s) actualizados'
      : '$written actualizados, ${failed.length} fallidos'
          '${error == null ? '' : ': $error'}';
}

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------

/// Lector/escritor de etiquetas para MP3 (ID3v2) y FLAC (Vorbis comment).
abstract final class TagEditor {
  /// Extensiones que este editor sabe tocar.
  static const List<String> writableExtensions = <String>['mp3', 'flac'];

  static bool canWrite(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp3') || lower.endsWith('.flac');
  }

  /// Lee las etiquetas sin lanzar: si el archivo no se puede abrir devuelve
  /// [TrackTags.empty] y deja el detalle en [lastError].
  static String? lastError;

  static TrackTags read(File file) {
    try {
      final bytes = file.readAsBytesSync();
      return readBytes(bytes);
    } catch (error) {
      lastError = 'No se pudo leer ${file.path}: $error';
      return TrackTags.empty;
    }
  }

  static TrackTags readBytes(Uint8List bytes) {
    if (Id3v2.hasTag(bytes)) return _readId3(bytes);
    if (Flac.hasHeader(bytes)) return _readFlac(bytes);
    return TrackTags.empty;
  }

  static TrackTags _readId3(Uint8List bytes) {
    String text(String id) => Id3v2.text(bytes, id)?.trim() ?? '';
    final year = text('TYER').isNotEmpty ? text('TYER') : text('TDRC');
    final trackText = text('TRCK');
    final slash = trackText.indexOf('/');
    final trackNumber = int.tryParse(
          slash > 0 ? trackText.substring(0, slash) : trackText,
        ) ??
        0;
    return TrackTags(
      title: text('TIT2'),
      artist: text('TPE1'),
      album: text('TALB'),
      year: year.length > 4 ? year.substring(0, 4) : year,
      genre: _genre(text('TCON')),
      track: trackNumber,
      cover: _coverId3(bytes),
    );
  }

  static Uint8List? _coverId3(Uint8List bytes) {
    for (final frame in Id3v2.frames(bytes)) {
      if (frame.id != 'APIC' || frame.data.length < 4) continue;
      final data = frame.data;
      var pos = 1 + _indexOf(data, 0, 1) + 1; // codificación + mime
      if (pos <= 1 || pos >= data.length) continue;
      pos += 1; // tipo de imagen
      final descEnd = _terminatorEnd(data, pos, data[0]);
      if (descEnd < 0) continue;
      final image = Uint8List.sublistView(data, descEnd);
      if (image.isNotEmpty) return Uint8List.fromList(image);
    }
    return null;
  }

  static TrackTags _readFlac(Uint8List bytes) {
    final comments = Flac.comments(bytes);
    String value(String key) => (comments[key] ?? '').trim();
    final trackText = value('TRACKNUMBER');
    final slash = trackText.indexOf('/');
    return TrackTags(
      title: value('TITLE'),
      artist: value('ARTIST'),
      album: value('ALBUM'),
      year: _yearOf(value('DATE').isNotEmpty ? value('DATE') : value('YEAR')),
      genre: value('GENRE'),
      track: int.tryParse(slash > 0 ? trackText.substring(0, slash) : trackText) ?? 0,
      cover: Flac.picture(bytes),
    );
  }

  static String _yearOf(String value) =>
      value.length > 4 ? value.substring(0, 4) : value;

  static String _genre(String raw) {
    // ID3v1 numérico entre paréntesis: "(17)" -> "Rock" no hace falta, se deja
    // el número fuera y se devuelve vacío si no hay texto.
    if (raw.startsWith('(') && raw.endsWith(')')) return raw.substring(1, raw.length - 1);
    return raw;
  }

  /// Escribe las etiquetas. En MP3 sustituye la etiqueta ID3v2 y copia el audio;
  /// en FLAC reconstruye la cadena de bloques. Deja `.tmp` solo si falla.
  static Future<TagWriteReport> write(File file, TrackTags tags) async {
    lastError = null;
    try {
      final bytes = await file.readAsBytes();
      final Uint8List result;
      final lower = file.path.toLowerCase();
      if (lower.endsWith('.flac')) {
        result = rewriteFlac(bytes, tags);
      } else if (lower.endsWith('.mp3')) {
        result = rewriteId3(bytes, tags);
      } else {
        lastError = 'Este formato no admite edición de etiquetas: ${file.path}';
        return TagWriteReport(written: 0, failed: <String>[file.path], error: lastError);
      }
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(result, flush: true);
      await temp.rename(file.path);
      return const TagWriteReport(written: 1, failed: <String>[]);
    } catch (error) {
      lastError = 'No se pudo escribir en ${file.path}: $error';
      return TagWriteReport(written: 0, failed: <String>[file.path], error: lastError);
    }
  }

  /// Escribe la misma etiqueta en varios archivos (edición por álbum). El
  /// título y el número de pista se conservan si [tags] no los trae.
  static Future<TagWriteReport> writeMany(
    List<File> files,
    TrackTags tags, {
    bool keepTitleAndTrack = true,
  }) async {
    var written = 0;
    final failed = <String>[];
    for (final file in files) {
      var target = tags;
      if (keepTitleAndTrack) {
        final current = read(file);
        target = tags.copyWith(
          title: tags.title.isEmpty ? current.title : tags.title,
          track: tags.track == 0 ? current.track : tags.track,
        );
      }
      final report = await write(file, target);
      written += report.written;
      failed.addAll(report.failed);
    }
    return TagWriteReport(written: written, failed: failed, error: lastError);
  }

  /// Etiqueta ID3v2.3 completa (cabecera + marcos + 1 KiB de relleno).
  static Uint8List buildId3v2(TrackTags tags) {
    final frames = BytesBuilder();
    void textFrame(String id, String value) {
      final clean = value.trim();
      if (clean.isEmpty) return;
      frames.add(_frame(id, _textPayload(clean)));
    }

    textFrame('TIT2', tags.title);
    textFrame('TPE1', tags.artist);
    textFrame('TALB', tags.album);
    textFrame('TYER', _yearOf(tags.year.trim()));
    textFrame('TCON', tags.genre);
    if (tags.track > 0) textFrame('TRCK', '${tags.track}');
    final cover = tags.cover;
    if (cover != null && cover.isNotEmpty) {
      frames.add(_frame('APIC', _apicPayload(cover)));
    }

    final body = frames.takeBytes();
    const padding = 1024;
    final out = BytesBuilder()
      ..add(<int>[0x49, 0x44, 0x33, 3, 0, 0])
      ..add(_syncsafeBytes(body.length + padding))
      ..add(body)
      ..add(Uint8List(padding));
    return out.takeBytes();
  }

  /// Audio original con la etiqueta nueva delante (sustituye la anterior).
  static Uint8List rewriteId3(Uint8List bytes, TrackTags tags) {
    final existing = Id3v2.totalSize(bytes) ?? 0;
    final audio = existing > 0 && existing <= bytes.length
        ? Uint8List.sublistView(bytes, existing)
        : bytes;
    final tag = buildId3v2(tags);
    final out = BytesBuilder()
      ..add(tag)
      ..add(audio);
    return out.takeBytes();
  }

  /// FLAC con la cadena de metadatos reconstruida (STREAMINFO primero).
  static Uint8List rewriteFlac(Uint8List bytes, TrackTags tags) {
    if (!Flac.hasHeader(bytes)) return bytes;
    final (blocks, audioStart) = Flac.parse(bytes);
    if (blocks.isEmpty) return bytes;
    final streamInfo = blocks.firstWhere(
      (block) => block.type == 0,
      orElse: () => blocks.first,
    );
    final out = BytesBuilder()..add(const <int>[0x66, 0x4C, 0x61, 0x43]);

    void block(int type, Uint8List data, {required bool last}) {
      final length = data.length;
      out.add(<int>[
        (last ? 0x80 : 0) | type,
        (length >> 16) & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF,
      ]);
      out.add(data);
    }

    final comments = _vorbisComment(tags);
    final cover = tags.cover;
    final picture = cover != null && cover.isNotEmpty ? _pictureBlock(cover) : null;

    block(0, streamInfo.data, last: false);
    block(4, comments, last: picture == null);
    if (picture != null) block(6, picture, last: true);

    if (audioStart > 0 && audioStart <= bytes.length) {
      out.add(Uint8List.sublistView(bytes, audioStart));
    }
    return out.takeBytes();
  }

  /// Archivos de audio del mismo directorio con el mismo álbum (edición por
  /// álbum completo). Si ningún hermano comparte el álbum, devuelve solo el
  /// propio archivo.
  static List<File> albumSiblings(File file) {
    final album = read(file).album.trim().toLowerCase();
    final directory = file.parent;
    if (!directory.existsSync()) return <File>[file];
    final out = <File>[];
    for (final entry in directory.listSync(followLinks: false)) {
      if (entry is! File) continue;
      if (!canWrite(entry.path)) continue;
      if (album.isEmpty || read(entry).album.trim().toLowerCase() == album) {
        out.add(entry);
      }
    }
    if (out.isEmpty) out.add(file);
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  // --- piezas internas -----------------------------------------------------

  static Uint8List _frame(String id, Uint8List payload) {
    final out = BytesBuilder()
      ..add(ascii.encode(id))
      ..add(<int>[
        (payload.length >> 24) & 0xFF,
        (payload.length >> 16) & 0xFF,
        (payload.length >> 8) & 0xFF,
        payload.length & 0xFF,
        0,
        0,
      ])
      ..add(payload);
    return out.takeBytes();
  }

  static Uint8List _textPayload(String value) {
    final out = BytesBuilder()..add(<int>[0x01, 0xFF, 0xFE]);
    for (final unit in value.codeUnits) {
      out.add(<int>[unit & 0xFF, (unit >> 8) & 0xFF]);
    }
    return out.takeBytes();
  }

  static Uint8List _apicPayload(Uint8List image) {
    final mime = _mimeOf(image);
    final out = BytesBuilder()
      ..add(<int>[0x00])
      ..add(ascii.encode(mime))
      ..add(<int>[0x00, 0x03, 0x00]) // tipo portada + descripción vacía
      ..add(image);
    return out.takeBytes();
  }

  static String _mimeOf(Uint8List image) {
    if (image.length > 3 &&
        image[0] == 0xFF &&
        image[1] == 0xD8 &&
        image[2] == 0xFF) {
      return 'image/jpeg';
    }
    return 'image/png';
  }

  static Uint8List _vorbisComment(TrackTags tags) {
    final entries = <String>[
      if (tags.title.trim().isNotEmpty) 'TITLE=${tags.title.trim()}',
      if (tags.artist.trim().isNotEmpty) 'ARTIST=${tags.artist.trim()}',
      if (tags.album.trim().isNotEmpty) 'ALBUM=${tags.album.trim()}',
      if (tags.year.trim().isNotEmpty) 'DATE=${_yearOf(tags.year.trim())}',
      if (tags.genre.trim().isNotEmpty) 'GENRE=${tags.genre.trim()}',
      if (tags.track > 0) 'TRACKNUMBER=${tags.track}',
    ];
    final out = BytesBuilder();
    final vendor = utf8.encode('CyberHex');
    out.add(_le32(vendor.length));
    out.add(vendor);
    out.add(_le32(entries.length));
    for (final entry in entries) {
      final bytes = utf8.encode(entry);
      out.add(_le32(bytes.length));
      out.add(bytes);
    }
    return out.takeBytes();
  }

  static Uint8List _pictureBlock(Uint8List image) {
    final mime = utf8.encode(_mimeOf(image));
    final out = BytesBuilder()
      ..add(_be32(3)) // portada frontal
      ..add(_be32(mime.length))
      ..add(mime)
      ..add(_be32(0)) // descripción vacía
      ..add(_be32(0)) // ancho (desconocido: 0 es válido)
      ..add(_be32(0))
      ..add(_be32(0))
      ..add(_be32(0))
      ..add(_be32(image.length))
      ..add(image);
    return out.takeBytes();
  }

  static Uint8List _le32(int value) => Uint8List(4)
    ..[0] = value & 0xFF
    ..[1] = (value >> 8) & 0xFF
    ..[2] = (value >> 16) & 0xFF
    ..[3] = (value >> 24) & 0xFF;

  static Uint8List _be32(int value) => Uint8List(4)
    ..[0] = (value >> 24) & 0xFF
    ..[1] = (value >> 16) & 0xFF
    ..[2] = (value >> 8) & 0xFF
    ..[3] = value & 0xFF;

  static Uint8List _syncsafeBytes(int value) => Uint8List(4)
    ..[0] = (value >> 21) & 0x7F
    ..[1] = (value >> 14) & 0x7F
    ..[2] = (value >> 7) & 0x7F
    ..[3] = value & 0x7F;

  static int _indexOf(Uint8List data, int value, int from) {
    for (var i = from; i < data.length; i++) {
      if (data[i] == value) return i;
    }
    return -1;
  }

  /// Fin del terminador de la cadena que empieza en [start]: en UTF-16 son dos
  /// ceros, en el resto uno.
  static int _terminatorEnd(Uint8List data, int start, int encoding) {
    final wide = encoding == 1 || encoding == 2;
    for (var i = start; i + 1 < data.length; i += wide ? 2 : 1) {
      if (data[i] == 0 && (!wide || data[i + 1] == 0)) {
        return i + (wide ? 2 : 1);
      }
    }
    return -1;
  }
}

int _min(int a, int b) => a < b ? a : b;
