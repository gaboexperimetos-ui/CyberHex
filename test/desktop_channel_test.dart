import 'dart:async';

import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/theme_controller.dart';
import 'package:cyberhex/platform/desktop_channel.dart';
import 'package:cyberhex/ui/player_page.dart';
import 'package:cyberhex/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

/// Tests del puente de escritorio (`cyberhex/desktop`) y de los atajos de
/// teclado del reproductor. El canal se simula: no hace falta Linux, GTK ni
/// D-Bus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
  const channel = MethodChannel(DesktopChannel.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

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

  List<MethodCall> callsTo(String method) =>
      outgoing.where((MethodCall call) => call.method == method).toList();

  /// Simula un mensaje del runner GTK hacia Dart.
  Future<void> fromPlatform(String method, [Object? arguments]) async {
    await messenger.handlePlatformMessage(
      DesktopChannel.channelName,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (ByteData? _) {},
    );
  }

  FakePlayer playerWithTrack() {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Uno'
      ..artist = 'Artista'
      ..album = 'Álbum'
      ..duration = 120;
    return fake;
  }

  group('DesktopChannel: hacia MPRIS', () {
    test('manda metadatos al conectar, en microsegundos', () async {
      final controller = PlayerController(playerWithTrack());
      addTearDown(controller.dispose);
      controller.pump();

      final bridge = DesktopChannel(controller);
      addTearDown(bridge.dispose);
      await pumpEventQueue();

      final calls = callsTo('updateMetadata');
      expect(calls, hasLength(1));
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Uno');
      expect(args['artist'], 'Artista');
      expect(args['album'], 'Álbum');
      expect(args['durationMicros'], 120000000);
      expect(args['hasTrack'], isTrue);
    });

    test('updateState lleva estado, repetición, aleatorio y volumen', () async {
      final controller = PlayerController(playerWithTrack());
      addTearDown(controller.dispose);
      controller.pump();

      final bridge = DesktopChannel(controller);
      addTearDown(bridge.dispose);
      await pumpEventQueue();

      controller.play();
      controller.setRepeatMode(1);
      await pumpEventQueue();

      final calls = callsTo('updateState');
      expect(calls, isNotEmpty);
      final args = calls.last.arguments as Map<Object?, Object?>;
      expect(args['playing'], isTrue);
      expect(args['loop'], 'Playlist');
      expect(args['shuffle'], isFalse);
      expect(args['volume'], isA<double>());
      expect(args['positionMicros'], isA<int>());
    });

    test('la posición se limita a un segundo entero', () async {
      final controller = PlayerController(playerWithTrack());
      addTearDown(controller.dispose);
      controller.pump();

      final bridge = DesktopChannel(controller);
      addTearDown(bridge.dispose);
      await pumpEventQueue();
      outgoing.clear();

      controller.seek(1.2);
      await pumpEventQueue();
      controller.seek(1.8);
      await pumpEventQueue();
      // Mismo segundo entero: no cruza el canal otra vez.
      expect(callsTo('updateState'), hasLength(1));

      controller.seek(2.4);
      await pumpEventQueue();
      expect(callsTo('updateState'), hasLength(2));
    });

    test('setAlwaysOnTop, notifyTrack y notifySeek van al runner', () async {
      final controller = PlayerController(playerWithTrack());
      addTearDown(controller.dispose);
      final bridge = DesktopChannel(controller);
      addTearDown(bridge.dispose);
      await pumpEventQueue();
      outgoing.clear();

      await bridge.setAlwaysOnTop(true);
      await bridge.notifyTrack(title: 'Tema', body: 'Grupo');
      await bridge.notifySeek(42.5);

      expect(callsTo('setAlwaysOnTop').single.arguments, isTrue);
      final notify = callsTo('notifyTrack').single.arguments
          as Map<Object?, Object?>;
      expect(notify['title'], 'Tema');
      expect(notify['body'], 'Grupo');
      final seek = callsTo('notifySeek').single.arguments
          as Map<Object?, Object?>;
      expect(seek['positionMicros'], 42500000);
    });
  });

  group('DesktopChannel: desde MPRIS', () {
    test('transporte y volumen llegan al controlador', () async {
      final fake = playerWithTrack();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();
      final bridge = DesktopChannel(controller);
      addTearDown(bridge.dispose);
      await pumpEventQueue();

      await fromPlatform('play');
      expect(fake.isPlaying, isTrue);
      await fromPlatform('toggle');
      expect(fake.isPlaying, isFalse);
      await fromPlatform('next');
      await fromPlatform('previous');
      await fromPlatform('setVolume', 0.25);
      expect(controller.snapshot.volume, closeTo(0.25, 1e-9));
      await pumpEventQueue();
    });

    test('seek absoluto, relativo y topes de duración', () async {
      final fake = playerWithTrack();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();
      final bridge = DesktopChannel(controller);
      addTearDown(bridge.dispose);
      await pumpEventQueue();

      await fromPlatform('seek', 30);
      expect(fake.position, 30);
      await fromPlatform('seekRelative', 15);
      expect(fake.position, 45);
      // Nunca fuera de la pista.
      await fromPlatform('seekRelative', -100);
      expect(fake.position, 0);
      await fromPlatform('seek', 100000);
      expect(fake.position, 120);
      await pumpEventQueue();
    });

    test('repetición y aleatorio', () async {
      final fake = playerWithTrack();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();
      final bridge = DesktopChannel(controller);
      addTearDown(bridge.dispose);
      await pumpEventQueue();

      await fromPlatform('setLoop', 'Track');
      await pumpEventQueue();
      expect(controller.snapshot.repeatMode, 2);
      await fromPlatform('setLoop', 'Playlist');
      await pumpEventQueue();
      expect(controller.snapshot.repeatMode, 1);
      await fromPlatform('setLoop', 'None');
      await pumpEventQueue();
      expect(controller.snapshot.repeatMode, 0);

      await fromPlatform('setShuffle', true);
      await pumpEventQueue();
      expect(controller.snapshot.shuffle, isTrue);
    });

    test('onDropPaths alimenta el flujo de rutas soltadas', () async {
      final controller = PlayerController(playerWithTrack());
      addTearDown(controller.dispose);
      final bridge = DesktopChannel(controller);
      addTearDown(bridge.dispose);
      await pumpEventQueue();

      final received = <List<String>>[];
      final subscription = bridge.drops.listen(received.add);
      addTearDown(subscription.cancel);

      await fromPlatform('onDropPaths', <String>['/música/a.flac', '/música']);
      await pumpEventQueue();
      await fromPlatform('onDropPaths', <Object?>[]);
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single, <String>['/música/a.flac', '/música']);
    });

    test('sin runner al otro lado no lanza', () async {
      messenger.setMockMethodCallHandler(channel, null);
      final controller = PlayerController(playerWithTrack());
      addTearDown(controller.dispose);
      final bridge = DesktopChannel(controller);
      addTearDown(bridge.dispose);

      await bridge.setAlwaysOnTop(false);
      await bridge.notifyTrack(title: 'Sin escritorio');
      await pumpEventQueue();
    });
  });

  group('PlayerPage: atajos de teclado', () {
    Future<(FakePlayer, PlayerController)> pumpPage(WidgetTester tester) async {
      final fake = playerWithTrack();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      controller.pump();
      controller.seek(30);
      final theme = ThemeController.memory();
      addTearDown(theme.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: buildCyberHexThemed(CyberHexPalette.neon),
        home: PlayerPage(controller: controller, theme: theme),
      ));
      await tester.pump();
      return (fake, controller);
    }

    testWidgets('espacio, flechas y desplazamientos', (tester) async {
      final (fake, controller) = await pumpPage(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.isPlaying, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(fake.position, 35);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(fake.position, 30);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(controller.snapshot.hasTrack, isTrue);

      controller.setVolume(0.5);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(controller.snapshot.volume, closeTo(0.55, 1e-9));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.snapshot.volume, closeTo(0.5, 1e-9));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('M silencia y restaura, L repite y S aleatorio', (tester) async {
      final (fake, controller) = await pumpPage(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(controller.snapshot.volume, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(controller.snapshot.volume, closeTo(1.0, 1e-9));

      final before = controller.snapshot.repeatMode;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      expect(controller.snapshot.repeatMode, isNot(before));

      final shuffle = controller.snapshot.shuffle;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pump();
      expect(controller.snapshot.shuffle, isNot(shuffle));

      await tester.pumpWidget(const SizedBox());
    });
  });
}
