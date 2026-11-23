import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyberhex/core/backup_service.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/radio_store.dart';
import 'package:cyberhex/core/scrobbler.dart';
import 'package:cyberhex/core/theme_controller.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/network_page.dart';
import 'package:cyberhex/ui/audio_export_sheet.dart';
import 'package:cyberhex/ui/settings_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

/// Servidor HTTP local que sirve un flujo de audio falso, listas m3u/pls y
/// acepta los POST de ListenBrainz/Last.fm.
class _TestServer {
  _TestServer(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<String> requestLog = <String>[];
  final List<Map<String, String>> postedBodies = <Map<String, String>>[];
  final List<String> postedRaw = <String>[];
  final List<String> authHeaders = <String>[];

  /// Bytes de audio que devuelve `/stream`.
  int streamBytes = 40 * 1024;

  /// Código a devolver en `/stream` (para probar errores).
  int streamStatus = 200;

  /// Código a devolver en las APIs de scrobbling.
  int apiStatus = 200;

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    requestLog.add('${request.method} ${request.uri.path}');
    final path = request.uri.path;

    if (path == '/radio.m3u') {
      request.response.headers.contentType = ContentType('audio', 'x-mpegurl');
      request.response.write('#EXTM3U\n#EXTINF:-1,Prueba\n${url('/stream')}\n');
      await request.response.close();
      return;
    }

    if (path == '/stream') {
      if (streamStatus != 200) {
        request.response.statusCode = streamStatus;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      final payload = List<int>.generate(streamBytes, (index) => index % 251);
      var sent = 0;
      while (sent < payload.length) {
        final end = (sent + 4096) > payload.length
            ? payload.length
            : sent + 4096;
        request.response.add(payload.sublist(sent, end));
        sent = end;
      }
      await request.response.close();
      return;
    }

    if (path == '/submit-listens' || path == '/ws/2.0/') {
      authHeaders.add(request.headers.value('authorization') ?? '');
      final body = await utf8.decoder.bind(request).join();
      postedRaw.add(body);
      postedBodies.add(<String, String>{
        'contentType': request.headers.contentType?.mimeType ?? '',
        'body': body,
      });
      request.response.statusCode = apiStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        apiStatus == 200 ? '{"status":"ok"}' : '{"error":9}',
      );
      await request.response.close();
      return;
    }

    if (path.startsWith('/dav')) {
      // El cliente manda un cuerpo XML: hay que consumirlo antes de responder.
      await request.drain<void>();
      request.response.statusCode = 207;
      request.response.headers.contentType = ContentType(
        'application',
        'xml',
        charset: 'utf-8',
      );
      request.response.write('''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/m%C3%BAsica/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/m%C3%BAsica/tema%20uno.flac</d:href>
    <d:propstat><d:prop><d:getcontentlength>1234567</d:getcontentlength><d:resourcetype/></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/m%C3%BAsica/sub/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
</d:multistatus>''');
      await request.response.close();
      return;
    }

    request.response.statusCode = 404;
    await request.response.close();
  }
}

