import 'dart:math' as math;

import 'package:cyberhex/core/eq_presets.dart';
import 'package:cyberhex/core/player_api.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/audio_lab_sheet.dart';
import 'package:cyberhex/ui/eq_sheet.dart';
import 'package:cyberhex/ui/hearing_test_sheet.dart';
import 'package:cyberhex/ui/visualizer_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

/// Las 36 frecuencias del contrato: 20 Hz a 20 kHz repartidas logarítmicamente.
List<double> _frequencies() =>
    List<double>.generate(36, (i) => 20 * math.pow(1000, i / 35).toDouble());

/// Envuelve un widget en la app mínima con el tema real.
Widget _app(Widget child) => MaterialApp(
      theme: buildCyberHexTheme(),
      home: Scaffold(body: child),
    );

void main() {
  group('EqPreset', () {
    test('el preset plano deja todas las bandas a cero', () {
      final freqs = <double>[20, 100, 1000, 20000];
      expect(EqPreset.flat.gainsFor(freqs), everyElement(0));
    });

    test('interpola en logaritmo y recorta a ±18 dB', () {
      const preset = EqPreset(
        name: 'Prueba',
        description: '',
        anchors: <EqAnchor>[EqAnchor(100, 0), EqAnchor(1000, 12)],
      );
      final gains = preset.gainsFor(<double>[50, 100, 316.23, 1000, 5000]);
      expect(gains[0], 0, reason: 'por debajo del primer anclaje');
      expect(gains[1], 0);
      // 316 Hz es la mitad logarítmica entre 100 y 1000: 6 dB.
      expect(gains[2], closeTo(6, 0.1));
      expect(gains[3], 12);
      expect(gains[4], 12, reason: 'por encima del último anclaje');

      const hard = EqPreset(
        name: 'X',
        description: '',
        anchors: <EqAnchor>[EqAnchor(100, 40), EqAnchor(1000, -40)],
      );
      expect(hard.gainsFor(<double>[100, 1000]), <double>[18, -18]);
    });

    test('la compensación refuerza solo lo que no se oyó', () {
      final freqs = <double>[100, 1000, 10000];
      final preset = EqPreset.compensationFrom(
        frequencies: freqs,
        heard: <bool>[true, false],
      );
      final gains = preset.gainsFor(freqs);
      expect(gains[0], 0);
      expect(gains[1], 12);
      expect(preset.name, 'Mi oído');
    });

    test('los presets incluidos son 36 valores dentro del rango', () {
      final freqs = _frequencies();
      for (final preset in eqPresets) {
        final gains = preset.gainsFor(freqs);
        expect(gains.length, 36, reason: preset.name);
        for (final db in gains) {
          expect(db, inInclusiveRange(-18, 18), reason: preset.name);
        }
      }
    });
  });

  group('VisualizerWidget', () {
    testWidgets('dibuja el espectro y los medidores L/R', (tester) async {
      final fake = FakePlayer()
        ..levelsValue = const PlayerLevels(
          rmsLeft: 0.3,
          rmsRight: 0.2,
          peakLeft: 0.8,
          peakRight: 0.7,
        );
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(VisualizerWidget(controller: controller)));
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      expect(fake.spectrumBands, 28);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('el estilo hexágonos se pinta igual', (tester) async {
      final controller = PlayerController(FakePlayer());
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(
        VisualizerWidget(
          controller: controller,
          style: VisualizerStyle.hexagon,
          bands: 12,
          showMeters: false,
        ),
      ));
      await tester.pump();

      final custom = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
      expect(custom, isNotEmpty);
      expect(find.text('L'), findsNothing);
      expect(VisualizerStyle.hexagon.label, 'Hexágonos');
      expect(VisualizerStyle.bars.next, VisualizerStyle.hexagon);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('AudioLabSheet', () {
    testWidgets('enseña las secciones y el visualizador', (tester) async {
      final controller = PlayerController(FakePlayer());
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(AudioLabSheet(controller: controller)));
      await tester.pump();

      expect(find.text('Laboratorio de audio'), findsOneWidget);
      expect(find.text('Espacial'), findsOneWidget);
      expect(find.text('Mezcla y motor'), findsOneWidget);
      expect(find.text('Avance y temporizador'), findsOneWidget);
      expect(find.text('Paisaje sonoro'), findsOneWidget);
      expect(find.text('Herramientas'), findsOneWidget);
      expect(find.byType(VisualizerWidget), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('el interruptor de 9D llega al motor', (tester) async {
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(AudioLabSheet(controller: controller)));
      await tester.pump();

      final toggle = find.widgetWithText(SwitchListTile, 'Audio 9D');
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();

      expect(fake.nineDFlag, isTrue);
      expect(controller.snapshot.nineDEnabled, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('el chip de paisaje enciende la lluvia', (tester) async {
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(AudioLabSheet(controller: controller)));
      await tester.pump();

      // Despliega la sección de paisaje y toca «Lluvia».
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Paisaje sonoro'), 250,
          scrollable: scrollable);
      await tester.tap(find.text('Paisaje sonoro'));
      await tester.pump();

      final chip = find.widgetWithText(ChoiceChip, 'Lluvia');
      await tester.scrollUntilVisible(chip, 120, scrollable: scrollable);
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();

      expect(fake.soundscape, SoundscapePreset.rain);
      expect(fake.soundscapeCalls, 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('detectar BPM muestra el valor del motor', (tester) async {
      // Con cola: el panel saca la ruta de la pista actual del snapshot, y sin
      // ella ni siquiera llega a pedir los BPM.
      final fake = FakePlayer()
        ..bpmValue = 128.3
        ..queuePaths.add('/musica/tema.flac')
        ..queueIndexValue = 0;
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);
      await controller.openFile('/musica/tema.flac');

      await tester.pumpWidget(_app(AudioLabSheet(controller: controller)));
      await tester.pump();

      // `ensureVisible` basta: el panel es un `SingleChildScrollView`, así que
      // el botón ya existe en el árbol y solo hay que llevarlo a la ventana.
      await tester.ensureVisible(find.text('Detectar BPM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detectar BPM'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.bpmCalls, 1);
      expect(fake.bpmPath, '/musica/tema.flac');
      expect(find.text('128 BPM'), findsOneWidget);
      expect(find.textContaining('128.3'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('HearingTestSheet', () {
    testWidgets('recorre las bandas y restaura el EQ al cancelar',
        (tester) async {
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);

      final before = List<double>.of(controller.eqGains);

      await tester.pumpWidget(_app(HearingTestSheet(controller: controller)));
      await tester.pump();

      expect(find.text('Prueba de audición'), findsOneWidget);
      expect(find.text('¿Oyes este tono sobre la música?'), findsOneWidget);
      // Al empezar, todas las bandas quedan fuera menos la primera.
      expect(controller.eqGains.first, 12);

      await tester.tap(find.text('Cancelar (restaura el EQ)'));
      await tester.pump();

      expect(controller.eqGains, before);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('10 respuestas terminan la prueba y compensan lo perdido',
        (tester) async {
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(HearingTestSheet(controller: controller)));
      await tester.pump();

      // El primer tercio se oye, el resto no.
      for (var i = 0; i < 10; i++) {
        final label = i < 3 ? 'Lo oigo' : 'No lo oigo';
        await tester.tap(find.text(label));
        await tester.pump();
      }

      expect(find.textContaining('No has oído'), findsOneWidget);

      await tester.tap(find.text('Aplicar «Mi oído»'));
      await tester.pump();

      final gains = controller.eqGains;
      expect(gains.length, 36);
      // Las bandas altas (no oídas) quedan reforzadas; las de abajo, planas.
      expect(gains.first, 0);
      expect(gains.last, greaterThan(0));

      await tester.pumpWidget(const SizedBox());
    });

    test('describeEqPreset resume la curva', () {
      final frequencies = _frequencies();
      final text = describeEqPreset(eqPresets.first, frequencies);
      expect(text.startsWith('Plano'), isTrue);
      expect(bandLabel(frequencies, 0), '20');
      expect(bandLabel(frequencies, 35), '20k');
    });
  });

  group('EqualizerSheet', () {
    testWidgets('lista los presets y aplica uno al tocarlo', (tester) async {
      final fake = FakePlayer();
      final controller = PlayerController(fake);
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(EqualizerSheet(controller: controller)));
      await tester.pump();

      expect(find.text('Ecualizador'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Plano'), findsOneWidget);

      final rock = find.widgetWithText(ActionChip, 'Rock');
      await tester.tap(rock);
      await tester.pump();

      // Rock sube los graves: la primera banda deja de ser cero.
      expect(controller.eqGains.first, greaterThan(0));

      await tester.pumpWidget(const SizedBox());
    });
  });
}
