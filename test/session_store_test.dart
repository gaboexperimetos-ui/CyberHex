import 'dart:convert';
import 'dart:io';

import 'package:cyberhex/core/favorites_store.dart';
import 'package:cyberhex/core/player_api.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/core/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

void main() {
  late Directory temp;
  late File file;
  late SessionStore store;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cyberhex-session');
    file = File('${temp.path}/session.json');
    store = SessionStore(file: file);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('SessionSnapshot', () {
    test('va y vuelve por JSON sin perder nada', () {
      const session = SessionSnapshot(
        queue: ['/m/a.flac', '/m/b.mp3'],
        queueIndex: 1,
        position: 42.5,
        volume: 0.7,
        repeatMode: 2,
        shuffle: true,
      );

      final copy = SessionSnapshot.fromJson(
        jsonDecode(jsonEncode(session.toJson())) as Map<String, Object?>,
      );

      expect(copy, session);
      expect(copy.hashCode, session.hashCode);
      expect(copy.queue, ['/m/a.flac', '/m/b.mp3']);
      expect(copy.position, 42.5);
    });

    test('un JSON raro se degrada a valores seguros', () {
      final copy = SessionSnapshot.fromJson(const <String, Object?>{
        'queue': ['/m/a.flac', 42, '', '/m/b.mp3'],
        'queueIndex': 99,
        'position': 'no',
        'volume': 4,
        'repeatMode': 9,
        'shuffle': 'sí',
      });

      // Solo las cadenas no vacías; el índice fuera de rango se descarta.
      expect(copy.queue, ['/m/a.flac', '/m/b.mp3']);
      expect(copy.queueIndex, -1);
      expect(copy.position, 0);
      expect(copy.volume, 1);
      expect(copy.repeatMode, 2);
      expect(copy.shuffle, isFalse);
    });

    test('isEmpty distingue una sesión vacía', () {
      expect(const SessionSnapshot().isEmpty, isTrue);
      expect(const SessionSnapshot(queue: ['/m/a.flac'], queueIndex: 0).isEmpty,
          isFalse);
    });
  });

  group('StorageDirectory', () {
    test('CYBERHEX_DATA_DIR manda sobre todo lo demás', () {
      final dir = StorageDirectory.resolve(
        environment: {
          'CYBERHEX_DATA_DIR': '/datos/cyberhex',
          'XDG_DATA_HOME': '/xdg',
          'HOME': '/home/ana',
        },
        tempPath: '/tmp',
        windows: false,
      );
      expect(dir.path, '/datos/cyberhex');
    });

    test('Linux: XDG_DATA_HOME primero, luego ~/.local/share', () {
      final xdg = StorageDirectory.resolve(
        environment: {'XDG_DATA_HOME': '/xdg', 'HOME': '/home/ana'},
        tempPath: '/tmp',
        windows: false,
      );
      expect(xdg.path, '/xdg/cyberhex');

      final home = StorageDirectory.resolve(
        environment: {'HOME': '/home/ana'},
        tempPath: '/tmp',
        windows: false,
      );
      expect(home.path, '/home/ana/.local/share/cyberhex');
    });

    test('Windows usa APPDATA', () {
      final dir = StorageDirectory.resolve(
        environment: {'APPDATA': r'C:\Users\ana\AppData\Roaming'},
        tempPath: r'C:\Temp',
        windows: true,
      );
      expect(dir.path, r'C:\Users\ana\AppData\Roaming\CyberHex');
    });

    test('sin variables cae al temporal, sin reventar', () {
      final dir = StorageDirectory.resolve(
        environment: const <String, String>{},
        tempPath: '/tmp',
        windows: false,
      );
      expect(dir.path, '/tmp/cyberhex');
    });

    test('ensure crea el directorio y sus padres', () async {
      final target = Directory('${temp.path}/a/b/c');
      final ready = await StorageDirectory.ensure(target);
      expect(ready.path, target.path);
      expect(target.existsSync(), isTrue);
    });

    test('ensure sobre algo que ya existe no falla', () async {
      final ready = await StorageDirectory.ensure(temp);
      expect(ready.path, temp.path);
      expect(temp.existsSync(), isTrue);
    });

    test('los almacenes por defecto viven en el directorio de datos', () {
      final store = SessionStore();
      expect(store.file.parent.path, StorageDirectory.current.path);
      expect(store.file.path, endsWith('/session.json'));

      final favorites = FavoritesStore();
      expect(favorites.file!.parent.path, StorageDirectory.current.path);
      expect(favorites.file!.path, endsWith('/favorites.json'));
    });
  });

  group('SessionStore', () {
    test('sin archivo devuelve null', () async {
      expect(await store.load(), isNull);
    });

    test('guarda y recupera, y no deja el .tmp detrás', () async {
      const session = SessionSnapshot(
        queue: ['/m/a.flac'],
        queueIndex: 0,
        position: 3,
      );

      expect(await store.save(session), isTrue);
      expect(file.existsSync(), isTrue);
      expect(File('${file.path}.tmp').existsSync(), isFalse);

      final loaded = await store.load();
      expect(loaded, session);
    });

    test('crea el directorio que falte', () async {
      final deep = SessionStore(
        file: File('${temp.path}/a/b/c/session.json'),
      );
      expect(await deep.save(const SessionSnapshot(queue: ['/m/a.flac'],
          queueIndex: 0)), isTrue);
      expect(await deep.load(), isNotNull);
    });

    test('un archivo corrupto no rompe el arranque', () async {
      file.writeAsStringSync('{"queue": [ esto no es json');
      expect(await store.load(), isNull);
    });

    test('un archivo vacío o con una lista se ignora', () async {
      file.writeAsStringSync('');
      expect(await store.load(), isNull);
      file.writeAsStringSync('[1, 2, 3]');
      expect(await store.load(), isNull);
    });

    test('una sesión sin cola no se considera sesión', () async {
      await store.save(const SessionSnapshot(volume: 0.5));
      expect(await store.load(), isNull);
    });

    test('clear borra el archivo', () async {
      await store.save(const SessionSnapshot(queue: ['/m/a.flac'],
          queueIndex: 0));
      expect(await store.clear(), isTrue);
      expect(file.existsSync(), isFalse);
    });
  });

  group('SessionKeeper', () {
    test('restaura cola, índice, posición y ajustes sin sonar', () async {
      await store.save(const SessionSnapshot(
        queue: ['/m/a.flac', '/m/b.mp3', '/m/c.ogg'],
        queueIndex: 1,
        position: 30,
        volume: 0.4,
        repeatMode: 1,
        shuffle: true,
      ));

      final fake = FakePlayer();
      final controller = PlayerController(fake);
      final keeper = SessionKeeper(controller: controller, store: store);
      addTearDown(controller.dispose);
      addTearDown(keeper.dispose);

      await keeper.restore();

      expect(fake.queuePaths, ['/m/a.flac', '/m/b.mp3', '/m/c.ogg']);
      expect(controller.snapshot.queueIndex, 1);
      expect(controller.snapshot.title, 'b');
      expect(controller.position.value, 30);
      expect(controller.snapshot.playing, isFalse);
      expect(controller.snapshot.volume, 0.4);
      expect(controller.snapshot.repeatMode, 1);
      expect(controller.snapshot.shuffle, isTrue);
    });

    test('saveNow escribe lo que hay ahora', () async {
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      final keeper = SessionKeeper(controller: controller, store: store);
      addTearDown(controller.dispose);
      addTearDown(keeper.dispose);

      controller.enqueue('/m/a.flac');
      controller.enqueue('/m/b.mp3');
      controller.playAt(1);
      controller.setVolume(0.25);
      controller.position.value = 12;

      expect(await keeper.saveNow(), isTrue);

      final saved = await store.load();
      expect(saved, isNotNull);
      expect(saved!.queue, ['/m/a.flac', '/m/b.mp3']);
      expect(saved.queueIndex, 1);
      expect(saved.position, 12);
      expect(saved.volume, 0.25);
    });

    test('al pausar programa un guardado y dispose lo escribe', () async {
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      final keeper = SessionKeeper(controller: controller, store: store);
      addTearDown(controller.dispose);

      controller.enqueue('/m/a.flac');
      controller.playAt(0);
      await keeper.restore(); // no hay sesión: solo engancha el listener

      controller.pause();
      await keeper.dispose();

      final saved = await store.load();
      expect(saved, isNotNull);
      expect(saved!.queue, ['/m/a.flac']);
      expect(saved.queueIndex, 0);
    });

    test('sin sesión previa no toca nada y deja el controlador vivo',
        () async {
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      final keeper = SessionKeeper(controller: controller, store: store);
      addTearDown(controller.dispose);
      addTearDown(keeper.dispose);

      await keeper.restore();

      expect(fake.queuePaths, isEmpty);
      expect(controller.snapshot.volume, 1);
      expect(controller.snapshot.shuffle, isFalse);
    });
  });

  group('ajustes de audio en la sesión', () {
    const tuned = AudioSettings(
      nineDEnabled: true,
      nineDSpeed: 0.4,
      nineDDepth: 0.7,
      stereoWidth: 1.5,
      bassPunch: 0.4,
      vocalCut: 0.6,
      crossfeedEnabled: true,
      crossfeedLevel: 0.3,
      nightModeEnabled: true,
      nightModeAmount: 0.8,
      balance: -0.4,
      channelMode: 2,
      replayGainEnabled: false,
      replayGainAlbum: true,
      crossfade: 4,
      gapless: false,
      speed: 1.25,
      pitch: -3,
      soundscape: SoundscapePreset.brown,
      soundscapeLevel: 0.35,
    );

    test('el snapshot guarda y recupera el DSP entero', () {
      final snapshot = SessionSnapshot(
        queue: const ['/m/a.flac'],
        queueIndex: 0,
        volume: 0.7,
        audio: tuned,
      );
      final restored = SessionSnapshot.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map,
        ),
      );
      expect(restored.audio, tuned);
      expect(restored.volume, 0.7);
      expect(SessionSnapshot.formatVersion, 2);
    });

    test('una sesión vieja (sin audio) queda en valores neutros', () {
      final restored = SessionSnapshot.fromJson(<String, Object?>{
        'version': 1,
        'queue': <String>['/m/a.flac'],
        'queueIndex': 0,
        'volume': 1,
      });
      expect(restored.audio, AudioSettings.neutral);
      expect(restored.audio.soundscape, SoundscapePreset.off);
      expect(restored.audio.gapless, isTrue);
    });

    test('un audio corrupto se degrada campo a campo', () {
      final restored = AudioSettings.fromJson(<String, Object?>{
        'nineD': <String, Object?>{'on': true, 'speed': 'rápido', 'depth': 9},
        'stereo': 'no es un mapa',
        'balance': 42,
        'channelMode': 99,
        'gapless': 'sí',
        'soundscape': <String, Object?>{'preset': 'volcano', 'level': -5},
        'speed': 0,
      });
      expect(restored.nineDEnabled, isTrue);
      expect(restored.nineDSpeed, 0.15, reason: 'texto -> valor por defecto');
      expect(restored.nineDDepth, 1.0);
      expect(restored.stereoWidth, 1);
      expect(restored.balance, 1.0);
      expect(restored.channelMode, 2);
      expect(restored.gapless, isTrue);
      expect(restored.soundscape, SoundscapePreset.off);
      expect(restored.soundscapeLevel, 0);
      expect(restored.speed, 0.25);
    });

    test('SessionKeeper restaura el DSP y guarda los cambios', () async {
      await store.save(SessionSnapshot(
        queue: const ['/m/a.flac'],
        queueIndex: 0,
        volume: 0.6,
        audio: tuned,
      ));

      final fake = FakePlayer();
      final controller = PlayerController(fake);
      final keeper = SessionKeeper(controller: controller, store: store);
      addTearDown(controller.dispose);
      addTearDown(keeper.dispose);

      await keeper.restore();

      expect(fake.nineDFlag, isTrue);
      expect(fake.nineDSpeedValue, 0.4);
      expect(fake.stereoWidthValue, 1.5);
      expect(fake.vocalCutValue, 0.6);
      expect(fake.crossfeedFlag, isTrue);
      expect(fake.nightModeFlag, isTrue);
      expect(fake.balance, closeTo(-0.4, 1e-9));
      expect(fake.channelMode, 2);
      expect(fake.soundscape, SoundscapePreset.brown);
      expect(fake.soundscapeLevel, 0.35);
      expect(fake.speed, 1.25);
      expect(fake.pitch, -3);
      expect(fake.crossfade, 4);
      expect(fake.gapless, isFalse);

      // Un cambio de DSP basta para que se escriba la sesión.
      controller.setSoundscape(SoundscapePreset.rain, level: 0.9);
      expect(await keeper.saveNow(), isTrue);
      final saved = await store.load();
      expect(saved!.audio.soundscape, SoundscapePreset.rain);
      expect(saved.audio.soundscapeLevel, 0.9);
      expect(saved.audio.nineDEnabled, isTrue);
    });

    test('el aviso de ajustes usa antirrebote y dispose lo escribe', () async {
      // Sin cola la sesión se considera vacía y no se guarda: se da una pista.
      final fake = FakePlayer()
        ..queuePaths.add('/m/uno.mp3')
        ..queueIndexValue = 0;
      final controller = PlayerController(fake);
      final keeper = SessionKeeper(controller: controller, store: store);
      addTearDown(controller.dispose);

      await keeper.restore();
      controller.setCrossfeed(enabled: true, level: 0.7);
      controller.set9D(enabled: true, speed: 0.2, depth: 0.5);
      await keeper.dispose();

      final saved = await store.load();
      expect(saved, isNotNull);
      expect(saved!.audio.crossfeedEnabled, isTrue);
      expect(saved.audio.nineDEnabled, isTrue);
    });
  });

}
