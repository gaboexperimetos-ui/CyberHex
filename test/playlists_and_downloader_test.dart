import 'dart:io';

import 'package:cyberhex/core/audio_downloader.dart';
import 'package:cyberhex/core/automix_engine.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/playlist_store.dart';
import 'package:cyberhex/core/stats_store.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/downloader_page.dart';
import 'package:cyberhex/ui/playlists_page.dart';
import 'package:cyberhex/ui/queue_sheet.dart';
import 'package:cyberhex/ui/stats_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

Directory _tempDir(String name) {
  final dir = Directory('${Directory.systemTemp.path}/cyberhex5_$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir;
}

Widget _app(Widget child) => MaterialApp(theme: buildCyberHexTheme(), home: child);

/// Descargador falso: sin red, pero con la misma interfaz que el real.
class _FakeDownloader extends AudioDownloader {
  _FakeDownloader() : super(directory: Directory.systemTemp.path);

  @override
  Future<List<ArchiveItem>> search(String query, {int rows = 12}) async {
    return const <ArchiveItem>[
      ArchiveItem(identifier: 'item1', title: 'Concierto de prueba', creator: 'Alguien'),
    ];
  }

  @override
  Future<List<AudioCandidate>> files(String identifier) async {
    return const <AudioCandidate>[
      AudioCandidate(
        url: 'https://example.org/a.mp3',
        name: 'a.mp3',
        format: 'VBR MP3',
        size: 2048,
      ),
    ];
  }

  @override
  Future<File?> download(
    AudioCandidate candidate, {
    void Function(DownloadProgress progress)? onProgress,
    String? directory,
    String? fileName,
    bool overwrite = false,
  }) async {
    onProgress?.call(const DownloadProgress(received: 2048, total: 2048));
    return File('${Directory.systemTemp.path}/a.mp3');
  }
}

void main() {
  group('PlaylistStore', () {
    test('crear, renombrar, duplicar y borrar', () {
      final store = PlaylistStore.memory();
      final one = store.create('Favoritas', paths: <String>['/m/a.mp3']);
      expect(store.length, 1);
      expect(one.length, 1);

      expect(store.rename(one.id, 'Otras'), isTrue);
      expect(store.byId(one.id)!.name, 'Otras');

      final copy = store.duplicate(one.id);
      expect(copy, isNotNull);
      expect(copy!.name, 'Otras (copia)');
      expect(store.length, 2);
      expect(copy.paths, <String>['/m/a.mp3']);

      expect(store.delete(one.id), isTrue);
      expect(store.length, 1);
      expect(store.byId(one.id), isNull);

      // Un nombre vacío no rompe nada: se autogenera.
      final auto = store.create('  ');
      expect(auto.name, isNotEmpty);
    });

    test('añadir sin duplicados, quitar y reordenar', () {
      final store = PlaylistStore.memory();
      final list = store.create('Lista', paths: <String>['/a', '/b']);
      expect(store.addPaths(list.id, <String>['/b', '/c', '']), isTrue);
      expect(store.byId(list.id)!.paths, <String>['/a', '/b', '/c']);
      // Repetir lo mismo no cambia nada.
      expect(store.addPaths(list.id, <String>['/c']), isFalse);

      expect(store.move(list.id, 2, 0), isTrue);
      expect(store.byId(list.id)!.paths, <String>['/c', '/a', '/b']);

      expect(store.removeAt(list.id, 1), isTrue);
      expect(store.byId(list.id)!.paths, <String>['/c', '/b']);
      expect(store.removeAt(list.id, 9), isFalse);
    });

    test('.m3u: parsear con rutas relativas y volver a escribir', () {
      const m3u = '#EXTM3U\n#EXTINF:-1,Primera\nPrimera.mp3\n'
          '#EXTINF:-1,Segunda\n/musica/Segunda.flac\n';
      final paths = PlaylistStore.parseM3u(m3u, baseDir: '/musica');
      expect(paths, <String>['/musica/Primera.mp3', '/musica/Segunda.flac']);

      final playlist = Playlist(id: 'x', name: 'X', paths: paths);
      final text = PlaylistStore.buildM3u(playlist);
      expect(text.startsWith('#EXTM3U\n'), isTrue);
      expect(text.contains('#EXTINF:-1,Primera'), isTrue);
      expect(PlaylistStore.parseM3u(text), paths);
    });

    test('.pls: solo las líneas FileN', () {
      const pls = '[playlist]\nFile1=/m/a.mp3\nTitle1=A\nFile2=/m/b.flac\n'
          'NumberOfEntries=2\n';
      expect(PlaylistStore.parsePls(pls), <String>['/m/a.mp3', '/m/b.flac']);
    });

    test('importa y exporta desde disco', () async {
      final dir = _tempDir('pl_io');
      final source = File('${dir.path}/lista.m3u')
        ..writeAsStringSync('#EXTM3U\nuno.mp3\ndos.mp3\n');
      final store = PlaylistStore.memory();
      final imported = await store.importFile(source);
      expect(imported, isNotNull);
      expect(imported!.name, 'lista');
      expect(imported.paths, <String>['${dir.path}/uno.mp3', '${dir.path}/dos.mp3']);

      final target = File('${dir.path}/salida.m3u8');
      final written = await store.exportPlaylist(imported, target);
      expect(written, isNotNull);
      expect(target.readAsStringSync(), contains('uno.mp3'));
      dir.deleteSync(recursive: true);
    });

    test('las listas inteligentes salen de las reproducciones y de lo añadido',
        () {
      final store = PlaylistStore.memory();
      final now = DateTime(2026, 11, 21, 10);
      store.remember(<String>['/nueva.mp3'], at: now);
      store.remember(<String>['/vieja.mp3'], at: DateTime(2026, 1, 4));
      final plays = <String, int>{'/mucho.mp3': 9, '/poco.mp3': 1, '/nueva.mp3': 2};

      final lists = store.smartLists(
        library: <String>['/mucho.mp3', '/poco.mp3', '/nueva.mp3', '/nunca.mp3'],
        plays: (path) => plays[path] ?? 0,
        now: now,
      );
      expect(lists.length, 3);
      final top = lists.first;
      expect(top.id, SmartList.top25.id);
      expect(top.paths.take(3), <String>['/mucho.mp3', '/nueva.mp3', '/poco.mp3']);

      final never = lists[1];
      expect(never.paths, <String>['/nunca.mp3', '/vieja.mp3'],
          reason: 'sin reproducciones, incluidas las vistas pero nunca puestas');

      final month = lists[2];
      expect(month.paths, <String>['/nueva.mp3']);
    });

    test('se guarda y se recupera del JSON', () async {
      final dir = _tempDir('pl_save');
      final file = File('${dir.path}/playlists.json');
      final store = PlaylistStore(file: file);
      store.create('Rock', paths: <String>['/m/r.mp3']);
      store.remember(<String>['/m/r.mp3'], at: DateTime(2026, 11, 2));
      await store.save();

      final again = PlaylistStore(file: file);
      await again.load();
      expect(again.length, 1);
      expect(again.playlists.first.name, 'Rock');
      expect(again.playlists.first.paths, <String>['/m/r.mp3']);
      // `seen` sobrevive: la lista del mes sigue viendo la pista.
      final month = again.smartLists(
        library: const <String>[],
        plays: (_) => 0,
        now: DateTime(2026, 11, 21),
      )[2];
      expect(month.paths, <String>['/m/r.mp3']);
      dir.deleteSync(recursive: true);
    });
  });

  group('MultiQueueStore', () {
    test('captura, cambia de cola y renombra', () {
      final queues = MultiQueueStore.memory();
      expect(queues.slots.length, 5);
      expect(queues.active, 0);

      expect(queues.capture(0, <String>['/a', '/b'], 1), isTrue);
      expect(queues.activeSlot.paths.length, 2);
      expect(queues.activeSlot.index, 1);
      // Lo mismo otra vez no ensucia ni notifica.
      expect(queues.capture(0, <String>['/a', '/b'], 1), isFalse);

      queues.setActive(2);
      expect(queues.active, 2);
      expect(queues.activeSlot.isEmpty, isTrue);
      expect(queues.hasStored, isTrue);

      expect(queues.rename(2, 'Trabajo'), isTrue);
      expect(queues.activeSlot.label, 'Trabajo');
      expect(queues.clear(0), isTrue);
      expect(queues.slots[0].isEmpty, isTrue);
    });

    test('se guarda en disco con el índice y la cola activa', () async {
      final dir = _tempDir('queues');
      final file = File('${dir.path}/queues.json');
      final queues = MultiQueueStore(file: file);
      queues.capture(1, <String>['/x.mp3'], 0);
      queues.setActive(1);
      await queues.save();

      final again = MultiQueueStore(file: file);
      await again.load();
      expect(again.active, 1);
      expect(again.slots[1].paths, <String>['/x.mp3']);
      dir.deleteSync(recursive: true);
    });
  });

  group('LongTrackMemory', () {
    test('solo recuerda pistas largas y posiciones útiles', () {
      final memory = LongTrackMemory.memory();
      expect(memory.remember('/corto.mp3', 120, 300), isFalse);
      expect(memory.remember('/largo.mp3', 10, 7200), isFalse);
      expect(memory.remember('/largo.mp3', 300, 7200), isTrue);
      expect(memory.positionFor('/largo.mp3'), 300);
      expect(memory.remember('/largo.mp3', 7190, 7200), isTrue);
      expect(memory.positionFor('/largo.mp3'), isNull,
          reason: 'casi al final se olvida');
      expect(LongTrackMemory.isLong(15 * 60), isTrue);
      expect(LongTrackMemory.isLong(899), isFalse);
    });
  });

  group('StatsStore', () {
    test('acumula reproducciones, artistas y franja horaria', () {
      final stats = StatsStore.memory();
      final at = DateTime(2026, 11, 21, 22, 15);
      stats.record(path: '/a.mp3', title: 'A', artist: 'Uno', seconds: 200, at: at);
      stats.record(path: '/a.mp3', title: 'A', artist: 'Uno', seconds: 200, at: at);
      stats.record(path: '/b.mp3', title: 'B', artist: 'Dos', seconds: 100, at: at);

      expect(stats.totalPlays, 3);
      expect(stats.totalSeconds, 500);
      expect(stats.playsOf('/a.mp3'), 2);
      expect(stats.playsOf('/desconocida'), 0);
      expect(stats.topTracks().first.path, '/a.mp3');
      expect(stats.topArtists().first.key, 'Uno');
      expect(stats.topArtists().first.value, 2);
      expect(stats.favoriteHour, 22);
      expect(stats.favoriteSlot, 'por la noche');
      expect(stats.history.length, 3);
      expect(stats.history.first.path, '/b.mp3');
      expect(stats.byHour[22], 3);
    });

    test('se guarda y se recupera, y `clear` deja todo a cero', () async {
      final dir = _tempDir('stats');
      final file = File('${dir.path}/stats.json');
      final stats = StatsStore(file: file);
      stats.record(path: '/a.mp3', title: 'A', artist: 'Uno', seconds: 60, at: DateTime(2026, 1, 2, 8));
      await stats.save();

      final again = StatsStore(file: file);
      await again.load();
      expect(again.totalPlays, 1);
      expect(again.playsOf('/a.mp3'), 1);
      expect(again.favoriteHour, 8);

      await again.clear();
      expect(again.totalPlays, 0);
      expect(again.history, isEmpty);
      expect(again.favoriteHour, -1);
      dir.deleteSync(recursive: true);
    });
  });

  group('Automix', () {
    test('el plan estira como mucho ±8 % y acepta el doble de pulso', () {
      final near = AutomixPlanner.plan(bpmA: 120, bpmB: 124);
      expect(near.tempo, closeTo(1.033, 0.001));
      expect(near.mixes, isTrue);

      final far = AutomixPlanner.plan(bpmA: 100, bpmB: 130);
      expect(far.tempo, closeTo(1.08, 0.0001));
      expect(far.describe(), contains('BPM'));

      final double1 = AutomixPlanner.plan(bpmA: 90, bpmB: 180);
      expect(double1.tempo, 1.0, reason: '180 es el doble de 90: mismo patrón');

      final none = AutomixPlanner.plan(bpmA: 0, bpmB: 120);
      expect(none.analysed, isFalse);
      expect(none.tempo, 1);
      expect(none.mixes, isFalse);
      expect(none.describe(), contains('Sin pulso'));
    });

    test('el motor ajusta el tempo al final y lo restaura al cambiar', () async {
      final fake = FakePlayer()
        ..hasTrack = true
        ..duration = 100
        ..queuePaths.addAll(<String>['/a.mp3', '/b.mp3'])
        ..queueIndexValue = 0;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.seek(96); // quedan 4 s: dentro del pre-roll

      final bpms = <String, double>{'/a.mp3': 120, '/b.mp3': 128};
      final engine = AutomixEngine(
        controller: controller,
        autoTick: false,
        probe: (path) async => bpms[path] ?? 0,
      );
      engine.setEnabled(true);
      engine.tick();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(engine.phase, AutomixPhase.blending);
      expect(fake.crossfadeCalls, greaterThan(0));
      expect(fake.speed, greaterThan(1.0));
      expect(fake.speed, lessThanOrEqualTo(1.08));
      expect(engine.status, contains('128'));

      // La pista siguiente entra: el tempo vuelve a 1.
      fake.queueIndexValue = 1;
      controller.pump();
      engine.tick();
      expect(fake.speed, 1);
      expect(engine.phase, AutomixPhase.idle);
      engine.dispose();
    });
  });

  group('AudioDownloader', () {
    test('parsea el buscador de Internet Archive', () {
      final items = AudioDownloader.parseSearch(<String, Object?>{
        'response': <String, Object?>{
          'docs': <Object?>[
            <String, Object?>{
              'identifier': 'item1',
              'title': 'Un concierto',
              'creator': <String>['Ana', 'Luis'],
              'year': '1927',
              'downloads': 40,
            },
            <String, Object?>{'title': 'sin identificador'},
          ],
        },
      });
      expect(items.length, 1);
      expect(items.first.identifier, 'item1');
      expect(items.first.creator, 'Ana, Luis');
      expect(items.first.subtitle, contains('1927'));
    });

    test('de los archivos solo quedan los de audio, FLAC primero', () {
      final files = AudioDownloader.parseFiles('item1', <String, Object?>{
        'files': <Object?>[
          <String, Object?>{'name': 'cover.jpg', 'format': 'JPEG'},
          <String, Object?>{'name': 'tema.mp3', 'format': 'VBR MP3', 'size': 1000},
          <String, Object?>{'name': 'tema.flac', 'format': 'Flac', 'size': 3000},
          <String, Object?>{'name': 'notas.txt', 'format': 'Text'},
        ],
      });
      expect(files.length, 2);
      expect(files.first.name, 'tema.flac');
      expect(files.first.url,
          'https://archive.org/download/item1/tema.flac');
      expect(files.first.sizeLabel, contains('KiB'));
    });

    test('el nombre se sanea para el sistema de archivos', () {
      expect(AudioDownloader.sanitize('a/b/c.mp3'), 'c.mp3');
      expect(AudioDownloader.sanitize('con:dos*malos?.mp3'), 'con_dos_malos_.mp3');
      expect(AudioDownloader.sanitize(''), 'descarga.mp3');
      final long = AudioDownloader.sanitize('${'x' * 400}.mp3');
      expect(long.length, lessThanOrEqualTo(180));
      expect(long.endsWith('.mp3'), isTrue);
    });

    test('descarga de verdad contra un servidor local, con progreso', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final payload = List<int>.generate(150000, (i) => i % 251);
      server.listen((request) {
        request.response.headers.contentLength = payload.length;
        request.response.add(payload);
        request.response.close();
      });

      final dir = _tempDir('download');
      final downloader = AudioDownloader(directory: dir.path);
      final fractions = <double>[];
      final candidate = AudioCandidate(
        url: 'http://127.0.0.1:${server.port}/tema.mp3',
        name: 'tema.mp3',
        format: 'MP3',
      );
      final file = await downloader.download(
        candidate,
        onProgress: (progress) {
          final fraction = progress.fraction;
          if (fraction != null) fractions.add(fraction);
        },
      );
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(file.lengthSync(), payload.length);
      expect(fractions, isNotEmpty);
      expect(fractions.last, closeTo(1, 0.01));

      // Un puerto cerrado devuelve null, no una excepción.
      final deadPort = server.port;
      downloader.close();
      await server.close(force: true);
      final second = AudioDownloader(directory: dir.path);
      final missing = await second.download(AudioCandidate(
        url: 'http://127.0.0.1:$deadPort/tema.mp3',
        name: 'otro.mp3',
        format: 'MP3',
      ));
      expect(missing, isNull);
      second.close();
      await server.close(force: true);
      dir.deleteSync(recursive: true);
    });
  });

  group('PlaylistsPage', () {
    testWidgets('crea una lista y la abre', (tester) async {
      final store = PlaylistStore.memory();
      store.create('Hecha', paths: <String>['/m/a.mp3']);
      final controller = PlayerController(FakePlayer());
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        PlaylistsPage(
          controller: controller,
          store: store,
          stats: StatsStore.memory(),
        ),
      ));
      await tester.pump();

      expect(find.text('Hecha'), findsOneWidget);
      expect(find.textContaining('Top 25'), findsOneWidget);

      await tester.tap(find.byTooltip('Nueva lista'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Nueva');
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('StatsPage', () {
    testWidgets('muestra totales y el top', (tester) async {
      final stats = StatsStore.memory()
        ..record(path: '/a.mp3', title: 'Canción A', artist: 'Grupo', seconds: 300)
        ..record(path: '/a.mp3', title: 'Canción A', artist: 'Grupo', seconds: 300);

      await tester.pumpWidget(_app(StatsPage(stats: stats)));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('Canción A'), findsWidgets);
      expect(find.textContaining('10 min'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('DownloaderPage', () {
    testWidgets('busca, lista archivos y descarga', (tester) async {
      final controller = PlayerController(FakePlayer());
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        DownloaderPage(controller: controller, downloader: _FakeDownloader()),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'concierto');
      await tester.tap(find.byTooltip('Buscar'));
      await tester.pumpAndSettle();
      expect(find.text('Concierto de prueba'), findsOneWidget);

      await tester.tap(find.text('Concierto de prueba'));
      await tester.pumpAndSettle();
      expect(find.text('a.mp3'), findsOneWidget);

      await tester.tap(find.byTooltip('Descargar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Guardado en'), findsOneWidget);
      expect(find.text('Añadir a la cola'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('QueueSheet', () {
    testWidgets('cambia entre las cinco colas', (tester) async {
      final fake = FakePlayer()
        ..hasTrack = true
        ..queuePaths.addAll(<String>['/a.mp3', '/b.mp3'])
        ..queueIndexValue = 0;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      final queues = MultiQueueStore.memory();
      final automix = AutomixEngine(controller: controller, autoTick: false);

      await tester.pumpWidget(_app(
        Scaffold(
          body: QueueSheet(controller: controller, queues: queues, automix: automix),
        ),
      ));
      await tester.pump();

      expect(find.text('Automix DJ'), findsOneWidget);
      expect(find.text('3 · 0'), findsOneWidget);

      await tester.tap(find.text('3 · 0'));
      await tester.pump();
      expect(queues.active, 2);
      expect(fake.clearCalls, greaterThan(0),
          reason: 'al cambiar de cola se vacía la que había');
      expect(find.textContaining('Cola 3'), findsOneWidget);

      // Lo que había en la cola 1 quedó guardado.
      expect(queues.slots[0].paths.length, 2);

      automix.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
