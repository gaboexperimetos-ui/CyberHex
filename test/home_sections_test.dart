import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/stats_store.dart';
import 'package:cyberhex/core/theme_controller.dart';
import 'package:cyberhex/ui/home_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

void main() {
  Widget mount(
    PlayerController controller,
    ThemeController theme,
    StatsStore stats,
  ) {
    return MaterialApp(
      theme: theme.themeData,
      home: HomePage(
        controller: controller,
        theme: theme,
        stats: stats,
        onOpenPlayer: () {},
        onOpenLibrary: () {},
        onOpenPlaylists: () {},
        onOpenRadio: () {},
        onOpenStats: () {},
      ),
    );
  }

  testWidgets('inicio muestra recientes y lo más escuchado', (tester) async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Ahora'
      ..artist = 'Alguien'
      ..queuePaths.add('/m/ahora.flac');
    fake.queueIndexValue = 0;
    final controller = PlayerController(fake);
    final theme = ThemeController();
    final stats = StatsStore.memory()
      ..record(
        path: '/m/otra.flac',
        title: 'Otra',
        artist: 'Banda',
        seconds: 200,
      )
      ..record(path: '/m/tercera.flac', title: 'Tercera', artist: 'Grupo')
      ..record(path: '/m/otra.flac', title: 'Otra', artist: 'Banda');
    addTearDown(controller.dispose);
    addTearDown(theme.dispose);
    addTearDown(stats.dispose);

    await tester.pumpWidget(mount(controller, theme, stats));
    await tester.pumpAndSettle();

    expect(find.text('Sigue escuchando'), findsOneWidget);
    expect(find.text('Otra'), findsWidgets);
    expect(find.text('Tercera'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Lo que más suena'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin historial las secciones no ocupan espacio', (tester) async {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    final theme = ThemeController();
    final stats = StatsStore.memory();
    addTearDown(controller.dispose);
    addTearDown(theme.dispose);
    addTearDown(stats.dispose);

    await tester.pumpWidget(mount(controller, theme, stats));
    await tester.pumpAndSettle();

    expect(find.text('Sigue escuchando'), findsNothing);
    expect(find.text('Lo que más suena'), findsNothing);
    expect(find.text('Explorar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
