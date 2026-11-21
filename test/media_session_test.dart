import 'dart:typed_data';

import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/platform/media_session_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

/// Tests del puente sin dispositivo: el canal se simula con
/// `TestDefaultBinaryMessengerBinding`, así que no hace falta Android ni la `.so`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
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

  List<MethodCall> callsTo(String method) =>
      outgoing.where((MethodCall call) => call.method == method).toList();

  /// Simula un mensaje del servicio Kotlin hacia Dart.
  Future<void> fromPlatform(String method, [Object? arguments]) async {
    await messenger.handlePlatformMessage(
      MediaSessionChannel.channelName,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (ByteData? _) {},
    );
  }

  test('envía metadatos al conectarse y cuando cambia la pista', () async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Uno'
      ..artist = 'Artista'
      ..album = 'Álbum'
      ..duration = 100;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.pump();

    final bridge = MediaSessionChannel(controller);
    addTearDown(bridge.dispose);
    await pumpEventQueue();

    final first = callsTo('updateMetadata');
    expect(first, hasLength(1));
    final args = first.single.arguments as Map<Object?, Object?>;
    expect(args['title'], 'Uno');
    expect(args['artist'], 'Artista');
    expect(args['album'], 'Álbum');
    expect(args['durationMs'], 100000);

    fake
      ..title = 'Dos'
      ..duration = 200;
    controller.pump();
    await pumpEventQueue();

    final second = callsTo('updateMetadata');
    expect(second, hasLength(2));
    expect((second.last.arguments as Map<Object?, Object?>)['title'], 'Dos');
    expect((second.last.arguments as Map<Object?, Object?>)['durationMs'], 200000);
  });

  test('updateState se limita a un segundo entero de posición', () async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..duration = 240;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = MediaSessionChannel(controller);
    addTearDown(bridge.dispose);
    await pumpEventQueue();

    fake.position = 1.4;
    controller.pump();
    await pumpEventQueue();
    final afterFirst = callsTo('updateState');
    expect((afterFirst.last.arguments as Map<Object?, Object?>)['positionMs'], 1400);
    final count = afterFirst.length;

    // Mismo segundo: no debe cruzar el canal.
    fake.position = 1.9;
    controller.pump();
    await pumpEventQueue();
    expect(callsTo('updateState'), hasLength(count));

    // Segundo nuevo: sí.
    fake.position = 2.2;
    controller.pump();
    await pumpEventQueue();
    expect(callsTo('updateState'), hasLength(count + 1));
    expect(
      (callsTo('updateState').last.arguments as Map<Object?, Object?>)['positionMs'],
      2200,
    );
  });

  test('los comandos entrantes llegan al controlador', () async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..duration = 100;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    final bridge = MediaSessionChannel(controller);
    addTearDown(bridge.dispose);

    await fromPlatform('play');
    expect(fake.isPlaying, isTrue);

    await fromPlatform('pause');
    expect(fake.isPlaying, isFalse);

    await fromPlatform('toggle');
    expect(fake.isPlaying, isTrue);

    await fromPlatform('next');
    expect(fake.nextCalls, 1);

    await fromPlatform('previous');
    expect(fake.previousCalls, 1);

    await fromPlatform('seek', 42.5);
    expect(fake.position, 42.5);

    await fromPlatform('setVolume', 0.8);
    expect(controller.snapshot.volume, 0.8);
  });

  test('seek no se sale de la duración de la pista', () async {
    final fake = FakePlayer()
      ..hasTrack = true
      ..duration = 30;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    final bridge = MediaSessionChannel(controller);
    addTearDown(bridge.dispose);

    await fromPlatform('seek', 300.0);
    expect(fake.position, 30);

    await fromPlatform('seek', -5.0);
    expect(fake.position, 0);
  });

  test('duck baja al 25 % y restaura el volumen exacto', () async {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    final bridge = MediaSessionChannel(controller);
    addTearDown(bridge.dispose);

    controller.setVolume(0.8);
    await fromPlatform('duck', true);
    expect(controller.snapshot.volume, closeTo(0.2, 1e-9));
    expect(bridge.ducked, isTrue);
    expect(bridge.userVolume, 0.8);

    // Un segundo duck(true) no debe guardar el volumen ya duckeado.
    await fromPlatform('duck', true);
    expect(controller.snapshot.volume, closeTo(0.2, 1e-9));

    await fromPlatform('duck', false);
    expect(controller.snapshot.volume, 0.8);
    expect(bridge.ducked, isFalse);
  });

  test('duck(false) sin duck previo no toca el volumen', () async {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    final bridge = MediaSessionChannel(controller);
    addTearDown(bridge.dispose);

    controller.setVolume(0.35);
    await fromPlatform('duck', false);
    expect(controller.snapshot.volume, 0.35);
  });

  test('sin canal nativo (escritorio) no lanza', () async {
    messenger.setMockMethodCallHandler(channel, null);

    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = MediaSessionChannel(controller);
    addTearDown(bridge.dispose);

    controller.play();
    controller.seek(10);
    await pumpEventQueue();

    // Si llegásemos aquí sin excepción, el MissingPluginException se ignoró.
    expect(bridge.ducked, isFalse);
  });
}
