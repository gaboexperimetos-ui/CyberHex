import 'dart:typed_data';

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

  test('dispose libera el motor', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    controller.dispose();
    expect(fake.disposed, isTrue);
  });

  test('la cola se edita y se salta a cualquier pista', () {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.enqueue('/musica/a.mp3'), isTrue);
    expect(controller.enqueue('/musica/b.mp3'), isTrue);
    expect(controller.queueCount, 2);

    expect(controller.queueMove(0, 1), isTrue);
    expect(fake.queue, ['/musica/b.mp3', '/musica/a.mp3']);

    expect(controller.playIndex(1), isTrue);
    expect(controller.queueIndex, 1);
    expect(controller.position.value, 0);

    expect(controller.queueInsert(0, '/musica/c.mp3'), isTrue);
    expect(fake.queue.first, '/musica/c.mp3');

    expect(controller.queueRemove(0), isTrue);
    expect(controller.queueCount, 2);

    expect(controller.queueClear(), isTrue);
    expect(controller.queueCount, 0);
  });

  test('modos de reproducción y temporizador llegan al motor', () {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    controller.repeatMode = 2;
    expect(fake.repeatMode, 2);

    controller.shuffle = true;
    expect(fake.shuffle, isTrue);
    controller.setShuffleSeed(1234);
    expect(fake.shuffleSeed, 1234);

    controller.gapless = false;
    expect(fake.gapless, isFalse);

    controller.crossfadeSeconds = 3.5;
    expect(fake.crossfadeSeconds, 3.5);

    controller.speed = 1.25;
    expect(fake.speed, 1.25);

    controller.pitch = -2;
    expect(fake.pitch, -2);

    controller.setSleepTimer(600, fadeSeconds: 10);
    expect(fake.sleepTimer, 600);
    expect(fake.sleepFade, 10);
    expect(controller.sleepRemaining, 600);
  });

  test('etiquetas completas, letras y carátula llegan a la UI', () {
    final fake = FakePlayer()
      ..hasTrack = true
      ..date = '1998'
      ..genre = 'Jazz'
      ..composer = 'Miles Davis'
      ..trackNumber = 3
      ..discNumber = 1
      ..lyricsCount = 42
      ..activeLyricLine = 'so what'
      ..cover = Uint8List.fromList([1, 2, 3]);
    fake.tags['BPM'] = '132';
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.date, '1998');
    expect(controller.genre, 'Jazz');
    expect(controller.composer, 'Miles Davis');
    expect(controller.trackNumber, 3);
    expect(controller.discNumber, 1);
    expect(controller.tag('BPM'), '132');
    expect(controller.tag('no-existe'), '');
    expect(controller.sampleRate, 48000);
    expect(controller.channels, 2);
    expect(controller.lyricsCount, 42);
    expect(controller.activeLyricLine, 'so what');

    expect(controller.saveCover(0, '/tmp/portada.jpg'), isTrue);
    expect(fake.savedCoverPath, '/tmp/portada.jpg');
  });

  test('guardar y cargar el estado de reproducción', () {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.saveState('/tmp/cyberhex-state.json'), isTrue);
    expect(fake.savedStatePath, '/tmp/cyberhex-state.json');

    fake.stateToLoad = 42.5;
    expect(controller.loadState('/tmp/cyberhex-state.json'), 42.5);
    expect(controller.position.value, 42.5);
  });
}
