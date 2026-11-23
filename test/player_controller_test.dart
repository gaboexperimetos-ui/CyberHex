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

  test('el DSP y la medición llegan al motor', () {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    fake.levels = const [0.1, 0.2, 0.3, 0.4];
    expect(controller.levels, const [0.1, 0.2, 0.3, 0.4]);
    expect(controller.spectrum(8), hasLength(8));

    controller.eqPreamp = -6;
    expect(fake.eqPreamp, -6);
    expect(controller.setBandGain(3, 4.5), isTrue);
    expect(fake.eqGains[3], 4.5);

    controller.setLimiter(true, ceilingDb: -1.5);
    expect(controller.limiter, isTrue);
    expect(fake.limiterCeiling, -1.5);

    controller.setCrossfeed(true, strength: 0.3);
    expect(controller.crossfeed, (enabled: true, strength: 0.3));

    controller.gainDb = 2.5;
    expect(fake.gainDb, 2.5);

    controller.stereoWidth = 1.5;
    expect(fake.stereoWidth, 1.5);

    controller.setTrimSilence(true, thresholdDb: -45);
    expect(controller.trimSilence.thresholdDb, -45);

    controller.setReplayGain(true);
    expect(fake.replayGainEnabled, isTrue);
    fake.replayGainGainDb = -7.5;
    expect(controller.replayGainGainDb, -7.5);

    controller.setMono(true);
    expect(controller.mono, isTrue);

    controller.setAbLoop(10, 20);
    expect(controller.abLoop, (start: 10.0, end: 20.0));
    controller.clearAbLoop();
    expect(controller.abLoop.start, -1);
  });

  test('análisis de sonoridad, normalización y silencio', () {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.analyzeCurrent(), isNull);
    fake.analysisLufs = -14.2;
    expect(controller.analyzeCurrent(), (lufs: -14.2, peakDb: 0.0));

    fake.normalizedDb = 3.5;
    expect(controller.normalizeCurrent(-16), 3.5);
    expect(controller.gainDb, 3.5);

    expect(controller.detectSilence('/musica/tema.flac'), isNull);
    fake.silence = (lead: 1.5, tail: 2.0);
    expect(controller.detectSilence('/musica/tema.flac'), (
      lead: 1.5,
      tail: 2.0,
    ));

    fake.bufferedSeconds = 3.75;
    fake.bufferUnderflows = 2;
    expect(controller.bufferedSeconds, 3.75);
    expect(controller.bufferUnderflows, 2);
  });

  test('previous reinicia la pista si ya pasaron 3 s', () {
    final fake = FakePlayer()..hasTrack = true;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    controller.seek(10);
    controller.previous();
    expect(fake.previousCalls, 0, reason: 'reinicia, no cambia de pista');
    expect(fake.position, 0);

    controller.seek(1);
    controller.previous();
    expect(fake.previousCalls, 1);
  });

  test('la cola expone sus pistas y el volumen efectivo', () {
    final fake = FakePlayer()..hasTrack = true;
    fake.queue.addAll(['/musica/a.mp3', '/musica/b.mp3']);
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.queueItem(0), '/musica/a.mp3');
    expect(controller.queueItem(1), '/musica/b.mp3');
    expect(controller.queueItem(9), '');

    fake.setVolume(0.6);
    expect(controller.volume, 0.6);
  });

  test('biblioteca, marcadores, CUE y dispositivos', () {
    final fake = FakePlayer()
      ..libraryTracks = const ['/m/a.flac', '/m/b.mp3']
      ..libraryRemoved = 1
      ..cue = const CueSheet(
        album: 'Live',
        albumPerformer: 'X',
        tracks: [
          CueTrack(
            number: 1,
            title: 'Uno',
            performer: 'X',
            file: 'live.flac',
            start: 0,
            end: 180.5,
          ),
        ],
      )
      ..loudness = (lufs: -14.2, peakDb: -0.3, duration: 240);
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final scan = controller.scanLibrary('/m');
    expect(scan?.tracks, const ['/m/a.flac', '/m/b.mp3']);
    expect(scan?.removed, 1);

    expect(controller.loadMarkers('/m/marks.txt', '/m/a.flac'), isEmpty);
    expect(
      controller.saveMarkers('/m/marks.txt', '/m/a.flac', const [
        TrackMarker(12.5, 'estribillo'),
        TrackMarker(64.0, 'solo'),
      ]),
      isTrue,
    );
    expect(controller.loadMarkers('/m/marks.txt', '/m/a.flac'), const [
      TrackMarker(12.5, 'estribillo'),
      TrackMarker(64.0, 'solo'),
    ]);

    expect(controller.removeMarker('/m/marks.txt', '/m/a.flac', 0), isTrue);
    expect(controller.loadMarkers('/m/marks.txt', '/m/a.flac'), const [
      TrackMarker(64.0, 'solo'),
    ]);

    expect(controller.clearMarkers('/m/marks.txt', '/m/a.flac'), isTrue);
    expect(controller.loadMarkers('/m/marks.txt', '/m/a.flac'), isEmpty);

    final cue = controller.readCue('/m/live.cue');
    expect(cue?.album, 'Live');
    expect(cue?.tracks.single.duration, 180.5);

    expect(controller.outputDevices, const ['Altavoces', 'Auriculares']);
    controller.outputDevice = 1;
    expect(fake.outputDevice, 1);

    expect(controller.scanLoudness('/m/a.flac')?.lufs, -14.2);
    fake.waveformPeaksValue = const [0.1, 0.9, 0.4];
    expect(controller.waveform('/m/a.flac', 3), const [0.1, 0.9, 0.4]);
    expect(controller.coreVersion, 'test');
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

    fake.position = 0;
    controller.pump();
    expect(controller.position.value, 42.5);

    fake.position = 42.7;
    controller.pump();
    expect(controller.position.value, 42.7);
  });

  test('la forma de onda se analiza de forma asíncrona', () async {
    final fake = FakePlayer()..waveformPeaksValue = const [0.2, 0.8, 0.4];
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(await controller.waveformAsync('/musica/tema.flac', 3), const [
      0.2,
      0.8,
      0.4,
    ]);
  });
}
