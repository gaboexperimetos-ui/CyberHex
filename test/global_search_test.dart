import 'package:cyberhex/core/library_search.dart';
import 'package:cyberhex/core/player_api.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/stats_store.dart';
import 'package:cyberhex/core/text_search.dart';
import 'package:cyberhex/core/theme_controller.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/home_page.dart';
import 'package:cyberhex/ui/search_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

final List<LibraryTrack> _tracks = <LibraryTrack>[
  LibraryTrack.fromPath('/m/Radiohead/In Rainbows/15 Step.flac'),
  LibraryTrack.fromPath('/m/Radiohead/In Rainbows/Nude.flac'),
  LibraryTrack.fromPath('/m/Björk/Homogenic/Jóga.flac'),
];

void main() {
  group('normalizeForSearch', () {
    test('quita mayúsculas y tildes', () {
      expect(normalizeForSearch('Canción'), 'cancion');
      expect(normalizeForSearch('BJÖRK'), 'bjork');
      expect(normalizeForSearch('Niño'), 'nino');
      expect(normalizeForSearch(''), '');
    });
  });

  group('searchHits', () {
    test('encuentra por título, artista y álbum sin tildes', () {
      expect(
        searchHits(
          query: 'joga',
          library: _tracks,
          history: const <HistoryEntry>[],
        ).map((h) => h.title),
        <String>['Jóga'],
      );
      expect(
        searchHits(
          query: 'radiohead',
          library: _tracks,
          history: const <HistoryEntry>[],
        ).map((h) => h.title),
        containsAll(<String>['15 Step', 'Nude']),
      );
      expect(
        searchHits(
          query: 'in rainbows',
          library: _tracks,
          history: const <HistoryEntry>[],
        ).map((h) => h.title),
        containsAll(<String>['15 Step', 'Nude']),
      );
    });

    test('pone delante lo que viene del historial', () {
      final history = <HistoryEntry>[
        HistoryEntry(
          path: '/m/Björk/Homogenic/Jóga.flac',
          started: DateTime(2026, 11, 22),
          title: 'Jóga',
          artist: 'Björk',
        ),
      ];
      final hits = searchHits(query: 'o', library: _tracks, history: history);

      expect(hits.first.path, '/m/Björk/Homogenic/Jóga.flac');
      expect(hits.first.recent, isTrue);
      expect(hits.where((h) => h.recent), hasLength(1));
    });

    test('sin consulta devuelve lo reciente y luego la biblioteca', () {
      final history = <HistoryEntry>[
        HistoryEntry(
          path: '/m/Radiohead/In Rainbows/Nude.flac',
          started: DateTime(2026, 11, 22),
          title: 'Nude',
        ),
      ];
      final hits = searchHits(query: '  ', library: _tracks, history: history);

      expect(hits.first.title, 'Nude');
      expect(hits.map((h) => h.title), contains('Jóga'));
    });

    test('respeta el límite y no repite rutas', () {
      final history = <HistoryEntry>[
        HistoryEntry(
          path: '/m/Radiohead/In Rainbows/Nude.flac',
          started: DateTime(2026, 11, 22),
          title: 'Nude',
        ),
        HistoryEntry(
          path: '/m/Radiohead/In Rainbows/Nude.flac',
          started: DateTime(2026, 11, 21),
          title: 'Nude',
        ),
      ];
      final hits = searchHits(
        query: '',
        library: _tracks,
        history: history,
        limit: 2,
      );

      expect(hits, hasLength(2));
      expect(hits.where((h) => h.path.endsWith('Nude.flac')), hasLength(1));
    });
  });

  group('SearchSheet', () {
    Widget harness(PlayerController controller, StatsStore stats) {
      return MaterialApp(
        theme: buildCyberHexTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => SearchSheet.show(
                  context,
                  controller: controller,
                  stats: stats,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('lista los resultados y reproduce al tocar', (tester) async {
      final fake = FakePlayer()..library = _tracks;
      final controller = PlayerController(fake);
      await controller.scanDirectory('/m');
      final stats = StatsStore.memory()
        ..record(
          path: '/m/Björk/Homogenic/Jóga.flac',
          title: 'Jóga',
          artist: 'Björk',
        );
      addTearDown(controller.dispose);
      addTearDown(stats.dispose);

      await tester.pumpWidget(harness(controller, stats));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      // Con la consulta vacía ya se ve lo reciente.
      expect(find.text('Jóga'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nude');
      await tester.pumpAndSettle();
      expect(find.text('Nude'), findsOneWidget);
      expect(find.text('Jóga'), findsNothing);

      await tester.tap(find.text('Nude'));
      await tester.pumpAndSettle();

      expect(fake.loadedPaths, contains('/m/Radiohead/In Rainbows/Nude.flac'));
      expect(find.byType(TextField), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('avisa cuando no hay coincidencias', (tester) async {
      final fake = FakePlayer()..library = _tracks;
      final controller = PlayerController(fake);
      await controller.scanDirectory('/m');
      final stats = StatsStore.memory();
      addTearDown(controller.dispose);
      addTearDown(stats.dispose);

      await tester.pumpWidget(harness(controller, stats));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text('Sin resultados'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin biblioteca ni historial invita a escanear', (
      tester,
    ) async {
      final controller = PlayerController(FakePlayer());
      final stats = StatsStore.memory();
      addTearDown(controller.dispose);
      addTearDown(stats.dispose);

      await tester.pumpWidget(harness(controller, stats));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Nada que buscar todavía'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Inicio', () {
    Widget mount(PlayerController controller, StatsStore stats) {
      return MaterialApp(
        theme: buildCyberHexTheme(),
        home: HomePage(
          controller: controller,
          theme: ThemeController(),
          stats: stats,
          onOpenPlayer: () {},
          onOpenLibrary: () {},
          onOpenPlaylists: () {},
          onOpenRadio: () {},
          onOpenStats: () {},
          onOpenAlbum: (_) {},
        ),
      );
    }

    testWidgets('la lupa de la cabecera abre la búsqueda global', (
      tester,
    ) async {
      final controller = PlayerController(FakePlayer()..library = _tracks);
      await controller.scanDirectory('/m');
      final stats = StatsStore.memory();
      addTearDown(controller.dispose);
      addTearDown(stats.dispose);

      await tester.pumpWidget(mount(controller, stats));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Buscar (Ctrl+F)'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Ctrl+F también abre la búsqueda', (tester) async {
      final controller = PlayerController(FakePlayer()..library = _tracks);
      await controller.scanDirectory('/m');
      final stats = StatsStore.memory();
      addTearDown(controller.dispose);
      addTearDown(stats.dispose);

      await tester.pumpWidget(mount(controller, stats));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
