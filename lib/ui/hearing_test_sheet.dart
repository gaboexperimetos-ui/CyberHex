import 'package:material_ui/material_ui.dart';

import '../core/eq_presets.dart';
import '../core/player_controller.dart';
import '../theme.dart';

/// Prueba de audición por bandas, sin generador de tonos.
///
/// El núcleo no expone un oscilador, así que se usa lo que esté sonando: para
/// cada banda se deja **solo** esa banda al máximo (+12 dB) y el resto a −18 dB,
/// y se pregunta si se oye. Es la misma idea de una audiometría de barrido, pero
/// con música en vez de un tono puro; sirve para detectar bandas muertas y
/// generar una curva de compensación suave (`EqPreset.compensationFrom`).
///
/// El ecualizador se **restaura** al salir, pase lo que pase (`dispose`).
class HearingTestSheet extends StatefulWidget {
  const HearingTestSheet({super.key, required this.controller});

  final PlayerController controller;

  static Future<void> show(BuildContext context, PlayerController controller) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => HearingTestSheet(controller: controller),
    );
  }

  @override
  State<HearingTestSheet> createState() => _HearingTestSheetState();
}

class _HearingTestSheetState extends State<HearingTestSheet> {
  /// Bandas elegidas para la prueba (las 10 más representativas de 36).
  static const List<int> _testBands = <int>[
    0,
    4,
    8,
    12,
    16,
    20,
    24,
    28,
    32,
    35,
  ];

  late List<double> _original;
  late List<bool> _heard;
  int _step = 0;
  bool _finished = false;

  /// Si el usuario aplicó la compensación, la hoja no debe deshacerla al cerrar.
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    _original = List<double>.of(widget.controller.eqGains);
    _heard = List<bool>.filled(widget.controller.eqGains.length, false);
    _solo();
  }

  @override
  void dispose() {
    // Nunca dejar el EQ deformado por una prueba a medias… salvo que el usuario
    // haya aceptado la compensación.
    if (!_applied) _restore();
    super.dispose();
  }

  void _restore() {
    final gains = widget.controller.eqGains;
    for (var i = 0; i < gains.length && i < _original.length; i++) {
      widget.controller.setBand(i, _original[i]);
    }
  }

  /// Deja solo la banda del paso actual audible.
  void _solo() {
    final gains = widget.controller.eqGains;
    final band = _testBands[_step];
    for (var i = 0; i < gains.length; i++) {
      widget.controller.setBand(i, i == band ? 12 : -18);
    }
  }

  void _answer(bool heard) {
    _heard[_testBands[_step]] = heard;
    if (_step + 1 >= _testBands.length) {
      _restore();
      setState(() => _finished = true);
      return;
    }
    setState(() => _step += 1);
    _solo();
  }

  void _applyCompensation() {
    final preset = EqPreset.compensationFrom(
      frequencies: widget.controller.eqBandFrequencies,
      heard: _heard,
    );
    applyEqPreset(widget.controller, preset);
    _applied = true;
    Navigator.of(context).maybePop();
  }

  void _cancel() {
    _restore();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final frequencies = widget.controller.eqBandFrequencies;
    final band =
        _testBands[_step < _testBands.length ? _step : _testBands.length - 1];
    final hz = band < frequencies.length ? frequencies[band] : 0.0;
    final missing = _heard.where((value) => !value).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Prueba de audición',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Se aísla una banda cada vez sobre la música que está sonando. '
              'Marca lo que oigas: al final se propone una curva suave.',
              style: TextStyle(fontSize: 12, color: palette.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (!_finished) ...[
              LinearProgressIndicator(
                value: (_step + 1) / _testBands.length,
                minHeight: 4,
                backgroundColor: palette.surfaceHigh,
                color: palette.accent,
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  '${_formatHz(hz)} · ${_step + 1}/${_testBands.length}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: palette.foreground,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '¿Oyes este tono sobre la música?',
                  style: TextStyle(fontSize: 13, color: palette.muted),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _answer(false),
                      icon: const Icon(
                        Icons.hearing_disabled_rounded,
                        size: 18,
                      ),
                      label: const Text('No lo oigo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.muted,
                        side: BorderSide(color: palette.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _answer(true),
                      icon: const Icon(Icons.hearing_rounded, size: 18),
                      label: const Text('Lo oigo'),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Icon(Icons.check_circle_rounded, size: 44, color: palette.accent),
              const SizedBox(height: 10),
              Text(
                missing == 0
                    ? 'Has oído todas las bandas: no hace falta compensar nada.'
                    : 'No has oído $missing de ${_testBands.length} bandas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: palette.foreground),
              ),
              const SizedBox(height: 6),
              Text(
                'La compensación es suave (+12 dB como mucho en las bandas '
                'perdidas) y se puede deshacer con el preset Plano.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: palette.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              if (missing > 0)
                FilledButton.icon(
                  onPressed: _applyCompensation,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Aplicar «Mi oído»'),
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.onAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _cancel,
                child: const Text('Salir sin cambios'),
              ),
            ],
            if (!_finished) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _cancel,
                child: const Text('Cancelar (restaura el EQ)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatHz(double hz) {
    if (!hz.isFinite || hz <= 0) return '—';
    if (hz >= 1000) {
      final k = hz / 1000;
      final text = k >= 10 ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text} kHz';
    }
    return '${hz.round()} Hz';
  }
}

/// Aplica un preset banda a banda (el contrato expone `set_band_gain`, no un
/// volcado en bloque desde la UI).
void applyEqPreset(PlayerController controller, EqPreset preset) {
  final frequencies = controller.eqBandFrequencies;
  final gains = preset.gainsFor(frequencies);
  for (var i = 0; i < gains.length; i++) {
    controller.setBand(i, gains[i]);
  }
}

/// Texto corto de la curva, para depurar y para los tests.
String describeEqPreset(EqPreset preset, List<double> frequencies) {
  final gains = preset.gainsFor(frequencies);
  final parts = <String>[
    for (var i = 0; i < gains.length; i += 6)
      '${frequencies[i].round()}Hz:${gains[i].toStringAsFixed(1)}',
  ];
  return '${preset.name} (${parts.join(', ')})';
}

/// Ayuda para la UI: nombre legible de una banda.
String bandLabel(List<double> frequencies, int index) {
  if (index < 0 || index >= frequencies.length) return '';
  final hz = frequencies[index];
  if (hz >= 1000) {
    return '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k';
  }
  return hz.round().toString();
}
