import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/player_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

void main() {
  testWidgets('la navegación se adapta a celular y escritorio', (tester) async {
    final controller = PlayerController(FakePlayer());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: PlayerPage(controller: controller),
      ),
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.pumpWidget(const SizedBox());

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: PlayerPage(controller: controller),
      ),
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('muestra la forma de onda de la pista actual', (tester) async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Canción'
      ..waveformPeaksValue = const [0.2, 0.8, 0.5];
    fake.queue.add('/music/cancion.flac');
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.pump();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: PlayerPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_WaveformPainter',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin pista muestra la bienvenida y el botón de abrir', (
    tester,
  ) async {
    final controller = PlayerController(FakePlayer());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: PlayerPage(controller: controller),
      ),
    );

    expect(find.text('Tu música, en tu máquina'), findsOneWidget);
    expect(find.text('Abrir audio'), findsOneWidget);
    expect(find.text('CYBERHEX'), findsOneWidget);
    // Desmonta la página antes del tearDown: así se libera el ticker del disco.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con pista muestra título, artista, álbum y duración', (
    tester,
  ) async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Canción'
      ..artist = 'Artista'
      ..album = 'Álbum'
      ..duration = 185;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.pump();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: PlayerPage(controller: controller),
      ),
    );

    expect(find.text('Canción'), findsWidgets);
    expect(find.text('Artista · Álbum'), findsOneWidget);
    expect(find.text('3:05 · motor nativo 48 kHz'), findsOneWidget);
    // Desmonta la página antes del tearDown: así se libera el ticker del disco.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la cola muestra las pistas y salta a la elegida', (
    tester,
  ) async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Canción';
    fake.queue.addAll(['/musica/uno.flac', '/musica/dos.mp3']);
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.pump();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: PlayerPage(controller: controller),
      ),
    );

    final queueDestination = find.widgetWithText(NavigationDestination, 'Cola');
    await tester.ensureVisible(queueDestination);
    await tester.tap(queueDestination);
    await tester.pumpAndSettle();

    expect(find.text('uno'), findsOneWidget);
    expect(find.text('dos'), findsOneWidget);

    await tester.tap(find.text('dos'));
    await tester.pumpAndSettle();
    expect(fake.queueIndex, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('los ajustes activan mono en el motor', (tester) async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Canción';
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.pump();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: PlayerPage(controller: controller),
      ),
    );

    final settingsDestination = find.widgetWithText(
      NavigationDestination,
      'Ajustes',
    );
    await tester.ensureVisible(settingsDestination);
    await tester.tap(settingsDestination);
    await tester.pumpAndSettle();

    expect(find.text('Velocidad'), findsOneWidget);
    await tester.tap(find.text('Mono'));
    await tester.pumpAndSettle();
    expect(fake.mono, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el icono cambia a pausa cuando el motor reproduce', (
    tester,
  ) async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Canción';
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.pump();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: PlayerPage(controller: controller),
      ),
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);

    controller.play();
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsWidgets);
    // Desmonta la página antes del tearDown: así se libera el ticker del disco.
    await tester.pumpWidget(const SizedBox());
  });
}
