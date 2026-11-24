import 'package:cyberhex/core/home_tab_store.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/scrobbler.dart';
import 'package:cyberhex/core/theme_controller.dart';
import 'package:cyberhex/ui/home_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

void main() {
  testWidgets(
    'cruzar el umbral de ventana ancha no recrea las páginas ni destruye el '
    'Scrobbler compartido',
    (tester) async {
      final controller = PlayerController(FakePlayer()..hasTrack = true);
      final theme = ThemeController.memory();
      final tabs = HomeTabStore.memory()..setTab(3);
      final scrobbler = Scrobbler.memory(controller);
      ScrobblerHost.attach(scrobbler);
      addTearDown(() {
        ScrobblerHost.attach(null);
        scrobbler.dispose();
        controller.dispose();
        theme.dispose();
        tabs.dispose();
      });
      controller.pump();

      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme.themeData,
          home: HomeShell(controller: controller, theme: theme, tabs: tabs),
        ),
      );
      await tester.pump();

      // Antes: el árbol se rehacía al pasar a barra lateral y una
      // `SettingsPage` destruía el Scrobbler que la otra seguía escuchando.
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pump();
      expect(find.byType(NavigationRail), findsOneWidget);

      tester.view.physicalSize = const Size(700, 900);
      await tester.pump();
      expect(find.byType(NavigationRail), findsNothing);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
