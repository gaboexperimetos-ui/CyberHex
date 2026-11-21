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

  // -------------------------------------------------------------------
  // Cola y biblioteca (fase 1B)
  // -------------------------------------------------------------------

  test('QueueItem y LibraryTrack comparan por contenido', () {
    const a = QueueItem(path: '/m/a.flac', title: 'a');
    const b = QueueItem(path: '/m/a.flac', title: 'a');
    const c = QueueItem(path: '/m/a.flac', title: 'otra');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));

    final track = LibraryTrack.fromPath('/musica/Artista - Tema.mp3');
    expect(track.title, 'Artista - Tema');
    expect(track.extension, 'mp3');
    expect(track.directory, '/musica');
    expect(track, LibraryTrack.fromPath('/musica/Artista - Tema.mp3'));
    expect(track.hashCode, LibraryTrack.fromPath('/musica/Artista - Tema.mp3').hashCode);
  });

  test('enqueue añade al final y el snapshot lo refleja', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.enqueue('/m/a.flac'), isTrue);
    expect(controller.enqueue('/m/b.mp3'), isTrue);

    expect(fake.enqueueCalls, 2);
    final queue = controller.snapshot.queue;
    expect(queue, hasLength(2));
    expect(queue.first.title, 'a');
    expect(queue.last.title, 'b');
    expect(controller.snapshot.queueIndex, -1);
  });

  test('playAt salta a la pista y respeta los índices fuera de rango', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.enqueue('/m/a.flac');
    controller.enqueue('/m/b.mp3');

    expect(controller.playAt(1), isTrue);
    expect(fake.playAtCalls, 1);
    expect(controller.snapshot.queueIndex, 1);
    expect(controller.snapshot.title, 'b');
    expect(controller.snapshot.playing, isTrue);
    expect(controller.position.value, 0);

    expect(controller.playAt(9), isFalse);
    expect(controller.playAt(-1), isFalse);
  });

  test('playNext inserta justo después de la pista actual', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.enqueue('/m/a.flac');
    controller.enqueue('/m/c.mp3');
    controller.playAt(0);

    expect(controller.playNext('/m/b.mp3'), isTrue);
    expect(fake.playNextCalls, 1);
    expect(fake.queuePaths, ['/m/a.flac', '/m/b.mp3', '/m/c.mp3']);
    expect(controller.snapshot.queue.map((i) => i.title).toList(),
        ['a', 'b', 'c']);
  });

  test('moveQueueItem reordena sin perder la pista activa', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.enqueue('/m/a.flac');
    controller.enqueue('/m/b.mp3');
    controller.enqueue('/m/c.ogg');
    controller.playAt(0);

    expect(controller.moveQueueItem(0, 2), isTrue);
    expect(fake.queuePaths, ['/m/b.mp3', '/m/c.ogg', '/m/a.flac']);
    // La pista que sonaba (a) se movió al final: el índice la sigue.
    expect(controller.snapshot.queueIndex, 2);
    expect(controller.snapshot.title, 'a');
  });

  test('removeQueueItem quita y ajusta el índice activo', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.enqueue('/m/a.flac');
    controller.enqueue('/m/b.mp3');
    controller.enqueue('/m/c.ogg');
    controller.playAt(2);

    expect(controller.removeQueueItem(0), isTrue);
    expect(fake.queuePaths, ['/m/b.mp3', '/m/c.ogg']);
    expect(controller.snapshot.queueIndex, 1);

    expect(controller.removeQueueItem(5), isFalse);
  });

  test('clearQueue vacía la cola y suelta la pista', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.enqueue('/m/a.flac');
    controller.playAt(0);

    controller.clearQueue();

    expect(fake.clearCalls, 1);
    expect(controller.snapshot.queue, isEmpty);
    expect(controller.snapshot.queueIndex, -1);
    expect(controller.snapshot.hasTrack, isFalse);
  });

  test('con la cola protegida, abrir una pista no vacía la cola', () async {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    controller.queueProtected = true;
    expect(controller.snapshot.queueProtected, isTrue);

    controller.enqueue('/m/vieja1.flac');
    controller.enqueue('/m/vieja2.flac');

    final error = await controller.openFile('/m/nueva.mp3');
    expect(error, isNull);
    expect(fake.loadAndPlayCalls, 1);
    // Las dos anteriores siguen y la nueva se añade al final.
    expect(fake.queuePaths, ['/m/vieja1.flac', '/m/vieja2.flac', '/m/nueva.mp3']);
    expect(controller.snapshot.queue, hasLength(3));
    expect(controller.snapshot.queueIndex, 2);
    expect(controller.snapshot.playing, isTrue);
  });

  test('sin la cola protegida, abrir una pista reemplaza la cola', () async {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    controller.enqueue('/m/vieja1.flac');
    controller.enqueue('/m/vieja2.flac');

    final error = await controller.openFile('/m/nueva.mp3');
    expect(error, isNull);
    expect(fake.loadAndPlayCalls, 0);
    expect(fake.queuePaths, ['/m/nueva.mp3']);
    expect(controller.snapshot.queue, hasLength(1));
  });

  test('scanDirectory cachea el resultado de la biblioteca', () async {
    final fake = FakePlayer()
      ..library = [
        LibraryTrack.fromPath('/m/a.flac'),
        LibraryTrack.fromPath('/m/sub/b.mp3'),
      ];
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    final tracks = await controller.scanDirectory('/m');

    expect(fake.scanCalls, 1);
    expect(tracks, hasLength(2));
    expect(tracks.last.title, 'b');
    expect(tracks.last.directory, '/m/sub');
    expect(controller.libraryTracks, tracks);
    expect(controller.libraryRemoved, 0);
  });

  // -------------------------------------------------------------------
  // Fase 2: núcleo DSP audiófilo
  // -------------------------------------------------------------------

  test('9D: setter, snapshot y recorte de rangos', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.snapshot.nineDEnabled, isFalse);

    controller.set9D(enabled: true, speed: 0.4, depth: 0.9);
    expect(fake.nineDCalls, 1);
    expect(controller.snapshot.nineDEnabled, isTrue);
    expect(controller.snapshot.nineDSpeed, 0.4);
    expect(controller.snapshot.nineDDepth, 0.9);

    // Solo cambia lo que se pasa: la velocidad se queda donde estaba.
    controller.set9D(depth: 0.2);
    expect(controller.snapshot.nineDSpeed, 0.4);
    expect(controller.snapshot.nineDDepth, 0.2);

    // El motor recorta; el controlador no inventa valores fuera de rango.
    controller.set9D(speed: 99, depth: 9);
    expect(controller.snapshot.nineDSpeed, 2.0);
    expect(controller.snapshot.nineDDepth, 1.0);
    controller.set9D(speed: -1, depth: -1);
    expect(controller.snapshot.nineDSpeed, 0.05);
    expect(controller.snapshot.nineDDepth, 0.0);

    controller.toggle9D();
    expect(controller.snapshot.nineDEnabled, isFalse);
  });

  test('potenciador estéreo: ancho y punch en el snapshot', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.snapshot.stereoWidth, 1);
    expect(controller.snapshot.bassPunch, 0);

    controller.setStereoEnhance(width: 1.7, bassPunch: 0.6);
    expect(fake.stereoEnhanceCalls, 1);
    expect(controller.snapshot.stereoWidth, 1.7);
    expect(controller.snapshot.bassPunch, 0.6);

    controller.setStereoEnhance(bassPunch: 0.1);
    expect(controller.snapshot.stereoWidth, 1.7);
    expect(controller.snapshot.bassPunch, 0.1);

    controller.setStereoEnhance(width: 9, bassPunch: 9);
    expect(controller.snapshot.stereoWidth, 2.0);
    expect(controller.snapshot.bassPunch, 1.0);
  });

  test('karaoke: el mando y su alternancia respetan 0..1', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    controller.setVocalCut(0.5);
    expect(fake.vocalCutCalls, 1);
    expect(controller.snapshot.vocalCut, 0.5);

    controller.setVocalCut(3);
    expect(controller.snapshot.vocalCut, 1.0);

    controller.toggleVocalCut(); // estaba por encima de 0 → se apaga
    expect(controller.snapshot.vocalCut, 0.0);
    controller.toggleVocalCut(); // apagado → 0.85
    expect(controller.snapshot.vocalCut, 0.85);
  });

  test('crossfeed y modo noche: estado y cantidad en el snapshot', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.snapshot.crossfeedEnabled, isFalse);
    expect(controller.snapshot.nightModeEnabled, isFalse);

    controller.setCrossfeed(enabled: true, level: 0.3);
    expect(fake.crossfeedCalls, 1);
    expect(controller.snapshot.crossfeedEnabled, isTrue);
    expect(controller.snapshot.crossfeedLevel, 0.3);

    controller.setNightMode(enabled: true, amount: 0.8);
    expect(fake.nightModeCalls, 1);
    expect(controller.snapshot.nightModeEnabled, isTrue);
    expect(controller.snapshot.nightModeAmount, 0.8);

    controller.setCrossfeed(level: 7);
    expect(controller.snapshot.crossfeedLevel, 1.0);
    // El nivel no se dispara al cambiar solo la cantidad.
    expect(controller.snapshot.crossfeedEnabled, isTrue);

    controller.toggleCrossfeed();
    controller.toggleNightMode();
    expect(controller.snapshot.crossfeedEnabled, isFalse);
    expect(controller.snapshot.nightModeEnabled, isFalse);
  });

  test('salida S16 con dither', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);

    expect(controller.snapshot.s16Output, isFalse);
    controller.setS16Output(true);
    expect(fake.s16Calls, 1);
    expect(controller.snapshot.s16Output, isTrue);
    controller.setS16Output(false);
    expect(controller.snapshot.s16Output, isFalse);
  });

  test('el snapshot compara los campos DSP: == y hashCode', () {
    const a = PlayerSnapshot(vocalCut: 0.2, bassPunch: 0.4);
    const b = PlayerSnapshot(vocalCut: 0.2, bassPunch: 0.4);
    const c = PlayerSnapshot(vocalCut: 0.2, bassPunch: 0.5);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));

    final withNineD = a.copyWith(nineDEnabled: true, nineDSpeed: 0.3, nineDDepth: 0.1);
    expect(withNineD.nineDEnabled, isTrue);
    expect(withNineD.nineDSpeed, 0.3);
    expect(withNineD.nineDDepth, 0.1);
    expect(withNineD.vocalCut, 0.2); // lo que no se toca, no cambia
    expect(withNineD, isNot(a));

    final withAll = a.copyWith(
      stereoWidth: 1.5,
      crossfeedEnabled: true,
      crossfeedLevel: 0.7,
      nightModeEnabled: true,
      nightModeAmount: 0.9,
      s16Output: true,
    );
    expect(withAll.crossfeedLevel, 0.7);
    expect(withAll.nightModeAmount, 0.9);
    expect(withAll.s16Output, isTrue);
    expect(withAll.hashCode, isNot(a.hashCode));
  });

  test('los setters DSP no hacen nada tras dispose', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    controller.dispose();

    controller.set9D(enabled: true);
    controller.setVocalCut(1);
    controller.setNightMode(enabled: true);
    controller.setS16Output(true);

    expect(fake.nineDCalls, 0);
    expect(fake.vocalCutCalls, 0);
    expect(fake.nightModeCalls, 0);
    expect(fake.s16Calls, 0);
  });

  test('dispose libera el motor', () {
    final fake = FakePlayer();
    final controller = PlayerController(fake);
    controller.dispose();
    expect(fake.disposed, isTrue);
  });
}
