import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cyberhex/core/lyrics_parser.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/tag_editor.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/lyrics_creator_page.dart';
import 'package:cyberhex/ui/lyrics_page.dart';
import 'package:cyberhex/ui/share_card_sheet.dart';
import 'package:cyberhex/ui/tag_editor_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

// ---------------------------------------------------------------------------
// Ayudantes para fabricar contenedores de audio con etiquetas
// ---------------------------------------------------------------------------

Uint8List _ascii(String value) => Uint8List.fromList(ascii.encode(value));

Uint8List _syncsafe(int value) => Uint8List(4)
  ..[0] = (value >> 21) & 0x7F
  ..[1] = (value >> 14) & 0x7F
  ..[2] = (value >> 7) & 0x7F
  ..[3] = value & 0x7F;

Uint8List _be32(int value) => Uint8List(4)
  ..[0] = (value >> 24) & 0xFF
  ..[1] = (value >> 16) & 0xFF
  ..[2] = (value >> 8) & 0xFF
  ..[3] = value & 0xFF;

Uint8List _le32(int value) => Uint8List(4)
  ..[0] = value & 0xFF
  ..[1] = (value >> 8) & 0xFF
  ..[2] = (value >> 16) & 0xFF
  ..[3] = (value >> 24) & 0xFF;

/// ID3v2.3 con un marco `USLT` en UTF-8.
Uint8List _id3WithUslt(String lyrics) {
  final payload = BytesBuilder()
    ..add(<int>[0x03])
    ..add(_ascii('eng'))
    ..add(<int>[0x00])
    ..add(utf8.encode(lyrics));
  final body = payload.takeBytes();
  final frame = BytesBuilder()
    ..add(_ascii('USLT'))
    ..add(_be32(body.length))
    ..add(<int>[0, 0])
    ..add(body);
  final frames = frame.takeBytes();
  return (BytesBuilder()
        ..add(<int>[0x49, 0x44, 0x33, 3, 0, 0])
        ..add(_syncsafe(frames.length))
        ..add(frames)
        ..add(Uint8List(64)))
      .takeBytes();
}

/// FLAC mínimo: `fLaC` + STREAMINFO + VORBIS_COMMENT con `LYRICS=`.
Uint8List _flacWithLyrics(String lyrics) {
  final comments = <String>['TITLE=Con letra', 'ARTIST=Alguien', 'LYRICS=$lyrics'];
  final vendor = utf8.encode('test');
  final block = BytesBuilder()
    ..add(_le32(vendor.length))
    ..add(vendor)
    ..add(_le32(comments.length));
  for (final comment in comments) {
    final bytes = utf8.encode(comment);
    block.add(_le32(bytes.length));
    block.add(bytes);
  }
  final commentData = block.takeBytes();
  final out = BytesBuilder()
    ..add(_ascii('fLaC'))
    ..add(<int>[0x00, 0x00, 0x00, 0x22]) // STREAMINFO, 34 B, no es el último
    ..add(Uint8List(34))
    ..add(<int>[
      0x84,
      (commentData.length >> 16) & 0xFF,
      (commentData.length >> 8) & 0xFF,
      commentData.length & 0xFF,
    ])
    ..add(commentData)
    ..add(_ascii('AUDIO'));
  return out.takeBytes();
}

