import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/mini_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

void main() {
  testWidgets('el mini-reproductor responde con haptica al tocar play', (
    tester,
  ) async {
    final sent = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        sent.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final fake = FakePlayer()
      ..hasTrack = true
      ..title = 'Tema'
      ..artist = 'Grupo'
      ..duration = 120;
    final controller = PlayerController(fake);
    addTearDown(controller.dispose);
    controller.pump();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MiniPlayer(controller: controller, onOpen: () {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      sent.where((c) => c.method == 'HapticFeedback.vibrate'),
      isEmpty,
      reason: 'antes de tocar nada no debe vibrar',
    );

    // El botón «Siguiente» del mini es un IconButton(tooltip:), fiable para
    // el buscador de tooltips de este Flutter.
    await tester.tap(find.byTooltip('Siguiente'));
    await tester.pump();

    expect(
      sent.where((c) => c.method == 'HapticFeedback.vibrate'),
      isNotEmpty,
      reason: 'al tocar un control debe dispararse la respuesta háptica',
    );

    await tester.pumpWidget(const SizedBox());
  });
}
