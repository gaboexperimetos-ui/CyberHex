import 'dart:io';

import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/platform/playback_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';

void main() {
  test('restaura la sesión local y guarda el estado actualizado', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cyberhex-session-test',
    );
    addTearDown(() => directory.delete(recursive: true));

    final stateFile = File(
      '${directory.path}${Platform.pathSeparator}playback-session.chstate',
    );
    await stateFile.writeAsString('saved session');

    final fake = FakePlayer()
      ..hasTrack = true
      ..queue.add('/music/track.flac')
      ..stateToLoad = 42.5;
    final controller = PlayerController(fake);
    final session = PlaybackSessionPersistence(
      controller,
      supportDirectoryProvider: () async => directory,
    );
    addTearDown(controller.dispose);
    addTearDown(session.dispose);

    await session.initialize();
    expect(session.restored, isTrue);
    expect(controller.position.value, 42.5);

    await session.saveNow();
    expect(fake.savedStatePath, stateFile.path);
    expect(session.status, 'Sesión guardada automáticamente.');
  });
}
