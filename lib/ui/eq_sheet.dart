import 'package:material_ui/material_ui.dart';

import '../core/eq_presets.dart';
import '../core/player_controller.dart';
import '../theme.dart';
import 'hearing_test_sheet.dart';

/// Ecualizador real del núcleo: 36 bandas logarítmicas de 20 Hz a 20 kHz,
/// con ±18 dB de recorrido. Las etiquetas salen de `ch_engine_eq_band_freq`,
/// no de una tabla fija, para que no vuelvan a desincronizarse.
class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  static const double _bandWidth = 36;

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gains = widget.controller.eqGains;
    final frequencies = widget.controller.eqBandFrequencies;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ecualizador',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(widget.controller.resetEq),
                  child: const Text('Plano'),
                ),
              ],
            ),
            Text(
              '${gains.length} bandas · 20 Hz – 20 kHz · ±18 dB',
              style: const TextStyle(fontSize: 12, color: chMuted),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: eqPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final preset = eqPresets[index];
                  return ActionChip(
                    label: Text(
                      preset.name,
                      style: const TextStyle(fontSize: 11),
                    ),
                    tooltip: preset.description,
                    backgroundColor: chSurfaceHigh,
                    side: const BorderSide(color: chBorder),
                    onPressed: () {
                      applyEqPreset(widget.controller, preset);
                      setState(() {});
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await HearingTestSheet.show(context, widget.controller);
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.hearing_rounded, size: 16),
                label: const Text(
                  'Prueba de audición',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ),
            SizedBox(
              height: 236,
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < gains.length; i++)
                        SizedBox(
                          width: _bandWidth,
                          child: _Band(
                            label: _formatHz(frequencies[i]),
                            value: gains[i],
                            onChanged: (value) =>
                                setState(() => widget.controller.setBand(i, value)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Desliza en horizontal para recorrer todo el espectro.',
              style: const TextStyle(fontSize: 11, color: chMuted),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatHz(double hz) {
  if (!hz.isFinite || hz <= 0) return '';
  if (hz >= 1000) {
    final k = hz / 1000;
    final digits = k >= 10 ? 0 : 1;
    final text = k.toStringAsFixed(digits);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}k';
  }
  return hz.round().toString();
}

class _Band extends StatelessWidget {
  const _Band({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 14,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value.abs() < 0.05 ? '' : value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 10, color: chMuted),
            ),
          ),
        ),
        SizedBox(
          height: 168,
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: value.clamp(-18, 18).toDouble(),
              min: -18,
              max: 18,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          height: 14,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(fontSize: 9, color: chMuted),
            ),
          ),
        ),
      ],
    );
  }
}
