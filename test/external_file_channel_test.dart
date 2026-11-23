import 'dart:typed_data';

import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/platform/external_file_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

/// Tests del canal `cyberhex/intent` sin Android: el canal se simula con
/// `TestDefaultBinaryMessengerBinding`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
  const channel = MethodChannel(ExternalFileChannel.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> outgoing;

  setUp(() {
    outgoing = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      outgoing.add(call);
      if (call.method == 'getInitialFile') return null;
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  List<MethodCall> callsTo(String method) =>
      outgoing.where((MethodCall call) => call.method == method).toList();

  /// Simula a Kotlin empujando un archivo con la app ya abierta.
  Future<void> fromPlatform(String method, [Object? arguments]) async {
    await messenger.handlePlatformMessage(
      ExternalFileChannel.channelName,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (ByteData? _) {},
    );
  }

  test('el archivo inicial se carga y se reproduce', () async {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      outgoing.add(call);
      if (call.method == 'getInitialFile') return '/cache/shared_audio/shared_1.mp3';
      return true;
    });

    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = ExternalFileChannel(controller);
    addTearDown(bridge.dispose);

    await bridge.start();
    await pumpEventQueue();

    expect(callsTo('getInitialFile'), hasLength(1));
    expect(fake.loadedPaths, ['/cache/shared_audio/shared_1.mp3']);
    expect(fake.isPlaying, isTrue);
    expect(fake.playCalls, 1);
  });

  test('sin archivo inicial no se toca el motor', () async {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = ExternalFileChannel(controller);
    addTearDown(bridge.dispose);

    await bridge.start();
    await pumpEventQueue();

    expect(callsTo('getInitialFile'), hasLength(1));
    expect(fake.loadedPaths, isEmpty);
    expect(fake.playCalls, 0);
  });

  test('start() es idempotente: no repregunta al recrear', () async {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = ExternalFileChannel(controller);
    addTearDown(bridge.dispose);

    await bridge.start();
    await bridge.start();
    await pumpEventQueue();

    expect(callsTo('getInitialFile'), hasLength(1));
  });

  test('onOpenFile con la app abierta carga y reproduce', () async {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = ExternalFileChannel(controller);
    addTearDown(bridge.dispose);

    await fromPlatform('onOpenFile', '/cache/shared_audio/shared_2.flac');
    await pumpEventQueue();

    expect(fake.loadedPaths, ['/cache/shared_audio/shared_2.flac']);
    expect(fake.isPlaying, isTrue);
  });

  test('si el motor no puede abrir, no se le da a play', () async {
    final fake = FakePlayer()..loadResult = false;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = ExternalFileChannel(controller);
    addTearDown(bridge.dispose);

    await fromPlatform('onOpenFile', '/cache/shared_audio/roto.mp3');
    await pumpEventQueue();

    expect(fake.loadedPaths, ['/cache/shared_audio/roto.mp3']);
    expect(fake.playCalls, 0);
    expect(fake.isPlaying, isFalse);
  });

  test('argumentos que no son ruta se ignoran', () async {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = ExternalFileChannel(controller);
    addTearDown(bridge.dispose);

    await fromPlatform('onOpenFile', 42);
    await pumpEventQueue();

    expect(fake.loadedPaths, isEmpty);
  });

  test('sin canal nativo (escritorio) no lanza', () async {
    messenger.setMockMethodCallHandler(channel, null);

    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = ExternalFileChannel(controller);
    addTearDown(bridge.dispose);

    await bridge.start();
    await pumpEventQueue();

    expect(fake.loadedPaths, isEmpty);
  });

  test('tras dispose no se procesan más mensajes', () async {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final bridge = ExternalFileChannel(controller);
    bridge.dispose();

    await fromPlatform('onOpenFile', '/cache/shared_audio/tarde.mp3');
    await pumpEventQueue();

    expect(fake.loadedPaths, isEmpty);
  });
}
