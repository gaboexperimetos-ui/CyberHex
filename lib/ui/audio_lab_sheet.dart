import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../core/eq_presets.dart';
import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../theme.dart';
import 'eq_sheet.dart';
import 'hearing_test_sheet.dart';
import 'kit/ch_kit.dart';
import 'visualizer_widget.dart';

/// Laboratorio de audio: todo el DSP del núcleo en una hoja, con los valores a
/// la vista.
///
/// Se organiza en secciones plegables para que la hoja no sea un muro de
/// controles: espacial (9D, ancho, crossfeed, karaoke, noche), mezcla (balance,
/// mono/swap, ReplayGain, velocidad y tono, S16), avance (crossfade, gapless,
/// loop A-B, temporizador), paisaje sonoro y herramientas (BPM, exportar WAV,
/// marcadores, prueba de audición).
class AudioLabSheet extends StatefulWidget {
  const AudioLabSheet({super.key, required this.controller});

  final PlayerController controller;

  static Future<void> show(BuildContext context, PlayerController controller) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AudioLabSheet(controller: controller),
    );
  }

  @override
  State<AudioLabSheet> createState() => _AudioLabSheetState();
}

class _AudioLabSheetState extends State<AudioLabSheet> {
  VisualizerStyle _style = VisualizerStyle.bars;
  double? _bpm;
  bool _bpmBusy = false;
  String? _status;

  PlayerController get _controller => widget.controller;

  void _say(String message) => setState(() => _status = message);

  Future<void> _detectBpm() async {
    final snapshot = _controller.snapshot;
    final index = snapshot.queueIndex;
    final path = index >= 0 && index < snapshot.queue.length
        ? snapshot.queue[index].path
        : '';
    if (path.isEmpty) {
      _say('No hay pista cargada para analizar.');
      return;
    }
    setState(() {
      _bpmBusy = true;
      _status = null;
    });
    final value = await _controller.detectBpm(path);
    if (!mounted) return;
    setState(() {
      _bpmBusy = false;
      _bpm = value;
      _status = value <= 0
          ? 'Sin pulso claro en los primeros 30 s.'
          : '≈ ${value.toStringAsFixed(1)} BPM';
    });
  }

  Future<void> _export() async {
    final snapshot = _controller.snapshot;
    final index = snapshot.queueIndex;
    final path = index >= 0 && index < snapshot.queue.length
        ? snapshot.queue[index].path
        : '';
    if (path.isEmpty) {
      _say('Abre una pista antes de exportar.');
      return;
    }
    const group = XTypeGroup(label: 'WAV', extensions: <String>['wav']);
    final location = await getSaveLocation(
      suggestedName: 'cyberhex_export.wav',
      acceptedTypeGroups: const <XTypeGroup>[group],
    );
    if (location == null || !mounted) return;
    setState(() => _status = 'Exportando…');
    final ok = await _controller.renderWav(path, location.path, withDsp: true);
    if (!mounted) return;
    setState(() {
      _status = ok
          ? 'Exportado con tu DSP: ${location.path}'
          : _controller.snapshot.error ?? 'No se pudo exportar.';
    });
  }

