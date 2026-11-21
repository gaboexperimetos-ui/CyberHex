import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../theme.dart';
import 'library_page.dart';
import 'queue_sheet.dart';
import 'eq_sheet.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0;
  bool _dragging = false;

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  PlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncSpin);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncSpin);
    _spin.dispose();
    super.dispose();
  }

  /// El disco solo gira con audio sonando y sin carátula (arte estático).
  void _syncSpin() {
    final snapshot = _controller.snapshot;
    final shouldSpin = snapshot.playing && snapshot.cover == null && !snapshot.busy;
    if (shouldSpin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!shouldSpin && _spin.isAnimating) {
      _spin.stop();
    }
  }

  void _openQueue() => QueueSheet.show(context, _controller);

  void _openLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryPage(controller: _controller),
      ),
    );
  }

  Future<void> _openFile() async {
    if (_controller.snapshot.busy) {
      return;
    }
    const group = XTypeGroup(
      label: 'Audio',
      extensions: ['mp3', 'flac', 'wav', 'ogg', 'opus', 'm4a', 'aac', 'aiff'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) {
      return;
    }
    final error = await _controller.openFile(file.path);
    if (!mounted || error == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error)),
    );
  }

  void _toggle() {
    final snapshot = _controller.snapshot;
    if (snapshot.busy || !snapshot.hasTrack) {
      return;
    }
    _controller.toggle();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.space): _ToggleIntent(),
          },
          child: Actions(
            actions: {
              _ToggleIntent: CallbackAction<_ToggleIntent>(
                onInvoke: (_) {
                  _toggle();
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
                            _Header(
                              onOpen: _openFile,
                              onQueue: _openQueue,
                              onLibrary: _openLibrary,
                            ),
                            const SizedBox(height: 28),
                            RepaintBoundary(
                              child: _Disc(spin: _spin, snapshot: snapshot),
                            ),
                            const SizedBox(height: 28),
                            _TrackInfo(snapshot: snapshot, onOpen: _openFile),
                            const SizedBox(height: 20),
                            _SeekBar(
                              position: _controller.position,
                              snapshot: snapshot,
                              dragging: _dragging,
                              dragPosition: _dragPosition,
                              onChangeStart: (value) => setState(() {
                                _dragging = true;
                                _dragPosition = value;
                              }),
                              onChanged: (value) =>
                                  setState(() => _dragPosition = value),
                              onChangeEnd: (value) {
                                _controller.seek(value);
                                setState(() => _dragging = false);
                              },
                            ),
                            const SizedBox(height: 4),
                            _ModeRow(
                              snapshot: snapshot,
                              onCycleRepeat: _controller.cycleRepeat,
                              onToggleShuffle: _controller.toggleShuffle,
                            ),
                            const SizedBox(height: 4),
                            _Controls(
                              snapshot: snapshot,
                              position: _controller.position,
                              onToggle: _toggle,
                              onSeek: _controller.seek,
                            ),
                            const SizedBox(height: 24),
                            _FooterRow(
                              snapshot: snapshot,
                              onVolume: _controller.setVolume,
                              onEq: () => showModalBottomSheet<void>(
                                context: context,
                                showDragHandle: true,
                                builder: (_) =>
                                    EqualizerSheet(controller: _controller),
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
      },
    );
  }
}

class _ToggleIntent extends Intent {
  const _ToggleIntent();
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onOpen,
    required this.onQueue,
    required this.onLibrary,
  });

  final VoidCallback onOpen;
  final VoidCallback onQueue;
  final VoidCallback onLibrary;

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
          onPressed: onLibrary,
          tooltip: 'Biblioteca',
          icon: const Icon(Icons.library_music_rounded),
        ),
        IconButton(
          onPressed: onQueue,
          tooltip: 'Cola de reproducción',
          icon: const Icon(Icons.queue_music_rounded),
        ),
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
  const _Disc({required this.spin, required this.snapshot});

  final AnimationController spin;
  final PlayerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final image = snapshot.cover;
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
                    color: chAccent.withValues(alpha: snapshot.playing ? 0.28 : 0.10),
                    blurRadius: snapshot.playing ? 70 : 40,
                    spreadRadius: snapshot.playing ? 12 : 4,
                  ),
                ],
              ),
            ),
            if (image != null)
              ClipOval(
                child: Image.memory(
                  image,
                  width: 236,
                  height: 236,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: 472,
                  errorBuilder: (_, __, ___) => _vinyl(reduceMotion),
                ),
              )
            else
              _vinyl(reduceMotion),
            if (snapshot.busy)
              Container(
                width: 236,
                height: 236,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xAA0F0F23),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _vinyl(bool reduceMotion) {
    return RotationTransition(
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
              snapshot.hasTrack
                  ? Icons.graphic_eq_rounded
                  : Icons.music_note_rounded,
              size: 34,
              color: snapshot.hasTrack ? chAccent : chMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.snapshot, required this.onOpen});

  final PlayerSnapshot snapshot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (!snapshot.hasTrack) {
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

    final subtitle = [snapshot.artist, snapshot.album]
        .where((part) => part.isNotEmpty)
        .join(' · ');
    return Column(
      children: [
        Text(
          snapshot.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: chForeground, fontSize: 13),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          '${_clock(snapshot.duration)} · motor nativo 48 kHz',
          style: const TextStyle(color: chMuted, fontSize: 12, letterSpacing: 0.4),
        ),
      ],
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.position,
    required this.snapshot,
    required this.dragging,
    required this.dragPosition,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final ValueListenable<double> position;
  final PlayerSnapshot snapshot;
  final bool dragging;
  final double dragPosition;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final duration = math.max(snapshot.duration, 0.001);
    final enabled = snapshot.hasTrack && !snapshot.busy;
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
                value: current.toDouble(),
                max: duration,
                onChangeStart: enabled ? onChangeStart : null,
                onChanged: enabled ? onChanged : null,
                onChangeEnd: enabled ? onChangeEnd : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_clock(current.toDouble()),
                      style: const TextStyle(fontSize: 11, color: chMuted)),
                  Text(
                    snapshot.hasTrack ? _clock(snapshot.duration) : '--:--',
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

/// Aleatorio y repetición, con el estado escrito para que no haya dudas:
/// "Aleatorio: sí / no" y "Repetir: no / todo / una".
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.snapshot,
    required this.onCycleRepeat,
    required this.onToggleShuffle,
  });

  final PlayerSnapshot snapshot;
  final VoidCallback onCycleRepeat;
  final VoidCallback onToggleShuffle;

  @override
  Widget build(BuildContext context) {
    final shuffle = snapshot.shuffle;
    final repeat = snapshot.repeatMode;
    final repeatLabel = switch (repeat) {
      1 => 'Repetir: todo',
      2 => 'Repetir: una',
      _ => 'Repetir: no',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ModeButton(
          icon: Icons.shuffle_rounded,
          label: shuffle ? 'Aleatorio: sí' : 'Aleatorio: no',
          active: shuffle,
          tooltip: shuffle
              ? 'Aleatorio activado (toca para desactivar)'
              : 'Aleatorio desactivado (toca para activar)',
          onPressed: onToggleShuffle,
        ),
        const SizedBox(width: 10),
        _ModeButton(
          icon: repeat == 2 ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          label: repeatLabel,
          active: repeat != 0,
          tooltip: switch (repeat) {
            1 => 'Repetir todo (toca para repetir una sola)',
            2 => 'Repetir una (toca para apagar)',
            _ => 'Repetición apagada (toca para repetir todo)',
          },
          onPressed: onCycleRepeat,
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = active ? chAccent : chMuted;
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: color),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        style: TextButton.styleFrom(
          backgroundColor:
              active ? chAccent.withValues(alpha: 0.14) : Colors.transparent,
          foregroundColor: color,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(color: active ? chAccent : chBorder),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.snapshot,
    required this.position,
    required this.onToggle,
    required this.onSeek,
  });

  final PlayerSnapshot snapshot;
  final ValueListenable<double> position;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final enabled = snapshot.hasTrack && !snapshot.busy;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed:
              enabled ? () => onSeek(math.max(position.value - 10, 0)) : null,
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
              snapshot.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 42,
            ),
          ),
        ),
        const SizedBox(width: 18),
        IconButton(
          onPressed: enabled
              ? () => onSeek(math.min(position.value + 10, snapshot.duration))
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
    required this.snapshot,
    required this.onVolume,
    required this.onEq,
  });

  final PlayerSnapshot snapshot;
  final ValueChanged<double> onVolume;
  final VoidCallback onEq;

  @override
  Widget build(BuildContext context) {
    final volume = snapshot.volume;
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

String _clock(double seconds) {
  final total = seconds.isFinite ? seconds.floor() : 0;
  final minutes = total ~/ 60;
  final rest = total % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
