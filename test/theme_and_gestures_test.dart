import 'dart:io';
import 'dart:typed_data';

import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/theme_controller.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/mini_player.dart';
import 'package:cyberhex/ui/player_page.dart';
import 'package:cyberhex/ui/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? buildCyberHexThemed(CyberHexPalette.neon),
  home: child,
);

/// 4 píxeles RGBA (2×2) del color indicado, como los devuelve `rawRgba`.
Uint8List _pixels(int r, int g, int b, {int count = 4, int alpha = 255}) {
  final out = Uint8List(count * 4);
  for (var i = 0; i < count; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = alpha;
  }
  return out;
}

void main() {
  group('CyberHexPalette', () {
    test('hay cinco temas, con nombre y brillo', () {
      expect(CyberHexThemeId.values.length, 5);
      expect(CyberHexThemeId.neon.label, 'CyberHex Neon');
      expect(CyberHexThemeId.amoled.label, 'AMOLED Negro Puro');
      expect(CyberHexThemeId.cyberpunk.label, 'Cyberpunk');
      expect(
        CyberHexPalette.of(CyberHexThemeId.light).brightness,
        Brightness.light,
      );
      expect(
        CyberHexPalette.of(CyberHexThemeId.cyberpunk).accent,
        const Color(0xFFF472B6),
      );
      expect(
        CyberHexPalette.of(CyberHexThemeId.amoled).background,
        const Color(0xFF000000),
      );
      expect(CyberHexThemeId.fromName('cyberpunk'), CyberHexThemeId.cyberpunk);
      expect(
        CyberHexThemeId.fromName('materialYou'),
        CyberHexThemeId.materialYou,
      );
      expect(CyberHexThemeId.fromName('no-existe'), CyberHexThemeId.neon);
    });

    test('el tema de Material usa la paleta y expone la extensión', () {
      final light = buildCyberHexThemed(CyberHexPalette.light);
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, CyberHexPalette.light.background);
      expect(light.colorScheme.primary, CyberHexPalette.light.accent);
      expect(light.extension<CyberHexPalette>(), CyberHexPalette.light);
      // El constructor de siempre sigue funcionando (compatibilidad).
      expect(buildCyberHexTheme().brightness, Brightness.dark);
    });

    test('un acento nuevo se aclara u oscurece para que se lea', () {
      final lighter = CyberHexPalette.neon.withAccent(const Color(0xFF101010));
      expect(
        lighter.accent,
        isNot(const Color(0xFF101010)),
        reason: 'se ajusta el brillo para que contraste',
      );
      expect(lighter.accent.computeLuminance(), greaterThan(0.2));
    });
  });

  group('ThemeController', () {
    test('arranca en neón, cambia de tema y cicla', () {
      final theme = ThemeController.memory();
      expect(theme.themeId, CyberHexThemeId.neon);
      expect(theme.palette.id, CyberHexThemeId.neon);

      theme.setTheme(CyberHexThemeId.amoled);
      expect(theme.palette.id, CyberHexThemeId.amoled);
      expect(theme.themeData.scaffoldBackgroundColor, const Color(0xFF000000));

      theme.cycleTheme();
      expect(theme.themeId, CyberHexThemeId.light);
      theme.cycleTheme();
      theme.cycleTheme();
      theme.cycleTheme();
      expect(theme.themeId, CyberHexThemeId.neon);
    });

    test('estilo de carátula, modo bolsillo y barra de acciones', () {
      final theme = ThemeController.memory();
      expect(theme.coverStyle, CoverStyle.spinningDisc);
      theme.setCoverStyle(CoverStyle.square);
      expect(theme.coverStyle, CoverStyle.square);
      expect(CoverStyle.fromName('fullBleed'), CoverStyle.fullBleed);

      theme.setPocketMode(true);
      expect(theme.pocketMode, isTrue);

      expect(theme.shows(PlayerAction.lyrics), isTrue);
      theme.toggleAction(PlayerAction.lyrics);
      expect(theme.shows(PlayerAction.lyrics), isFalse);
      theme.setActions(<PlayerAction>[PlayerAction.share]);
      expect(theme.actions, <PlayerAction>{PlayerAction.share});
      expect(PlayerAction.fromName('nada'), isNull);
    });

    test('el color dinámico sale de la carátula y se apaga', () async {
      final theme = ThemeController.memory();
      // Apagado por defecto: no toca la carátula.
      expect(await theme.updateCover(_pixels(20, 200, 60)), isNull);
      expect(theme.palette.accent, CyberHexPalette.neon.accent);

      theme.setDynamicColor(true);
      // Bytes que no son una imagen: cae en el acento de reserva, sin lanzar.
      final accent = await theme.updateCover(_pixels(200, 30, 30));
      expect(accent, isNotNull);
      expect(theme.palette.accent, isNot(CyberHexPalette.neon.accent));

      theme.setDynamicColor(false);
      expect(theme.palette.accent, CyberHexPalette.neon.accent);
    });

    test('el acento de los píxeles ignora grises y transparentes', () {
      final red = ThemeController.accentFromPixels(_pixels(220, 20, 20));
      expect(red, isNotNull);
      expect(red!.r, greaterThan(red.g));
      expect(red.g, lessThan(0.2));

      final gray = ThemeController.accentFromPixels(_pixels(120, 120, 120));
      expect(gray, isNull, reason: 'sin saturación no hay acento');

      final transparent = ThemeController.accentFromPixels(
        _pixels(220, 20, 20, alpha: 0),
      );
      expect(transparent, isNull);

      final mixed = BytesBuilder()
        ..add(_pixels(120, 120, 120))
        ..add(_pixels(20, 20, 220));
      final blue = ThemeController.accentFromPixels(mixed.takeBytes());
      expect(blue, isNotNull);
      expect(blue!.b, greaterThan(blue.r));
    });

    test('el acento de reserva es estable', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      expect(
        ThemeController.fallbackAccent(bytes),
        ThemeController.fallbackAccent(bytes),
      );
      expect(
        ThemeController.fallbackAccent(bytes),
        isNot(
          ThemeController.fallbackAccent(Uint8List.fromList(<int>[9, 9, 9])),
        ),
      );
    });

    test('los ajustes se guardan y se recuperan', () async {
      final dir = Directory('${Directory.systemTemp.path}/cyberhex6_theme');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      final file = File('${dir.path}/theme.json');

      final first = ThemeController(file: file);
      first.setTheme(CyberHexThemeId.materialYou);
      first.setCoverStyle(CoverStyle.rounded);
      first.setPocketMode(true);
      first.setDynamicColor(true);
      first.setActions(<PlayerAction>[PlayerAction.tags, PlayerAction.lab]);
      await first.save();

      final second = ThemeController(file: file);
      await second.load();
      expect(second.themeId, CyberHexThemeId.materialYou);
      expect(second.coverStyle, CoverStyle.rounded);
      expect(second.pocketMode, isTrue);
      expect(second.dynamicColor, isTrue);
      expect(second.actions, <PlayerAction>{
        PlayerAction.tags,
        PlayerAction.lab,
      });
      dir.deleteSync(recursive: true);
    });
  });

  group('PlayerPage: gestos', () {
    Future<(FakePlayer, PlayerController, ThemeController)> pumpPlayer(
      WidgetTester tester, {
      double position = 30,
    }) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Tema'
        ..artist = 'Grupo'
        ..duration = 200;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();
      controller.seek(position);
      final theme = ThemeController.memory();
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        _app(
          PlayerPage(controller: controller, theme: theme),
          theme: theme.themeData,
        ),
      );
      await tester.pump();
      return (fake, controller, theme);
    }

    Future<void> doubleTapAt(WidgetTester tester, Offset offset) async {
      await tester.tapAt(offset);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(offset);
      await tester.pump(const Duration(milliseconds: 320));
    }

    testWidgets('doble toque a la izquierda retrocede 10 s', (tester) async {
      final (fake, controller, _) = await pumpPlayer(tester);
      // En vertical no hay dos paneles: una sola columna.
      expect(find.byKey(const ValueKey<String>('player-panes')), findsNothing);
      await doubleTapAt(tester, const Offset(60, 300));
      expect(fake.position, 20);
      expect(controller.position.value, 20);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('doble toque a la derecha avanza 10 s', (tester) async {
      final (fake, _, _) = await pumpPlayer(tester);
      await doubleTapAt(tester, const Offset(340, 300));
      expect(fake.position, 40);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('doble toque en el centro reproduce o pausa', (tester) async {
      final (fake, controller, _) = await pumpPlayer(tester);
      expect(fake.isPlaying, isFalse);
      await doubleTapAt(tester, const Offset(200, 300));
      expect(fake.isPlaying, isTrue);
      expect(controller.snapshot.playing, isTrue);
      await doubleTapAt(tester, const Offset(200, 300));
      expect(fake.isPlaying, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('el arrastre vertical en la barra hace búsqueda fina', (
      tester,
    ) async {
      final (fake, _, _) = await pumpPlayer(tester, position: 30);
      // 100 px hacia arriba = 5 s (1 px = 50 ms).
      await tester.drag(find.byType(Slider).first, const Offset(0, -100));
      await tester.pump();
      // El gesto pierde el primer tramo (el umbral de arrastre de la barra),
      // así que se comprueba el sentido y no el valor exacto.
      expect(fake.position, closeTo(35, 1.5));
      expect(fake.position, greaterThan(30));
      await tester.pumpWidget(const SizedBox());
      // El temporizador de guardado que arranca al mover la posición se apaga
      // aquí: si no, la prueba acaba con un `Timer` pendiente.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('el modo bolsillo bloquea y se sale con pulsación larga', (
      tester,
    ) async {
      final (fake, _, theme) = await pumpPlayer(tester);
      await tester.tap(find.byTooltip('Modo bolsillo'));
      // La página entera escucha el doble toque, así que el toque simple se
      // resuelve cuando vence esa ventana: hay que dejar pasar el reloj.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      // El bloqueo es un ajuste del tema: si no se enciende, el botón no llegó.
      expect(
        theme.pocketMode,
        isTrue,
        reason: 'el botón no llegó a encenderlo',
      );
      expect(find.text('Mantén pulsado para salir'), findsOneWidget);

      // Con el bloqueo puesto, el doble toque no hace nada.
      await doubleTapAt(tester, const Offset(200, 300));
      expect(fake.isPlaying, isFalse);

      await tester.longPress(find.text('Modo bolsillo'));
      await tester.pumpAndSettle();
      expect(find.text('Mantén pulsado para salir'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(
        const Duration(seconds: 3),
      ); // suelta los temporizadores
    });

    testWidgets('los cuatro estilos de carátula se pintan sin errores', (
      tester,
    ) async {
      final (_, _, theme) = await pumpPlayer(tester);
      for (final style in CoverStyle.values) {
        theme.setCoverStyle(style);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'estilo ${style.name}');
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('en pantalla ancha se usa el diseño de dos paneles', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'Tema';
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();
      final theme = ThemeController.memory();
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        _app(
          PlayerPage(controller: controller, theme: theme),
          theme: theme.themeData,
        ),
      );
      await tester.pump();

      // En dos paneles la carátula y los controles están lado a lado.
      expect(
        find.byKey(const ValueKey<String>('player-panes')),
        findsOneWidget,
      );
      final cover = tester.getRect(
        find.byKey(const ValueKey<String>('player-cover')),
      );
      final title = tester.getRect(find.text('Tema'));
      expect(cover.center.dx, lessThan(title.center.dx));
      expect(find.text('CYBERHEX'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('MiniPlayer', () {
    testWidgets('muestra la pista y controla la reproducción', (tester) async {
      final fake = FakePlayer()
        ..hasTrack = true
        ..title = 'En la biblioteca'
        ..artist = 'Grupo';
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();
      var opened = 0;

      await tester.pumpWidget(
        _app(
          Scaffold(
            body: MiniPlayer(controller: controller, onOpen: () => opened += 1),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('En la biblioteca'), findsOneWidget);
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pump();
      expect(fake.isPlaying, isTrue);

      await tester.tap(find.text('En la biblioteca'));
      expect(opened, 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin pista no ocupa sitio', (tester) async {
      final controller = PlayerController(FakePlayer());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: MiniPlayer(controller: controller, onOpen: () {}),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('SettingsPage', () {
    testWidgets('cambia el tema, el bolsillo y la barra de acciones', (
      tester,
    ) async {
      final theme = ThemeController.memory();
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        _app(SettingsPage(theme: theme), theme: theme.themeData),
      );
      await tester.pump();

      await tester.tap(find.text('AMOLED Negro Puro'));
      await tester.pump();
      expect(theme.themeId, CyberHexThemeId.amoled);

      await tester.tap(find.text('Modo bolsillo'));
      await tester.pump();
      expect(theme.pocketMode, isTrue);

      await tester.tap(find.text('Letras'));
      await tester.pump();
      expect(theme.shows(PlayerAction.lyrics), isFalse);

      await tester.tap(find.text('Cuadrada'));
      await tester.pump();
      expect(theme.coverStyle, CoverStyle.square);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
