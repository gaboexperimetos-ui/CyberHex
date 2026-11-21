import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../theme.dart';

/// Ajustes de reproducción que el motor ya soporta: velocidad, tono,
/// crossfade, preamp del EQ, mono, limitador, salida de audio y temporizador.
class ToolsSheet extends StatefulWidget {
  const ToolsSheet({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<ToolsSheet> createState() => _ToolsSheetState();
}

class _ToolsSheetState extends State<ToolsSheet> {
  late double _speed;
  late double _pitch;
  late double _crossfade;
  late double _preamp;
  late bool _mono;
  late bool _limiter;

  PlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _speed = c.speed.clamp(0.5, 2.0).toDouble();
    _pitch = c.pitch.clamp(-6.0, 6.0).toDouble();
    _crossfade = c.crossfadeSeconds.clamp(0.0, 12.0).toDouble();
    _preamp = c.eqPreamp.clamp(-24.0, 0.0).toDouble();
    _mono = c.mono;
    _limiter = c.limiter;
  }

  @override
  Widget build(BuildContext context) {
    final devices = _controller.outputDevices;
    final remaining = _controller.sleepRemaining;
    final device = _controller.outputDevice;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Text('Ajustes', style: chDisplay.copyWith(fontSize: 20)),
          const SizedBox(height: 4),
          _LabeledSlider(
            label: 'Velocidad',
            valueLabel: '${_speed.toStringAsFixed(2)}x',
            value: _speed,
            min: 0.5,
            max: 2,
            onChanged: (value) {
              setState(() => _speed = value);
              _controller.speed = value;
            },
          ),
          _LabeledSlider(
            label: 'Tono',
            valueLabel: '${_pitch.toStringAsFixed(1)} st',
            value: _pitch,
            min: -6,
            max: 6,
            onChanged: (value) {
              setState(() => _pitch = value);
              _controller.pitch = value;
            },
          ),
          _LabeledSlider(
            label: 'Crossfade',
            valueLabel: '${_crossfade.toStringAsFixed(1)} s',
            value: _crossfade,
            min: 0,
            max: 12,
            onChanged: (value) {
              setState(() => _crossfade = value);
              _controller.crossfadeSeconds = value;
            },
          ),
          _LabeledSlider(
            label: 'Preamp del EQ',
            valueLabel: '${_preamp.toStringAsFixed(0)} dB',
            value: _preamp,
            min: -24,
            max: 0,
            onChanged: (value) {
              setState(() => _preamp = value);
              _controller.eqPreamp = value;
            },
          ),
          SwitchListTile(
            value: _mono,
            onChanged: (value) {
              setState(() => _mono = value);
              _controller.setMono(value);
            },
            title: const Text('Mono'),
            subtitle: const Text('La misma señal en los dos altavoces'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _limiter,
            onChanged: (value) {
              setState(() => _limiter = value);
              _controller.setLimiter(value);
            },
            title: const Text('Limitador de picos'),
            subtitle: const Text('Techo a -1 dBFS'),
            contentPadding: EdgeInsets.zero,
          ),
          if (devices.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Salida de audio'),
                const Spacer(),
                DropdownButton<int>(
                  value: device >= devices.length ? -1 : device,
                  items: [
                    const DropdownMenuItem(
                      value: -1,
                      child: Text('Predeterminada'),
                    ),
                    for (var i = 0; i < devices.length; i++)
                      DropdownMenuItem(value: i, child: Text(devices[i])),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {});
                    _controller.outputDevice = value;
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const Text('Temporizador', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final minutes in const [0, 15, 30, 60])
                ChoiceChip(
                  label: Text(minutes == 0 ? 'Apagado' : '$minutes min'),
                  selected: false,
                  onSelected: (_) =>
                      _controller.setSleepTimer(minutes * 60.0),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            remaining > 0
                ? 'Quedan ${remaining.ceil()} s de reproducción'
                : 'Sin temporizador activo',
            style: const TextStyle(color: chMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(
              valueLabel,
              style: const TextStyle(color: chMuted, fontSize: 12),
            ),
          ],
        ),
        Slider(
          value: current,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
