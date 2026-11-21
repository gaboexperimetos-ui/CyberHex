import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/native_player.dart';
import '../theme.dart';
import 'eq_sheet.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with SingleTickerProviderStateMixin {
  NativePlayer? _player;
  String? _initError;

  Timer? _poll;
  final _position = ValueNotifier<double>(0);
  double _dragPosition = 0;
  bool _dragging = false;
  double _volume = 1;

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    _player = NativePlayer.open();
    if (_player == null) {
      _initError = NativePlayer.lastCoreError();
    }
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || !(_player?.isPlaying ?? false)) {
      _spin.stop();
    }
  }

  void _tick() {
    final player = _player;
    if (player == null || !mounted) {
      return;
    }
    if (!_dragging) {
      _position.value = player.position;
    }
    if (player.isPlaying && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!player.isPlaying && _spin.isAnimating) {
      _spin.stop();
    }
    setState(() {});
  }

  Future<void> _openFile() async {
    const group = XTypeGroup(
      label: 'Audio',
      extensions: ['mp3', 'flac', 'wav', 'ogg', 'opus', 'm4a', 'aac', 'aiff'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    final player = _player;
    if (file == null || player == null) {
      return;
    }
    final ok = player.load(file.path);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(player.lastError)),
      );
      return;
    }
    _position.value = 0;
    setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _spin.dispose();
    _position.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return _ErrorScreen(message: _initError!);
    }
    final player = _player!;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): _ToggleIntent(),
      },
      child: Actions(
        actions: {
          _ToggleIntent: CallbackAction<_ToggleIntent>(
            onInvoke: (_) {
              player.toggle();
              setState(() {});
              return null;
            },
          ),
        },
        child: Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF141433), chBackground, Color(0xFF090912)],
                stops: [0, 0.45, 1],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(onOpen: _openFile),
                        const SizedBox(height: 28),
                        _Disc(
                          spin: _spin,
                          playing: player.isPlaying,
                          hasTrack: player.hasTrack,
                        ),
                        const SizedBox(height: 28),
                        _TrackInfo(player: player, onOpen: _openFile),
                        const SizedBox(height: 20),
                        _SeekBar(
                          player: player,
                          position: _position,
                          dragging: _dragging,
                          dragPosition: _dragPosition,
                          onChangeStart: (value) => setState(() {
                            _dragging = true;
                            _dragPosition = value;
                          }),
                          onChanged: (value) => setState(() => _dragPosition = value),
                          onChangeEnd: (value) {
                            player.seek(value);
                            _position.value = value;
                            setState(() => _dragging = false);
                          },
                        ),
                        const SizedBox(height: 8),
                        _Controls(
                          player: player,
                          onToggle: () {
                            player.toggle();
                            setState(() {});
                          },
                          onSeek: (value) {
                            player.seek(value);
                            _position.value = player.position;
                          },
                        ),
                        const SizedBox(height: 24),
                        _FooterRow(
                          player: player,
                          volume: _volume,
                          onVolume: (value) {
                            player.setVolume(value);
                            setState(() => _volume = value);
                          },
                          onEq: () => showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            builder: (_) => EqualizerSheet(player: player),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleIntent extends Intent {
  const _ToggleIntent();
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('CYBERHEX', style: TextStyle(
          fontFamily: 'Righteous',
          fontSize: 22,
          letterSpacing: 3,
          color: chForeground,
        )),
        const Spacer(),
        IconButton(
          onPressed: onOpen,
          tooltip: 'Abrir audio',
          icon: const Icon(Icons.folder_open_rounded),
        ),
      ],
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.spin, required this.playing, required this.hasTrack});

  final AnimationController spin;
  final bool playing;
  final bool hasTrack;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Center(
      child: SizedBox(
        width: 260,
        height: 260,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: chAccent.withValues(alpha: playing ? 0.28 : 0.10),
                    blurRadius: playing ? 70 : 40,
                    spreadRadius: playing ? 12 : 4,
                  ),
                ],
              ),
            ),
            RotationTransition(
              turns: reduceMotion ? const AlwaysStoppedAnimation(0.1) : spin,
              child: Container(
                width: 236,
                height: 236,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(
                    colors: [
                      Color(0xFF312E81),
                      Color(0xFF0F0F23),
                      Color(0xFF22C55E),
                      Color(0xFF0F0F23),
                      Color(0xFF312E81),
                    ],
                    stops: [0, 0.3, 0.5, 0.7, 1],
                  ),
                  border: Border.all(color: chBorder, width: 1),
                ),
                child: Center(
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: chBackground,
                      border: Border.all(color: chBorder),
                    ),
                    child: Icon(
                      hasTrack ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
                      size: 34,
                      color: hasTrack ? chAccent : chMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.player, required this.onOpen});

  final NativePlayer player;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (!player.hasTrack) {
      return Column(
        children: [
          const Text(
            'Tu música, en tu máquina',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Righteous', fontSize: 20, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'Abre un archivo de audio y CyberHex lo decodifica con su propio motor en Zig y C23. Nada sale de tu equipo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: chMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Abrir audio'),
            style: FilledButton.styleFrom(
              backgroundColor: chAccent,
              foregroundColor: chOnAccent,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Text(
          player.title ?? '',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          '${player.duration.toStringAsFixed(0)} s · motor nativo 48 kHz',
          style: const TextStyle(color: chMuted, fontSize: 12, letterSpacing: 0.4),
        ),
      ],
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.player,
    required this.position,
    required this.dragging,
    required this.dragPosition,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final NativePlayer player;
  final ValueNotifier<double> position;
  final bool dragging;
  final double dragPosition;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final duration = math.max(player.duration, 0.001);
    return ValueListenableBuilder<double>(
      valueListenable: position,
      builder: (context, value, _) {
        final current = (dragging ? dragPosition : value).clamp(0.0, duration);
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: current,
                max: duration,
                onChangeStart: player.hasTrack ? onChangeStart : null,
                onChanged: player.hasTrack ? onChanged : null,
                onChangeEnd: player.hasTrack ? onChangeEnd : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_clock(current), style: const TextStyle(fontSize: 11, color: chMuted)),
                  Text(
                    player.hasTrack ? _clock(player.duration) : '--:--',
                    style: const TextStyle(fontSize: 11, color: chMuted),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player, required this.onToggle, required this.onSeek});

  final NativePlayer player;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final enabled = player.hasTrack;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: enabled ? () => onSeek(math.max(player.position - 10, 0)) : null,
          tooltip: 'Retroceder 10 s',
          iconSize: 30,
          icon: const Icon(Icons.replay_10_rounded),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 78,
          height: 78,
          child: FilledButton(
            onPressed: enabled ? onToggle : null,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: chAccent,
              foregroundColor: chOnAccent,
              disabledBackgroundColor: chSurfaceHigh,
              padding: EdgeInsets.zero,
            ),
            child: Icon(
              player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 42,
            ),
          ),
        ),
        const SizedBox(width: 18),
        IconButton(
          onPressed: enabled
              ? () => onSeek(math.min(player.position + 10, player.duration))
              : null,
          tooltip: 'Avanzar 10 s',
          iconSize: 30,
          icon: const Icon(Icons.forward_10_rounded),
        ),
      ],
    );
  }
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({
    required this.player,
    required this.volume,
    required this.onVolume,
    required this.onEq,
  });

  final NativePlayer player;
  final double volume;
  final ValueChanged<double> onVolume;
  final VoidCallback onEq;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(
              volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 20,
              color: chMuted,
            ),
            Expanded(
              child: Slider(value: volume, onChanged: onVolume),
            ),
          ],
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: onEq,
          icon: const Icon(Icons.equalizer_rounded, size: 18),
          label: const Text('Ecualizador'),
          style: OutlinedButton.styleFrom(
            foregroundColor: chForeground,
            side: const BorderSide(color: chBorder),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: chError, size: 40),
              const SizedBox(height: 16),
              const Text('No se pudo iniciar el motor de audio',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center,
                  style: const TextStyle(color: chMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

String _clock(double seconds) {
  final total = seconds.isFinite ? seconds.floor() : 0;
  final minutes = total ~/ 60;
  final rest = total % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