  Future<void> _openCue() async {
    const group = XTypeGroup(label: 'Hoja CUE', extensions: <String>['cue']);
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null || !mounted) return;
    final tracks = _controller.readCue(file.path);
    if (!mounted) return;
    if (tracks.isEmpty) {
      _say('La hoja no tiene cortes válidos.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CueList(tracks: tracks, controller: _controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final snapshot = _controller.snapshot;
          final palette = paletteOf(context);
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChSheetHeader(
                    icon: Icons.science_rounded,
                    title: 'Laboratorio de audio',
                    palette: palette,
                    subtitle: snapshot.hasTrack
                        ? snapshot.title
                        : 'Todo el DSP del motor, con los valores a la vista',
                    trailing: IconButton(
                      tooltip: _style.next == VisualizerStyle.hexagon
                          ? 'Cambiar a hexágonos'
                          : 'Cambiar a barras',
                      onPressed: () => setState(() => _style = _style.next),
                      icon: Icon(
                        _style == VisualizerStyle.bars
                            ? Icons.equalizer_rounded
                            : Icons.hexagon_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(height: ChSpace.md),
                  VisualizerWidget(
                    controller: _controller,
                    style: _style,
                    height: 140,
                  ),
                  const SizedBox(height: 18),
                  _Section(
                    title: 'Espacial',
                    initiallyOpen: true,
                    children: [
                      _ToggleRow(
                        label: 'Audio 9D',
                        subtitle: 'El frente gira alrededor de la cabeza',
                        value: snapshot.nineDEnabled,
                        onChanged: (value) => _controller.set9D(enabled: value),
                      ),
                      _SliderRow(
                        label: 'Velocidad del giro',
                        value: snapshot.nineDSpeed,
                        min: 0.05,
                        max: 2,
                        format: (v) => '${v.toStringAsFixed(2)} vueltas/s',
                        onChanged: (v) => _controller.set9D(speed: v),
                      ),
                      _SliderRow(
                        label: 'Profundidad',
                        value: snapshot.nineDDepth,
                        format: _percent,
                        onChanged: (v) => _controller.set9D(depth: v),
                      ),
                      _SliderRow(
                        label: 'Ancho estéreo',
                        value: snapshot.stereoWidth,
                        min: 0,
                        max: 2,
                        format: (v) => v < 0.95
                            ? '${(v * 100).round()} % (mono)'
                            : v > 1.05
                            ? '${v.toStringAsFixed(2)}× (amplio)'
                            : 'normal',
                        onChanged: (v) =>
                            _controller.setStereoEnhance(width: v),
                      ),
                      _SliderRow(
                        label: 'Punch de graves',
                        value: snapshot.bassPunch,
                        format: _percent,
                        onChanged: (v) =>
                            _controller.setStereoEnhance(bassPunch: v),
                      ),
                      _ToggleRow(
                        label: 'Crossfeed Bauer',
                        subtitle: 'Auriculares: menos fatiga, más natural',
                        value: snapshot.crossfeedEnabled,
                        onChanged: (value) =>
                            _controller.setCrossfeed(enabled: value),
                      ),
                      _SliderRow(
                        label: 'Crossfeed',
                        value: snapshot.crossfeedLevel,
                        format: _percent,
                        onChanged: (v) => _controller.setCrossfeed(level: v),
                      ),
                      _SliderRow(
                        label: 'Karaoke (voz fuera)',
                        value: snapshot.vocalCut,
                        format: (v) => v <= 0 ? 'apagado' : _percent(v),
                        onChanged: _controller.setVocalCut,
                      ),
                      _ToggleRow(
                        label: 'Modo noche',
                        subtitle: 'Sube los pasajes flojos, doma los picos',
                        value: snapshot.nightModeEnabled,
                        onChanged: (value) =>
                            _controller.setNightMode(enabled: value),
                      ),
                      _SliderRow(
                        label: 'Compresión de noche',
                        value: snapshot.nightModeAmount,
                        format: _percent,
                        onChanged: (v) => _controller.setNightMode(amount: v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Section(
                    title: 'Mezcla y motor',
                    children: [
                      _SliderRow(
                        label: 'Balance',
                        value: _controller.balance,
                        min: -1,
                        max: 1,
                        format: (v) => v.abs() < 0.02
                            ? 'centro'
                            : v < 0
                            ? 'izquierda ${(v.abs() * 100).round()} %'
                            : 'derecha ${(v * 100).round()} %',
                        onChanged: _controller.setBalance,
                      ),
                      _ChoiceRow<int>(
                        label: 'Canales',
                        options: const <int>[0, 1, 2],
                        value: _choice(0, const <int>[0, 1, 2]),
                        labels: const <String>[
                          'Estéreo',
                          'Mono',
                          'Intercambiado',
                        ],
                        onSelected: _controller.setChannelMode,
                      ),
                      _ToggleRow(
                        label: 'ReplayGain',
                        subtitle: 'Normaliza el volumen entre pistas',
                        value: _controller.replayGainEnabled,
                        onChanged: _controller.setReplayGain,
                      ),
                      _ToggleRow(
                        label: 'ReplayGain por álbum',
                        value: _controller.replayGainAlbum,
                        onChanged: _controller.setReplayGainAlbum,
                      ),
                      _SliderRow(
                        label: 'Velocidad',
                        value: _controller.speed,
                        min: 0.25,
                        max: 4,
                        format: (v) => '${v.toStringAsFixed(2)}×',
                        onChanged: _controller.setSpeed,
                      ),
                      _SliderRow(
                        label: 'Tono',
                        value: _controller.pitch,
                        min: -12,
                        max: 12,
                        format: (v) =>
                            '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} semitonos',
                        onChanged: _controller.setPitch,
                      ),
                      _ToggleRow(
                        label: 'Salida S16 con dither',
                        subtitle: 'Reabre el dispositivo (audio «de CD»)',
                        value: snapshot.s16Output,
                        onChanged: _controller.setS16Output,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Section(
                    title: 'Avance y temporizador',
                    children: [
                      _SliderRow(
                        label: 'Crossfade',
                        value: _controller.crossfade,
                        min: 0,
                        max: 12,
                        format: (v) =>
                            v <= 0 ? 'apagado' : '${v.toStringAsFixed(1)} s',
                        onChanged: _controller.setCrossfade,
                      ),
                      _ToggleRow(
                        label: 'Gapless',
                        subtitle: 'Sin hueco entre pistas',
                        value: _controller.gapless,
                        onChanged: _controller.setGapless,
                      ),
                      _LoopRow(controller: _controller),
                      _SleepRow(controller: _controller),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Section(
                    title: 'Paisaje sonoro',
                    children: [
                      _ChoiceRow<SoundscapePreset>(
                        label: 'Fondo',
                        options: SoundscapePreset.values,
                        value: _controller.soundscape,
                        labels: const <String>[
                          'Ninguno',
                          'Lluvia',
                          'Marrón',
                          'Vinilo',
                        ],
                        onSelected: (preset) => _controller.setSoundscape(
                          preset,
                          level: preset == SoundscapePreset.off ? 0 : null,
                        ),
                      ),
                      _SliderRow(
                        label: 'Nivel del paisaje',
                        value: _controller.soundscapeLevel,
                        format: _percent,
                        onChanged: (v) => _controller.setSoundscape(
                          _controller.soundscape,
                          level: v,
                        ),
                      ),
                      const Text(
                        'Se mezcla bajo la música antes del limitador: nunca tapa '
                        'la pista y no cuesta nada cuando está apagado.',
                        style: TextStyle(fontSize: 11, height: 1.4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _Section(
                    title: 'Herramientas',
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              showDragHandle: true,
                              builder: (_) =>
                                  EqualizerSheet(controller: _controller),
                            ),
                            icon: const Icon(Icons.equalizer_rounded, size: 18),
                            label: const Text('EQ de 36 bandas'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                HearingTestSheet.show(context, _controller),
                            icon: const Icon(Icons.hearing_rounded, size: 18),
                            label: const Text('Prueba de audición'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _bpmBusy ? null : _detectBpm,
                            icon: _bpmBusy
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.speed_rounded, size: 18),
                            label: Text(
                              _bpm == null || _bpm! <= 0
                                  ? 'Detectar BPM'
                                  : '${_bpm!.toStringAsFixed(0)} BPM',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _export,
                            icon: const Icon(Icons.save_alt_rounded, size: 18),
                            label: const Text('Exportar WAV'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _openCue,
                            icon: const Icon(
                              Icons.playlist_play_rounded,
                              size: 18,
                            ),
                            label: const Text('Abrir .cue'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              final ok = _controller.addMarkerHere();
                              _say(
                                ok
                                    ? 'Marca puesta en la posición actual.'
                                    : 'Abre una pista para poner marcas.',
                              );
                            },
                            icon: const Icon(
                              Icons.bookmark_add_rounded,
                              size: 18,
                            ),
                            label: const Text('Marcar aquí'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              applyEqPreset(_controller, _pickPreset());
                            },
                            icon: const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                            ),
                            label: const Text('Preset de EQ'),
                          ),
                        ],
                      ),
                      if (_status != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _status!,
                          style: TextStyle(fontSize: 12, color: palette.accent),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  int _choice(int fallback, List<int> allowed) {
    final value = _controller.channelMode;
    return allowed.contains(value) ? value : fallback;
  }

  EqPreset _pickPreset() {
    // Sin diálogo modal: el botón recorre los presets en orden, que es más
    // rápido con una mano y no bloquea la hoja.
    final index = _presetCursor % eqPresets.length;
    _presetCursor = (index + 1) % eqPresets.length;
    final preset = eqPresets[index];
    _say('Preset: ${preset.name} — ${preset.description}');
    return preset;
  }

  int _presetCursor = 1; // el 0 es «Plano»
}

/// Porcentaje legible: 0 % .. 100 %.
String _percent(double value) => '${(value * 100).round()} %';

class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.children,
    this.initiallyOpen = false,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyOpen;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    // `Material` y no `Container`: el `ListTile` pinta su fondo y sus ondas en
    // el `Material` más cercano; con un `DecoratedBox` por medio, Flutter avisa
    // (y en las pruebas eso rompe el test).
    return Material(
      color: palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            trailing: Icon(
              _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: palette.muted,
            ),
            onTap: () => setState(() => _open = !_open),
            dense: true,
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: paletteOf(context).muted),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.format,
    this.min = 0,
    this.max = 1,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String Function(double) format;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(
              format(clamped),
              style: TextStyle(fontSize: 11, color: paletteOf(context).muted),
            ),
          ],
        ),
        Slider(value: clamped, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.options,
    required this.value,
    required this.labels,
    required this.onSelected,
  });

  final String label;
  final List<T> options;
  final T value;
  final List<String> labels;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var i = 0; i < options.length; i++)
                ChoiceChip(
                  label: Text(
                    i < labels.length ? labels[i] : '${options[i]}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: options[i] == value,
                  onSelected: (_) => onSelected(options[i]),
                  selectedColor: palette.accent.withValues(alpha: 0.22),
                  backgroundColor: palette.surfaceHigh,
                  side: BorderSide(
                    color: options[i] == value
                        ? palette.accent
                        : palette.border,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Loop A-B: marca A y B en la posición actual y permite quitarlo.
class _LoopRow extends StatelessWidget {
  const _LoopRow({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.loopActive;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Loop A-B', style: TextStyle(fontSize: 13)),
              ),
              Text(
                active
                    ? '${controller.loopStart.toStringAsFixed(1)} – '
                          '${controller.loopEnd.toStringAsFixed(1)} s'
                    : 'apagado',
                style: TextStyle(fontSize: 11, color: paletteOf(context).muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () {
                  final a = controller.loopStart;
                  final b = controller.position.value;
                  if (b > a) {
                    controller.setLoop(a, b);
                  } else {
                    controller.setLoop(b, b + 15);
                  }
                },
                child: Text(active ? 'Mover B aquí' : 'Marcar A-B'),
              ),
              if (active)
                TextButton(
                  onPressed: controller.clearLoop,
                  child: const Text('Quitar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Temporizador de apagado con atajos de 15/30/60 minutos.
class _SleepRow extends StatefulWidget {
  const _SleepRow({required this.controller});

  final PlayerController controller;

  @override
  State<_SleepRow> createState() => _SleepRowState();
}

class _SleepRowState extends State<_SleepRow> {
  @override
  Widget build(BuildContext context) {
    final remaining = widget.controller.sleepRemaining;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Temporizador', style: TextStyle(fontSize: 13)),
              ),
              Text(
                remaining > 0 ? '${(remaining / 60).ceil()} min' : 'apagado',
                style: TextStyle(fontSize: 11, color: paletteOf(context).muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: <Widget>[
              for (final minutes in const <int>[15, 30, 60])
                OutlinedButton(
                  onPressed: () {
                    widget.controller.setSleepTimer(minutes * 60.0);
                    setState(() {});
                  },
                  child: Text('$minutes min'),
                ),
              if (remaining > 0)
                TextButton(
                  onPressed: () {
                    widget.controller.setSleepTimer(0);
                    setState(() {});
                  },
                  child: const Text('Cancelar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cortes de una hoja `.cue`, con la duración de cada uno.
class _CueList extends StatelessWidget {
  const _CueList({required this.tracks, required this.controller});

  final List<CueTrack> tracks;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '${tracks.length} cortes',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final duration = track.duration;
                  return ListTile(
                    dense: true,
                    leading: Text(
                      '${track.number}',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                    title: Text(
                      track.label,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${_time(track.start)}'
                      '${duration > 0 ? ' · ${duration.toStringAsFixed(0)} s' : ''}',
                      style: TextStyle(fontSize: 11, color: palette.muted),
                    ),
                    onTap: track.file.isEmpty
                        ? null
                        : () async {
                            await controller.openFile(track.file);
                            controller.seek(track.start);
                            if (context.mounted) {
                              Navigator.of(context).maybePop();
                            }
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(double seconds) {
    final total = seconds.isFinite ? seconds.floor() : 0;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}
