import 'package:material_ui/material_ui.dart';

import '../core/native_player.dart';
import '../theme.dart';

class EqualizerSheet extends StatefulWidget {
  const EqualizerSheet({super.key, required this.player});

  final NativePlayer player;

  @override
  State<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends State<EqualizerSheet> {
  static const _labels = ['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                  onPressed: () => setState(widget.player.resetEq),
                  child: const Text('Plano'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < _labels.length; i++)
                    Expanded(
                      child: _Band(
                        label: _labels[i],
                        value: widget.player.eqGains[i],
                        onChanged: (value) => setState(() => widget.player.setBand(i, value)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Rango ±12 dB · 10 bandas',
              style: TextStyle(fontSize: 12, color: chMuted),
            ),
          ],
        ),
      ),
    );
  }
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
        Text(
          value.abs() < 0.05 ? '' : value.toStringAsFixed(0),
          style: const TextStyle(fontSize: 10, color: chMuted),
        ),
        SizedBox(
          height: 160,
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: value.clamp(-12, 12),
              min: -12,
              max: 12,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: chMuted)),
      ],
    );
  }
}
