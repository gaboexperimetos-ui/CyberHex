import 'dart:io';

import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/theme_controller.dart';
import 'package:cyberhex/platform/media_session_channel.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/settings_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeController: ajustes de la capa Android', () {
    test('por defecto: sin auto-play y con tres botones', () {
      final theme = ThemeController.memory();
      expect(theme.autoPlayOnConnect, isFalse);
      expect(theme.mediaActions, <MediaAction>[
        MediaAction.previous,
        MediaAction.toggle,
        MediaAction.next,
      ]);
    });

    test('play-pausa no se puede quitar y el orden es el del enum', () {
      final theme = ThemeController.memory();
      theme.toggleMediaAction(MediaAction.toggle);
      expect(theme.mediaActions, contains(MediaAction.toggle));

      theme.toggleMediaAction(MediaAction.stop);
      theme.toggleMediaAction(MediaAction.previous);
      expect(theme.mediaActions, <MediaAction>[
        MediaAction.toggle,
        MediaAction.next,
        MediaAction.stop,
      ]);

      theme.setMediaActions(<MediaAction>[MediaAction.stop]);
      expect(theme.mediaActions, <MediaAction>[MediaAction.toggle, MediaAction.stop]);
    });

    test('auto-play y botones sobreviven al guardado', () async {
      final dir = Directory('${Directory.systemTemp.path}/cyberhex7_media');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      final file = File('${dir.path}/theme.json');

      final first = ThemeController(file: file);
      first.setAutoPlayOnConnect(true);
      first.setMediaActions(<MediaAction>[MediaAction.next, MediaAction.stop]);
      await first.save();

      final second = ThemeController(file: file);
      await second.load();
      expect(second.autoPlayOnConnect, isTrue);
      expect(second.mediaActions, <MediaAction>[
        MediaAction.toggle,
        MediaAction.next,
        MediaAction.stop,
      ]);
      dir.deleteSync(recursive: true);
    });

    test('un JSON sin los campos nuevos no rompe los ajustes', () async {
      final dir = Directory('${Directory.systemTemp.path}/cyberhex7_old');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      final file = File('${dir.path}/theme.json')
        ..writeAsStringSync('{"version":1,"theme":"light","actions":["tags"]}');

      final theme = ThemeController(file: file);
      await theme.load();
      expect(theme.themeId, CyberHexThemeId.light);
      expect(theme.autoPlayOnConnect, isFalse);
      expect(theme.mediaActions, <MediaAction>[MediaAction.toggle]);
      dir.deleteSync(recursive: true);
    });
  });

  group('MediaSessionChannel: configure', () {
    const channel = MethodChannel(MediaSessionChannel.channelName);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> outgoing;

    setUp(() {
      outgoing = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        outgoing.add(call);
        return true;
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('manda auto-play y la lista de botones', () async {
      final controller = PlayerController(FakePlayer());
      addTearDown(controller.dispose);
      final bridge = MediaSessionChannel(controller);
      addTearDown(bridge.dispose);
      await pumpEventQueue();

      bridge.updateMediaSettings(
        autoPlayOnConnect: true,
        notificationActions: <String>['previous', 'toggle', 'stop'],
      );
      await pumpEventQueue();

      final calls = outgoing.where((call) => call.method == 'configure').toList();
      expect(calls, hasLength(1));
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['autoPlayOnConnect'], isTrue);
      expect(args['notificationActions'], <String>['previous', 'toggle', 'stop']);
    });
  });

  group('SettingsPage: notificación', () {
    testWidgets('cambia el auto-play y los botones de la notificación',
        (tester) async {
      final theme = ThemeController.memory();
      addTearDown(theme.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: buildCyberHexThemed(CyberHexPalette.neon),
        home: SettingsPage(theme: theme),
      ));
      await tester.pump();

      // La página es un `ListView`: la sección no existe hasta bajar.
      await tester.scrollUntilVisible(
        find.text('NOTIFICACIÓN Y AURICULARES'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('NOTIFICACIÓN Y AURICULARES'), findsOneWidget);

      await tester.tap(find.text('Auto-play al conectar'));
      await tester.pump();
      expect(theme.autoPlayOnConnect, isTrue);

      await tester.tap(find.text('Cerrar'));
      await tester.pump();
      expect(theme.mediaActions, contains(MediaAction.stop));

      // Play/pausa está siempre y no se puede desmarcar.
      await tester.tap(find.text('Reproducir / pausa'));
      await tester.pump();
      expect(theme.mediaActions, contains(MediaAction.toggle));

      await tester.pumpWidget(const SizedBox());
    });
  });
}
