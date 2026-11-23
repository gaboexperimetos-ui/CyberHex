import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/theme_controller.dart';
import 'package:cyberhex/ui/home_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

void main() {
  testWidgets('el armazón arranca en Inicio y cambia de pestaña',
      (tester) async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Canción'
      ..artist = 'Artista';
    final controller = PlayerController(fake);
    final theme = ThemeController();
    addTearDown(controller.dispose);
    addTearDown(theme.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: theme.themeData,
      home: HomeShell(controller: controller, theme: theme),
    ));
    await tester.pumpAndSettle();

    expect(find.text('CYBERHEX'), findsOneWidget);
    expect(find.text('Explorar'), findsOneWidget);

    int? index() => tester.widget<IndexedStack>(find.byType(IndexedStack)).index;

    expect(index(), 0);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Listas'),
      ),
    );
    await tester.pumpAndSettle();
    expect(index(), 2);

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
}
