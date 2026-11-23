import 'package:cyberhex/core/home_tab_store.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/theme_controller.dart';
import 'package:cyberhex/ui/home_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

void main() {
  testWidgets('el armazón arranca en Inicio y cambia de pestaña', (
    tester,
  ) async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Canción'
      ..artist = 'Artista';
    final controller = PlayerController(fake);
    final theme = ThemeController();
    final tabs = HomeTabStore.memory();
    addTearDown(controller.dispose);
    addTearDown(theme.dispose);
    addTearDown(tabs.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.themeData,
        home: HomeShell(controller: controller, theme: theme, tabs: tabs),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tu música, tu máquina'), findsOneWidget);
    expect(find.text('Explorar'), findsOneWidget);

    int? index() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index;

    expect(index(), 0);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Listas'),
      ),
    );
    await tester.pumpAndSettle();
    expect(index(), 2);
    expect(tabs.tab, 2);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Ajustes'),
      ),
    );
    await tester.pumpAndSettle();
    expect(index(), 3);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Inicio'),
      ),
    );
    await tester.pumpAndSettle();
    expect(index(), 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('restaura la pestaña guardada de la sesión anterior', (
    tester,
  ) async {
    final controller = PlayerController(FakePlayer());
    final theme = ThemeController();
    final tabs = HomeTabStore.memory()..setTab(2);
    addTearDown(controller.dispose);
    addTearDown(theme.dispose);
    addTearDown(tabs.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.themeData,
        home: HomeShell(controller: controller, theme: theme, tabs: tabs),
      ),
    );
    await tester.pumpAndSettle();

    final index = tester.widget<IndexedStack>(find.byType(IndexedStack)).index;
    expect(index, 2);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en ventana ancha la navegación pasa a barra lateral', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Canción'
      ..artist = 'Artista';
    final controller = PlayerController(fake);
    final theme = ThemeController();
    final tabs = HomeTabStore.memory();
    addTearDown(controller.dispose);
    addTearDown(theme.dispose);
    addTearDown(tabs.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme.themeData,
        home: HomeShell(controller: controller, theme: theme, tabs: tabs),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    int? index() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index;
    expect(index(), 0);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Biblioteca'),
      ),
    );
    await tester.pumpAndSettle();
    expect(index(), 1);
    expect(tabs.tab, 1);

    await tester.pumpWidget(const SizedBox());
  });
}