/// Directorio temporal por prueba, sin depender de `path_provider`.
Directory _tempDir(String name) {
  final dir = Directory('${Directory.systemTemp.path}/cyberhex_$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir;
}

/// `Uint8List` de una imagen PNG de 1×1 (válida como carátula).
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Widget _app(Widget child) => MaterialApp(
      theme: buildCyberHexTheme(),
      home: child,
    );

void main() {
  group('LyricsParser: .lrc', () {
    test('lee metadatos y líneas con tiempo', () {
      final lyrics = LyricsParser.parse('''
[ti:Canción]
[ar:Artista]
[al:Álbum]
[offset:+500]
[00:01.50]Primera línea
[00:10.00]Segunda línea
''');
      expect(lyrics.title, 'Canción');
      expect(lyrics.artist, 'Artista');
      expect(lyrics.album, 'Álbum');
      expect(lyrics.offsetMs, 500);
      expect(lyrics.lines.length, 2);
      expect(lyrics.lines.first.time, 1.5);
      expect(lyrics.lines.first.isTimed, isTrue);
      // Con offset +0,5 s la primera línea se presenta en el segundo 2.
      expect(lyrics.displayTime(lyrics.lines.first), 2.0);
      expect(lyrics.indexAt(1.6), -1);
      expect(lyrics.indexAt(2.0), 0);
      expect(lyrics.indexAt(500), 1);
    });

    test('varias marcas en una línea crean una entrada por marca', () {
      final lyrics = LyricsParser.parse('[00:10.00][01:20.00]Estribillo');
      expect(lyrics.lines.length, 2);
      expect(lyrics.lines.every((line) => line.text == 'Estribillo'), isTrue);
      expect(lyrics.lines[1].time, 80);
    });

    test('bilingüe: misma marca en dos líneas se fusiona', () {
      final lyrics = LyricsParser.parse('''
[00:05.00]Hello world
[00:05.00]Hola mundo
[00:09.00]Next line
''');
      expect(lyrics.lines.length, 2);
      expect(lyrics.lines.first.text, 'Hello world');
      expect(lyrics.lines.first.translation, 'Hola mundo');
      expect(lyrics.lines[1].hasTranslation, isFalse);
    });

    test('bilingüe: separador | en la misma línea', () {
      final lyrics = LyricsParser.parse('[00:03.00]Hola mundo|Hello world');
      expect(lyrics.lines.single.text, 'Hola mundo');
      expect(lyrics.lines.single.translation, 'Hello world');
    });

    test('línea suelta sin marca tras una con marca es su traducción', () {
      final lyrics = LyricsParser.parse('''
[00:02.00]Ligne un
Deuxième ligne
''');
      expect(lyrics.lines.single.translation, 'Deuxième ligne');
    });

    test('texto plano: todas sin tiempo y se puede escribir .lrc', () {
      final plain = LyricsParser.parsePlain('Uno\n\nDos\nTres');
      expect(plain.lines.length, 3);
      expect(plain.isTimed, isFalse);
      expect(plain.lines.every((line) => line.time == -1), isTrue);
    });

    test('build y parse hacen ida y vuelta', () {
      final lyrics = Lyrics(lines: <LyricLine>[
        const LyricLine(time: 3.25, text: 'Uno', translation: 'One'),
        const LyricLine(time: 61.5, text: 'Dos'),
      ], tags: <String, String>{'ti': 'Tema', 'ar': 'Grupo'});
      final text = LrcWriter.build(lyrics);
      expect(text.contains('[ti:Tema]'), isTrue);
      final again = LyricsParser.parse(text);
      expect(again.lines.length, 2);
      expect(again.lines.first.time, 3.25);
      expect(again.lines.first.translation, 'One');
      expect(again.lines[1].time, 61.5);
      expect(again.title, 'Tema');
    });

    test('la ruta del .lrc sigue al audio', () {
      expect(LyricsParser.lrcPathFor('/m/tema.flac'), '/m/tema.lrc');
      expect(LyricsParser.lrcPathFor('/m/tema'), '/m/tema.lrc');
    });

    test('un archivo vacío o basura no lanza', () {
      expect(LyricsParser.parse('').isEmpty, isTrue);
      expect(LyricsParser.parse('[99:99.99]imposible').isEmpty, isTrue);
      expect(LyricsParser.parse('solo texto').lines.single.text, 'solo texto');
    });
  });

  group('Letras incrustadas', () {
    test('USLT de ID3v2 en UTF-8', () {
      final bytes = _id3WithUslt('[00:04.00]Desde el MP3');
      expect(LyricsParser.id3Uslt(bytes), '[00:04.00]Desde el MP3');
      final lyrics = LyricsParser.readEmbedded(bytes);
      expect(lyrics.origin, 'embedded');
      expect(lyrics.lines.single.text, 'Desde el MP3');
    });

    test('LYRICS del Vorbis comment de FLAC', () {
      final bytes = _flacWithLyrics('[00:07.00]Desde el FLAC');
      expect(LyricsParser.flacLyrics(bytes), '[00:07.00]Desde el FLAC');
      expect(LyricsParser.readEmbedded(bytes).lines.single.time, 7);
    });

    test('carga el .lrc de al lado antes que lo incrustado', () async {
      final dir = _tempDir('lrc_sidecar');
      final audio = File('${dir.path}/tema.mp3');
      audio.writeAsBytesSync(_id3WithUslt('[00:01.00]Incrustada'));
      File('${dir.path}/tema.lrc').writeAsStringSync('[00:02.00]De al lado');
      final lyrics = await LyricsParser.loadForAudio(audio.path);
      expect(lyrics.lines.single.text, 'De al lado');
      // Sin el .lrc, cae en la incrustada.
      File('${dir.path}/tema.lrc').deleteSync();
      final embedded = await LyricsParser.loadForAudio(audio.path);
      expect(embedded.lines.single.text, 'Incrustada');
      dir.deleteSync(recursive: true);
    });
  });

  group('TagEditor', () {
    const tags = TrackTags(
      title: 'Título',
      artist: 'Artista',
      album: 'Álbum',
      year: '1999',
      genre: 'Rock',
      track: 7,
    );

    test('ID3v2.3 escrito y leído de vuelta', () {
      final bytes = TagEditor.buildId3v2(tags);
      expect(String.fromCharCodes(bytes.sublist(0, 3)), 'ID3');
      final read = TagEditor.readBytes(bytes);
      expect(read.title, 'Título');
      expect(read.artist, 'Artista');
      expect(read.album, 'Álbum');
      expect(read.year, '1999');
      expect(read.genre, 'Rock');
      expect(read.track, 7);
      expect(read.hasCover, isFalse);
    });

    test('la carátula viaja en APIC y vuelve igual', () {
      final withCover = tags.copyWith(cover: _tinyPng);
      final read = TagEditor.readBytes(TagEditor.buildId3v2(withCover));
      expect(read.hasCover, isTrue);
      expect(read.cover!.length, _tinyPng.length);
    });

    test('reescribir ID3 conserva el audio que venía detrás', () {
      final audio = BytesBuilder()
        ..add(_id3WithUslt('[00:01.00]vieja'))
        ..add(_ascii('AUDIO-REAL'));
      final rewritten = TagEditor.rewriteId3(audio.takeBytes(), tags);
      final asText = latin1.decode(rewritten);
      expect(asText.contains('AUDIO-REAL'), isTrue);
      expect(TagEditor.readBytes(rewritten).title, 'Título');
      // Sin doble etiqueta: solo una cabecera ID3 al principio.
      final second = latin1.decode(rewritten).indexOf('ID3', 1);
      expect(second, -1);
    });

    test('FLAC: Vorbis comment y PICTURE de ida y vuelta', () {
      final source = _flacWithLyrics('[00:01.00]x');
      final rewritten = TagEditor.rewriteFlac(
        source,
        tags.copyWith(cover: _tinyPng),
      );
      final read = TagEditor.readBytes(rewritten);
      expect(read.title, 'Título');
      expect(read.album, 'Álbum');
      expect(read.track, 7);
      expect(read.hasCover, isTrue);
      // El audio de después de los bloques sigue ahí.
      expect(latin1.decode(rewritten).contains('AUDIO'), isTrue);
    });

    test('escribe en disco y edita el álbum completo', () async {
      final dir = _tempDir('tags_write');
      final one = File('${dir.path}/01.mp3')
        ..writeAsBytesSync(TagEditor.buildId3v2(const TrackTags(title: 'Uno')));
      final two = File('${dir.path}/02.mp3')
        ..writeAsBytesSync(TagEditor.buildId3v2(const TrackTags(title: 'Dos')));
      final report = await TagEditor.write(one, tags);
      expect(report.ok, isTrue);
      expect(TagEditor.read(one).artist, 'Artista');

      final albumReport = await TagEditor.writeMany(
        <File>[one, two],
        const TrackTags(artist: 'Grupo', album: 'Disco'),
      );
      expect(albumReport.written, 2);
      expect(TagEditor.read(one).title, 'Título');
      expect(TagEditor.read(one).artist, 'Grupo');
      expect(TagEditor.read(two).title, 'Dos');
      expect(TagEditor.read(two).album, 'Disco');

      final siblings = TagEditor.albumSiblings(one);
      expect(siblings.length, 2);
      dir.deleteSync(recursive: true);
    });

    test('un formato desconocido no se escribe y lo dice', () async {
      final dir = _tempDir('tags_m4a');
      final file = File('${dir.path}/tema.m4a')..writeAsBytesSync(<int>[1, 2, 3]);
      final report = await TagEditor.write(file, tags);
      expect(report.ok, isFalse);
      expect(report.error, contains('no admite'));
      expect(TagEditor.canWrite('x.flac'), isTrue);
      expect(TagEditor.canWrite('x.ogg'), isFalse);
      dir.deleteSync(recursive: true);
    });
  });

  group('LyricsPage', () {
    Lyrics lyricsFor() => Lyrics(lines: <LyricLine>[
          const LyricLine(time: 1, text: 'Primera'),
          const LyricLine(time: 5, text: 'Segunda', translation: 'Second'),
          const LyricLine(time: 9, text: 'Tercera'),
        ], origin: 'lrc');

    testWidgets('muestra los versos y salta al tocar uno', (tester) async {
      final fake = FakePlayer()..hasTrack = true;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        LyricsPage(controller: controller, initial: lyricsFor(), autoLoad: false),
      ));
      await tester.pump();

      expect(find.text('Primera'), findsOneWidget);
      expect(find.text('Segunda'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget, reason: 'traducción visible');

      await tester.tap(find.text('Segunda'));
      await tester.pump();
      expect(fake.position, 5);
      expect(controller.position.value, 5);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin letra explica de dónde la saca', (tester) async {
      final fake = FakePlayer()..hasTrack = true;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        LyricsPage(controller: controller, autoLoad: false),
      ));
      await tester.pump();

      expect(find.textContaining('no trae letra'), findsOneWidget);
      expect(find.textContaining('USLT'), findsOneWidget);
      expect(find.text('Crear la letra'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('LyricsCreatorPage', () {
    testWidgets('pega, marca dos versos y guarda el .lrc junto al audio',
        (tester) async {
      final dir = _tempDir('creator');
      final audio = File('${dir.path}/tema.mp3')
        ..writeAsBytesSync(<int>[0, 1, 2, 3]);
      final fake = FakePlayer()
        ..title = 'Tema'
        ..artist = 'Grupo';
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      await controller.openFile(audio.path);

      await tester.pumpWidget(_app(LyricsCreatorPage(controller: controller)));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Uno\nDos\nTres');
      await tester.tap(find.text('Preparar versos'));
      await tester.pump();
      expect(find.text('Marcar verso'), findsOneWidget);

      controller.seek(12.5);
      await tester.pump();
      await tester.tap(find.text('Marcar verso'));
      await tester.pump();
      controller.seek(20.25);
      await tester.pump();
      await tester.tap(find.text('Marcar verso'));
      await tester.pump();
      expect(find.text('00:12.50'), findsOneWidget);
      expect(find.text('00:20.25'), findsOneWidget);

      // Ajuste fino del último verso: +0,1 s.
      await tester.tap(find.text('+ 0,1 s'));
      await tester.pump();
      expect(find.text('00:20.35'), findsOneWidget);

      await tester.tap(find.byTooltip('Guardar .lrc junto al audio'));
      await tester.pump();

      final lrc = File('${dir.path}/tema.lrc');
      expect(lrc.existsSync(), isTrue);
      final parsed = LyricsParser.parse(lrc.readAsStringSync());
      expect(parsed.lines.length, 2);
      expect(parsed.lines.first.time, 12.5);
      expect(parsed.lines[1].time, closeTo(20.35, 0.001));
      expect(parsed.title, 'Tema');
      expect(parsed.artist, 'Grupo');

      await tester.pumpWidget(const SizedBox());
      dir.deleteSync(recursive: true);
    });

    testWidgets('sin pista no inventa el .lrc', (tester) async {
      final controller = PlayerController(FakePlayer());
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(LyricsCreatorPage(controller: controller)));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Solo un verso');
      await tester.tap(find.text('Preparar versos'));
      await tester.pump();
      await tester.tap(find.text('Marcar verso'));
      await tester.pump();
      await tester.tap(find.byTooltip('Guardar .lrc junto al audio'));
      await tester.pump();

      expect(find.textContaining('Abre una pista'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('TagEditorSheet', () {
    testWidgets('carga las etiquetas del archivo y las guarda', (tester) async {
      final dir = _tempDir('tag_sheet');
      final audio = File('${dir.path}/tema.mp3')
        ..writeAsBytesSync(TagEditor.buildId3v2(
          const TrackTags(title: 'Viejo', artist: 'Viejo artista'),
        ));
      final controller = PlayerController(FakePlayer());
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        Scaffold(body: TagEditorSheet(controller: controller, path: audio.path)),
      ));
      await tester.pump();

      expect(find.text('Etiquetas y carátula'), findsOneWidget);
      expect(find.text('Viejo artista'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Título'),
        'Nuevo título',
      );
      // El botón puede quedar por debajo del pliegue del panel.
      await tester.ensureVisible(find.text('Guardar'));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Guardar'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();

      // Primero lo que cuenta el panel: si falló, el mensaje sale aquí y no
      // hay que adivinar por qué el archivo sigue igual.
      expect(find.textContaining('actualizados'), findsOneWidget);
      final read = TagEditor.read(audio);
      expect(read.title, 'Nuevo título');
      expect(read.artist, 'Viejo artista');

      await tester.pumpWidget(const SizedBox());
      dir.deleteSync(recursive: true);
    });
  });

  group('ShareCardSheet', () {
    test('la forma de onda es determinista y depende de la semilla', () {
      final a = shareWaveform('Tema|Grupo');
      final b = shareWaveform('Tema|Grupo');
      final c = shareWaveform('Otro|Grupo');
      expect(a, b);
      expect(a.length, 46);
      expect(a, isNot(c));
      expect(a.every((value) => value > 0 && value <= 1), isTrue);
    });

    testWidgets('pinta la tarjeta con carátula, verso y marca', (tester) async {
      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Tema'
        ..artist = 'Grupo'
        ..album = 'Disco';
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(ShareCard(
        title: 'Tema',
        artist: 'Grupo',
        album: 'Disco',
        cover: _tinyPng,
        verse: 'Y el cielo se abrió',
      )));
      await tester.pump();

      expect(find.text('Y el cielo se abrió'), findsOneWidget);
      expect(find.text('Tema'), findsOneWidget);
      expect(find.text('Grupo · Disco'), findsOneWidget);
      expect(find.text('CYBERHEX'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('la hoja propone el verso que suena y deja cambiarlo',
        (tester) async {
      final fake = FakePlayer()..hasTrack = true;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.position.value = 5;

      final lyrics = Lyrics(lines: <LyricLine>[
        const LyricLine(time: 1, text: 'Uno'),
        const LyricLine(time: 5, text: 'Dos'),
      ]);
      await tester.pumpWidget(_app(
        Scaffold(body: ShareCardSheet(controller: controller, lyrics: lyrics)),
      ));
      await tester.pump();

      expect(find.text('Tarjeta compartible'), findsOneWidget);
      // El verso puede ir entre comillas tipográficas: se busca el texto dentro.
      expect(find.textContaining('Dos'), findsWidgets);

      await tester.ensureVisible(find.text('Otro verso'));
      await tester.tap(find.text('Otro verso'));
      await tester.pump();
      expect(find.textContaining('Uno'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
