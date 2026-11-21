import 'package:cyberhex/core/player_api.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

void main() {
  test('openFile publica la pista y limpia el estado de carga', () async {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.snapshot.busy, isFalse);

    final future = controller.openFile('/musica/tema.flac');
    expect(controller.snapshot.busy, isTrue, reason: 'mientras carga');

    expect(await future, isNull);
    expect(controller.snapshot.busy, isFalse);
    expect(controller.snapshot.hasTrack, isTrue);
    expect(controller.snapshot.duration, 120);
    expect(fake.loadedPaths, ['/musica/tema.flac']);
  });

  test('openFile devuelve y publica el error del motor', () async {
    final fake = FakePlayer()..loadResult = false;
    fake.lastError = 'no se pudo decodificar el archivo';
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final error = await controller.openFile('/musica/roto.mp3');

    expect(error, 'no se pudo decodificar el archivo');
    expect(controller.snapshot.error, 'no se pudo decodificar el archivo');
    expect(controller.snapshot.hasTrack, isFalse);
    expect(controller.snapshot.busy, isFalse);
  });

  test('pump copia la posición y detecta play/pausa', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    fake.position = 12.5;
    fake.isPlaying = true;
    controller.pump();

    expect(controller.position.value, 12.5);
    expect(controller.snapshot.playing, isTrue);

    fake.isPlaying = false;
    controller.pump();
    expect(controller.snapshot.playing, isFalse);
  });

  test('el evento track relee etiquetas y reinicia la posición', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    fake
      ..position = 30
      ..title = 'Otra pista'
      ..duration = 61;
    fake.emit(const PlayerEvent(PlayerEventKind.track, a: 1, b: 2));
    controller.pump();

    expect(controller.position.value, 0);
    expect(controller.snapshot.title, 'Otra pista');
    expect(controller.snapshot.duration, 61);
  });

  test('el volumen se acota y se refleja en el snapshot', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    controller.setVolume(0.4);
    expect(controller.snapshot.volume, 0.4);

    controller.setVolume(3);
    expect(controller.snapshot.volume, 1);
  });

  test('toggle llama a play o pause según el estado', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    controller.toggle();
    expect(fake.playCalls, 1);

    controller.toggle();
    expect(fake.pauseCalls, 1);
  });

  test('next y previous llegan al motor y refrescan', () {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    controller.next();
    controller.previous();

    expect(fake.nextCalls, 1);
    expect(fake.previousCalls, 1);
  });

  test('next se ignora tras dispose', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    controller.dispose();

    controller.next();
    controller.previous();

    expect(fake.nextCalls, 0);
    expect(fake.previousCalls, 0);
  });

  test('cycleRepeat recorre apagado, todo, una y vuelve a apagado', () {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.snapshot.repeatMode, 0);

    controller.cycleRepeat();
    expect(controller.snapshot.repeatMode, 1);
    expect(fake.repeatRequests, 1);

    controller.cycleRepeat();
    expect(controller.snapshot.repeatMode, 2);

    // Tercera pulsación: vuelve a apagado, no se queda en "una".
    controller.cycleRepeat();
    expect(controller.snapshot.repeatMode, 0);
    expect(fake.repeatRequests, 3);
  });

  test('toggleShuffle alterna y el snapshot lo refleja', () {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.snapshot.shuffle, isFalse);

    controller.toggleShuffle();
    expect(controller.snapshot.shuffle, isTrue);
    expect(fake.shuffleRequests, 1);

    controller.toggleShuffle();
    expect(controller.snapshot.shuffle, isFalse);
  });

  test('cycleRepeat y toggleShuffle se ignoran tras dispose', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    controller.dispose();

    controller.cycleRepeat();
    controller.toggleShuffle();

    expect(fake.repeatRequests, 0);
    expect(fake.shuffleRequests, 0);
  });

  test('dispose libera el motor', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    controller.dispose();
    expect(fake.disposed, isTrue);
  });
}