void main() {
  // `flutter_test` sustituye `HttpClient` por uno falso que contesta 400 a
  // todo: los tests que levantan un `HttpServer` de verdad necesitan el real.
  // Se repone antes de cada test porque el binding se inicializa en `main()`.
  setUp(() => HttpOverrides.global = null);
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cyberhex9_');
  });

  tearDown(() {
    // Algún test deja una descarga a medias: no se falla por el borrado.
    if (temp.existsSync()) {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // da igual: es un directorio temporal
      }
    }
  });

  group('RadioStore', () {
    test('alta, deduplicado por URL, renombrado y baja', () {
      final store = RadioStore.memory();
      addTearDown(store.dispose);

      final first = store.add(name: 'Uno', url: 'https://a.example/stream');
      expect(store.length, 1);
      final again = store.add(
        name: 'Otro nombre',
        url: 'https://a.example/stream',
      );
      expect(again.id, first.id, reason: 'misma URL no se duplica');
      expect(store.length, 1);

      expect(store.rename(first.id, 'Renombrada'), isTrue);
      expect(store.stations.single.name, 'Renombrada');
      expect(store.remove(first.id), isTrue);
      expect(store.isEmpty, isTrue);
      expect(store.remove('no-existe'), isFalse);
    });

    test('sin nombre se usa el host', () {
      final store = RadioStore.memory();
      addTearDown(store.dispose);
      final station = store.add(
        name: '',
        url: 'https://radio.ejemplo/live.mp3',
      );
      expect(station.name, 'radio.ejemplo');
      expect(station.host, 'radio.ejemplo');
    });

    test('importa .m3u y .pls y exporta .m3u', () async {
      final store = RadioStore.memory();
      addTearDown(store.dispose);

      final m3u = File('${temp.path}/lista.m3u')
        ..writeAsStringSync(
          '#EXTM3U\n'
          '#EXTINF:-1,Soma Groove\n'
          'https://ice.example/groove\n'
          '#EXTINF:-1,Relativa\n'
          'otra/emisora.mp3\n',
        );
      final added = await store.importPlaylist(m3u);
      expect(added, hasLength(2));
      expect(added.first.name, 'Soma Groove');
      expect(added[1].url, startsWith('file://'));
      expect(added[1].url, endsWith('otra/emisora.mp3'));

      final pls = File('${temp.path}/lista.pls')
        ..writeAsStringSync(
          '[playlist]\n'
          'NumberOfEntries=1\n'
          'File1=https://pls.example/stream\n'
          'Title1=Desde PLS\n',
        );
      final more = await store.importPlaylist(pls);
      expect(more, hasLength(1));
      expect(more.single.name, 'Desde PLS');
      expect(store.length, 3);

      // Importar otra vez no duplica.
      expect(await store.importPlaylist(m3u), isEmpty);

      final target = File('${temp.path}/salida.m3u');
      await store.exportM3u(target);
      final text = target.readAsStringSync();
      expect(text, startsWith('#EXTM3U'));
      expect(text, contains('#EXTINF:-1,Desde PLS'));
      expect(text, contains('https://pls.example/stream'));
      expect(text, contains('https://ice.example/groove'));
      expect(File('${temp.path}/salida.m3u.tmp').existsSync(), isFalse);
    });

    test('parsea m3u con directivas y pls con títulos', () {
      final m3u = RadioStore.parsePlaylistText(
        '#EXTM3U\n#EXTINF:-1 tvg-name="X",Nombre Uno\nhttps://a/1\n'
        '#EXTINF:-1,Sin URL\n',
      );
      expect(m3u, hasLength(1), reason: 'un EXTINF sin URL no es una emisora');
      expect(m3u.first.name, 'Nombre Uno');
      expect(m3u.first.url, 'https://a/1');

      final pls = RadioStore.parsePlaylistText(
        '[playlist]\nFile2=https://b/2\nTitle2=Dos\nFile1=https://a/1\nTitle1=Uno\n',
      );
      expect(pls.map((seed) => seed.url), <String>[
        'https://a/1',
        'https://b/2',
      ]);
      expect(pls.map((seed) => seed.name), <String>['Uno', 'Dos']);

      // Lo que no es http(s) se ignora.
      final raro = RadioStore.parsePlaylistText(
        'javascript:alert(1)\nftp://x/y\n',
      );
      expect(raro, isEmpty);
    });

    test('guarda y recupera las emisoras (JSON atómico)', () async {
      final file = File('${temp.path}/radios.json');
      final first = RadioStore(file: file);
      first.add(name: 'Guardada', url: 'https://keep.example/s', genre: 'Jazz');
      await first.save();
      expect(file.existsSync(), isTrue);
      expect(File('${file.path}.tmp').existsSync(), isFalse);

      final second = RadioStore(file: file);
      await second.load();
      expect(second.length, 1);
      expect(second.stations.single.name, 'Guardada');
      expect(second.stations.single.genre, 'Jazz');
    });

    test('un JSON roto no impide arrancar', () async {
      final file = File('${temp.path}/radios.json')..writeAsStringSync('{roto');
      final store = RadioStore(file: file);
      await store.load();
      expect(store.isEmpty, isTrue);
    });

    test('baja un flujo HTTP a un archivo reproducible', () async {
      final server = _TestServer(await HttpServer.bind('127.0.0.1', 0));
      addTearDown(server.close);
      server.streamBytes = 9000;
      final store = RadioStore.memory();
      addTearDown(store.dispose);

      var progress = 0;
      final buffer = await store.buffer(
        server.url('/stream'),
        window: const Duration(seconds: 2),
        directory: temp,
        onProgress: (bytes) => progress = bytes,
      );

      expect(buffer.file.existsSync(), isTrue);
      expect(buffer.file.path, endsWith('.mp3'));
      expect(buffer.bytes, 9000);
      expect(progress, greaterThan(0));
      expect(buffer.truncated, isFalse, reason: 'el servidor cerró el flujo');
      expect(buffer.contentType, 'audio/mpeg');
      expect(File('${buffer.file.path}.part').existsSync(), isFalse);
    });

    test('una lista .m3u se resuelve a su flujo', () async {
      final server = _TestServer(await HttpServer.bind('127.0.0.1', 0));
      addTearDown(server.close);
      final store = RadioStore.memory();
      addTearDown(store.dispose);

      final resolved = await store.resolve(server.url('/radio.m3u'));
      expect(resolved.path, '/stream');
    });

    test('un 404 se convierte en RadioException', () async {
      final server = _TestServer(await HttpServer.bind('127.0.0.1', 0));
      addTearDown(server.close);
      server.streamStatus = 404;
      final store = RadioStore.memory();
      addTearDown(store.dispose);

      await expectLater(
        store.buffer(server.url('/stream'), directory: temp),
        throwsA(isA<RadioException>()),
      );
    });
  });

  group('Scrobbler', () {
    test('MD5 coincide con los vectores de siempre', () {
      expect(md5Hex(''), 'd41d8cd98f00b204e9800998ecf8427e');
      expect(md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72');
      expect(
        md5Hex('The quick brown fox jumps over the lazy dog'),
        '9e107d9d372bb6826bd81d3542a419d6',
      );
    });

    test('la firma de Last.fm ordena claves y añade el secreto', () {
      final signature = Scrobbler.lastFmSignature(<String, String>{
        'b': '2',
        'a': '1',
        'api_sig': 'ignorada',
      }, 'secreto');
      expect(signature, md5Hex('a1b2secreto'));
    });

    test('cuenta la escucha al pasar la mitad', () async {
      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Tema'
        ..artist = 'Grupo'
        ..duration = 600;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();

      final scrobbler = Scrobbler.memory(controller);
      addTearDown(scrobbler.dispose);
      scrobbler.updateSettings(
        const ScrobbleSettings(enabled: true, listenBrainzToken: 'token'),
      );

      controller.seek(299);
      expect(scrobbler.pending, isEmpty);
      controller.seek(300);
      expect(scrobbler.pending, hasLength(1));
      expect(scrobbler.pending.single.title, 'Tema');
      expect(scrobbler.pending.single.artist, 'Grupo');
    });

    test('pistas muy cortas no cuentan', () async {
      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Jingle'
        ..artist = 'Marca'
        ..duration = 20;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();

      final scrobbler = Scrobbler.memory(controller);
      addTearDown(scrobbler.dispose);
      scrobbler.updateSettings(
        const ScrobbleSettings(enabled: true, listenBrainzToken: 'token'),
      );
      controller.seek(19);
      expect(scrobbler.pending, isEmpty);
    });

    test('con el scrobbling apagado no se acumula nada', () async {
      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Tema'
        ..artist = 'Grupo'
        ..duration = 600;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();

      final scrobbler = Scrobbler.memory(controller);
      addTearDown(scrobbler.dispose);
      controller.seek(500);
      expect(scrobbler.pending, isEmpty);
    });

    test('envía a ListenBrainz con token y a Last.fm firmado', () async {
      final server = _TestServer(await HttpServer.bind('127.0.0.1', 0));
      addTearDown(server.close);

      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Canción'
        ..artist = 'Artista'
        ..album = 'Disco'
        ..duration = 600;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();

      final scrobbler = Scrobbler.memory(controller);
      addTearDown(scrobbler.dispose);
      scrobbler.listenBrainzEndpoint = server.url('/submit-listens');
      scrobbler.lastFmEndpoint = server.url('/ws/2.0/');
      scrobbler.updateSettings(
        const ScrobbleSettings(
          enabled: true,
          listenBrainzToken: 'secreto-lb',
          lastFmApiKey: 'clave',
          lastFmApiSecret: 'firma',
          lastFmSessionKey: 'sesion',
          lastFmUsername: 'usuario',
        ),
      );

      controller.seek(500);
      expect(scrobbler.pending, hasLength(1));
      final ok = await scrobbler.flush();
      expect(ok, isTrue);
      expect(scrobbler.pending, isEmpty);
      expect(scrobbler.submitted, 1);

      // ListenBrainz.
      final listen = server.postedRaw.firstWhere(
        (body) => body.contains('listen_type'),
      );
      final listenJson = jsonDecode(listen) as Map<String, Object?>;
      final payload =
          (listenJson['payload'] as List<Object?>).single
              as Map<String, Object?>;
      final metadata = payload['track_metadata'] as Map<String, Object?>;
      expect(metadata['artist_name'], 'Artista');
      expect(metadata['track_name'], 'Canción');
      expect(metadata['release_name'], 'Disco');
      expect(payload['listened_at'], isA<int>());
      expect(server.authHeaders.first, 'Token secreto-lb');

      // Last.fm.
      final form = server.postedRaw.firstWhere(
        (body) => body.contains('api_sig'),
      );
      final fields = Uri.splitQueryString(form);
      expect(fields['method'], 'track.scrobble');
      expect(fields['api_key'], 'clave');
      expect(fields['sk'], 'sesion');
      expect(fields['artist[0]'], 'Artista');
      expect(fields['track[0]'], 'Canción');
      final unsigned = Map<String, String>.of(fields)..remove('api_sig');
      expect(fields['api_sig'], Scrobbler.lastFmSignature(unsigned, 'firma'));
    });

    test('sin red la escucha se queda pendiente y se reintenta', () async {
      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Tema'
        ..artist = 'Grupo'
        ..duration = 600;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();

      final scrobbler = Scrobbler.memory(controller);
      addTearDown(scrobbler.dispose);
      // Puerto cerrado: la conexión falla.
      final dead = await HttpServer.bind('127.0.0.1', 0);
      final deadPort = dead.port;
      await dead.close();
      scrobbler.listenBrainzEndpoint = Uri.parse(
        'http://127.0.0.1:$deadPort/submit',
      );
      scrobbler.updateSettings(
        const ScrobbleSettings(enabled: true, listenBrainzToken: 'token'),
      );

      controller.seek(500);
      final ok = await scrobbler.flush();
      expect(ok, isFalse);
      expect(scrobbler.pending, hasLength(1));
      expect(scrobbler.lastError, isNotNull);
    });

    test('los ajustes y la cola sobreviven al guardado', () async {
      final file = File('${temp.path}/scrobbler.json');
      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Tema'
        ..artist = 'Grupo'
        ..duration = 600;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();

      final first = Scrobbler(controller, file: file);
      first.updateSettings(
        const ScrobbleSettings(enabled: true, listenBrainzToken: 'guardado'),
      );
      controller.seek(500);
      await first.save();
      expect(file.existsSync(), isTrue);

      final second = Scrobbler(controller, file: file);
      addTearDown(second.dispose);
      await second.load();
      expect(second.settings.enabled, isTrue);
      expect(second.settings.listenBrainzToken, 'guardado');
      expect(second.pending, hasLength(1));
      first.dispose();
    });
  });

  group('BackupService', () {
    test('exporta las secciones que existen y las restaura', () async {
      File('${temp.path}/favorites.json')
          .writeAsStringSync('{"version":1,"paths":["/a.mp3","/b.mp3"]}');
      File('${temp.path}/theme.json')
          .writeAsStringSync('{"version":1,"theme":"amoled"}');
      File('${temp.path}/radios.json')
          .writeAsStringSync('{"version":1,"stations":[]}');

      final service = BackupService(directory: temp);
      final snapshot = await service.snapshot();
      expect(snapshot['app'], 'CyberHex');
      final sections = snapshot['sections'] as Map<String, Object?>;
      expect(
        sections.keys,
        containsAll(<String>['favorites', 'theme', 'radios']),
      );
      expect(sections.keys, isNot(contains('stats')));
      final counts = snapshot['counts'] as Map<String, Object?>;
      expect(counts['favorites'], 2);

      final target = File('${temp.path}/copia.json');
      await service.exportTo(target, note: 'prueba');
      expect(target.existsSync(), isTrue);
      expect(File('${target.path}.tmp').existsSync(), isFalse);
      final decoded =
          jsonDecode(target.readAsStringSync()) as Map<String, Object?>;
      expect(decoded['note'], 'prueba');
      expect(BackupService.looksLikeBackup(decoded), isTrue);

      // Se borra el disco y se restaura.
      File('${temp.path}/favorites.json').deleteSync();
      File('${temp.path}/theme.json').deleteSync();
      final report = await service.importFrom(target);
      expect(report.restored, hasLength(3));
      expect(report.written, hasLength(3));
      expect(File('${temp.path}/favorites.json').existsSync(), isTrue);
      expect(
        File('${temp.path}/favorites.json').readAsStringSync(),
        contains('/a.mp3'),
      );
    });

    test(
      'una copia con secciones desconocidas o rotas no rompe nada',
      () async {
        final source = File('${temp.path}/rara.json')
          ..writeAsStringSync(
            jsonEncode(<String, Object?>{
              'app': 'CyberHex',
              'version': 1,
              'sections': <String, Object?>{
                'favorites': <String, Object?>{
                  'paths': <String>['/x.mp3'],
                },
                'inventada': <String, Object?>{'algo': 1},
                'stats': 'esto no es un mapa',
              },
            }),
          );
        final service = BackupService(directory: temp);
        final report = await service.importFrom(source);
        expect(report.restored, <String>['Favoritos']);
        expect(report.skipped, contains('inventada (desconocida)'));
        expect(report.skipped, contains('stats (formato)'));
        expect(File('${temp.path}/favorites.json').existsSync(), isTrue);
      },
    );

    test('rechaza un JSON que no es una copia', () async {
      final source = File('${temp.path}/otro.json')
        ..writeAsStringSync('{"hola":1}');
      final service = BackupService(directory: temp);
      await expectLater(
        service.importFrom(source),
        throwsA(isA<FormatException>()),
      );
    });

    test('sugiere un nombre con fecha', () {
      final service = BackupService(
        directory: temp,
        clock: () => DateTime(2026, 11, 21, 9, 5),
      );
      expect(service.suggestedName(), 'cyberhex-backup-20261121-0905.json');
    });
  });

  group('SettingsPage: copia y scrobbling', () {
    testWidgets('enseña las dos secciones nuevas', (tester) async {
      final theme = ThemeController.memory();
      addTearDown(theme.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildCyberHexThemed(CyberHexPalette.neon),
          home: SettingsPage(theme: theme),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('COPIA DE SEGURIDAD'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('COPIA DE SEGURIDAD'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Exportar copia'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Exportar copia'), findsOneWidget);
      expect(find.text('Restaurar copia'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('SCROBBLING'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // Sin motor no hay scrobbling que configurar.
      expect(find.textContaining('Scrobbling no disponible'), findsOneWidget);
    });

    testWidgets('el interruptor escribe en el Scrobbler', (tester) async {
      final theme = ThemeController.memory();
      addTearDown(theme.dispose);
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      final scrobbler = Scrobbler.memory(controller);
      addTearDown(scrobbler.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildCyberHexThemed(CyberHexPalette.neon),
          home: SettingsPage(
            theme: theme,
            player: controller,
            scrobbler: scrobbler,
          ),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Enviar escuchas'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(scrobbler.settings.enabled, isFalse);
      await tester.tap(find.text('Enviar escuchas'));
      await tester.pump();
      expect(scrobbler.settings.enabled, isTrue);

      await tester.scrollUntilVisible(
        find.text('ListenBrainz: token de usuario'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'ListenBrainz: token de usuario'),
        'token-prueba',
      );
      await tester.pump();
      expect(scrobbler.settings.listenBrainzToken, 'token-prueba');
    });
  });

  group('Exportador', () {
    testWidgets('muestra el rango y las dos salidas', (tester) async {
      final fake = FakePlayer(hasTrack: true, title: 'Tema', artist: 'Grupo')
        ..duration = 200
        ..queuePaths.add('/tmp/tema-de-prueba.mp3')
        ..queueIndexValue = 0;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildCyberHexThemed(CyberHexPalette.neon),
          home: Scaffold(body: AudioExportSheet(controller: controller)),
        ),
      );
      await tester.pump();

      expect(find.text('Exportar audio'), findsOneWidget);
      expect(find.text('Tema'), findsOneWidget);
      expect(find.byType(RangeSlider), findsOneWidget);
      expect(find.text('Pista masterizada'), findsOneWidget);
      expect(find.text('Tono de llamada'), findsOneWidget);
      expect(
        find.textContaining('Aplicar EQ, 9D y ancho estéreo'),
        findsOneWidget,
      );
      expect(find.text('Exportar'), findsOneWidget);
      // Sin pista no se puede exportar: aquí sí hay pista.
      expect(find.textContaining('Duración 03:20'), findsOneWidget);
    });

    testWidgets('sin pista avisa y bloquea el botón', (tester) async {
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildCyberHexThemed(CyberHexPalette.neon),
          home: Scaffold(body: AudioExportSheet(controller: controller)),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Abre una pista'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('Red: WebDAV y nube', () {
    test('parsea un 207 con carpetas, archivos y espacios codificados', () {
      final entries = WebDavClient.parseMultiStatus('''
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/m%C3%BAsica/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response><d:href>/dav/m%C3%BAsica/tema%20uno.flac</d:href>
    <d:propstat><d:prop><d:getcontentlength>1234567</d:getcontentlength><d:resourcetype/></d:prop></d:propstat>
  </d:response>
</d:multistatus>''', base: Uri.parse('http://nube.example/dav/Música/'));

      expect(entries, hasLength(2));
      expect(entries.first.isCollection, isTrue);
      expect(entries.first.name, 'música');
      expect(entries[1].name, 'tema uno.flac');
      expect(entries[1].size, 1234567);
      expect(entries[1].isAudio, isTrue);
      expect(entries[1].sizeLabel, '1.2 MB');
    });

    test('lista contra un servidor local y descarga una pista', () async {
      final server = _TestServer(await HttpServer.bind('127.0.0.1', 0));
      addTearDown(server.close);
      final client = WebDavClient();
      addTearDown(client.close);
      final store = NetworkStore.memory();
      addTearDown(store.dispose);

      final saved = store.add(
        name: 'Nube',
        url: server.url('/dav/música/').toString(),
        username: 'ana',
        password: 'clave',
      );
      expect(store.servers, hasLength(1));

      final entries = await client.list(saved, Uri.parse(saved.url));
      expect(entries.where((entry) => entry.isCollection), hasLength(1));
      expect(
        entries.firstWhere((entry) => !entry.isCollection).name,
        'tema uno.flac',
      );
    });

    test('NetworkStore guarda y recupera servidores', () async {
      final file = File('${temp.path}/network.json');
      final first = NetworkStore(file: file);
      first.add(
        name: 'Casa',
        url: 'https://nas.local/dav/',
        username: 'u',
        password: 'p',
      );
      first.add(
        name: 'Enlace',
        url: 'https://cloud.example/s/abc/download',
        kind: RemoteKind.cloud,
        token: 'bearer',
      );
      await first.save();

      final second = NetworkStore(file: file);
      await second.load();
      expect(second.servers, hasLength(2));
      final nas = second.servers.first;
      expect(nas.username, 'u');
      expect(nas.usesBearer, isFalse);
      final cloud = second.servers.last;
      expect(cloud.kind, RemoteKind.cloud);
      expect(cloud.usesBearer, isTrue);
      expect(second.remove(cloud.id), isTrue);
    });
  });
}
