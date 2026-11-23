import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../platform/connections.dart';
import '../platform/playback_session.dart';
import '../theme.dart';
import 'eq_sheet.dart';
import 'library_sheet.dart';
import 'lyrics_sheet.dart';
import 'queue_sheet.dart';
import 'tools_sheet.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.controller,
    this.connections,
    this.session,
  });

  final PlayerController controller;
  final CyberHexConnections? connections;
  final PlaybackSessionPersistence? session;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0;
  bool _dragging = false;
  int _currentIndex = 0;
  List<double> _waveform = const [];
  String? _waveformPath;
  int _waveformGeneration = 0;

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  PlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncPlaybackVisuals);
    _syncPlaybackVisuals();
  }

  @override
  void dispose() {
    _controller.removeListener(_syncPlaybackVisuals);
    _waveformGeneration++;
    _spin.dispose();
    super.dispose();
  }

  void _syncPlaybackVisuals() {
    _syncSpin();
    _syncWaveform();
  }

  /// El disco solo gira con audio sonando y sin carátula (arte estático).
  void _syncSpin() {
    final snapshot = _controller.snapshot;
    final shouldSpin =
        snapshot.playing && snapshot.cover == null && !snapshot.busy;
    if (shouldSpin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!shouldSpin && _spin.isAnimating) {
      _spin.stop();
    }
  }

  void _syncWaveform() {
    final path = _controller.currentTrackPath;
    if (path == _waveformPath) return;
    final hadPreviousPath = _waveformPath != null;
    _waveformPath = path;
    final generation = ++_waveformGeneration;
    if (hadPreviousPath && mounted) {
      setState(() => _waveform = const []);
    }
    if (path.isNotEmpty) unawaited(_loadWaveform(path, generation));
  }

  Future<void> _loadWaveform(String path, int generation) async {
    try {
      final values = await _controller.waveformAsync(path, 160);
      if (!mounted || generation != _waveformGeneration) return;
      setState(() => _waveform = values);
    } on Exception catch (error) {
      debugPrint('CyberHex waveform: $error');
    }
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  void _toggle() {
    final snapshot = _controller.snapshot;
    if (snapshot.busy || !snapshot.hasTrack) {
      return;
    }
    _controller.toggle();
  }

  /// Abre una hoja con el mismo estilo en toda la app.
  void _openSheet(Widget sheet) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => sheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        final width = MediaQuery.sizeOf(context).width;
        final desktop = width >= 840;
        final pages = <Widget>[
          _NowPlayingPage(
            controller: _controller,
            connections: widget.connections,
            session: widget.session,
            waveform: _waveform,
            spin: _spin,
            snapshot: snapshot,
            dragging: _dragging,
            dragPosition: _dragPosition,
            onOpenFile: _openFile,
            onToggle: _toggle,
            onDragStart: (value) => setState(() {
              _dragging = true;
              _dragPosition = value;
            }),
            onDragChanged: (value) => setState(() => _dragPosition = value),
            onDragEnd: (value) {
              _controller.seek(value);
              setState(() => _dragging = false);
            },
            onOpenSheet: _openSheet,
          ),
          LibrarySheet(controller: _controller, fullPage: true),
          QueueSheet(controller: _controller, fullPage: true),
          ToolsSheet(
            controller: _controller,
            connections: widget.connections,
            session: widget.session,
            fullPage: true,
          ),
        ];

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
                    colors: [
                      Color(0xFF141433),
                      chBackground,
                      Color(0xFF090912),
                    ],
                    stops: [0, 0.45, 1],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: desktop
                      ? Row(
                          children: [
                            NavigationRail(
                              selectedIndex: _currentIndex,
                              labelType: NavigationRailLabelType.all,
                              onDestinationSelected: (index) =>
                                  setState(() => _currentIndex = index),
                              destinations: const [
                                NavigationRailDestination(
                                  icon: Icon(Icons.play_circle_outline_rounded),
                                  selectedIcon: Icon(
                                    Icons.play_circle_fill_rounded,
                                  ),
                                  label: Text('Ahora'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.library_music_outlined),
                                  selectedIcon: Icon(
                                    Icons.library_music_rounded,
                                  ),
                                  label: Text('Biblioteca'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.queue_music_outlined),
                                  selectedIcon: Icon(Icons.queue_music_rounded),
                                  label: Text('Cola'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.tune_outlined),
                                  selectedIcon: Icon(Icons.tune_rounded),
                                  label: Text('Ajustes'),
                                ),
                              ],
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: IndexedStack(
                                index: _currentIndex,
                                children: pages,
                              ),
                            ),
                          ],
                        )
                      : IndexedStack(index: _currentIndex, children: pages),
                ),
              ),
              bottomNavigationBar: desktop
                  ? null
                  : _MobileShellBar(
                      snapshot: snapshot,
                      controller: _controller,
                      selectedIndex: _currentIndex,
                      onSelected: (index) =>
                          setState(() => _currentIndex = index),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _NowPlayingPage extends StatelessWidget {
  const _NowPlayingPage({
    required this.controller,
    required this.connections,
    required this.session,
    required this.waveform,
    required this.spin,
    required this.snapshot,
    required this.dragging,
    required this.dragPosition,
    required this.onOpenFile,
    required this.onToggle,
    required this.onDragStart,
    required this.onDragChanged,
    required this.onDragEnd,
    required this.onOpenSheet,
  });

  final PlayerController controller;
  final CyberHexConnections? connections;
  final PlaybackSessionPersistence? session;
  final List<double> waveform;
  final AnimationController spin;
  final PlayerSnapshot snapshot;
  final bool dragging;
  final double dragPosition;
  final VoidCallback onOpenFile;
  final VoidCallback onToggle;
  final ValueChanged<double> onDragStart;
  final ValueChanged<double> onDragChanged;
  final ValueChanged<double> onDragEnd;
  final void Function(Widget sheet) onOpenSheet;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(onOpen: onOpenFile),
              const SizedBox(height: 28),
              RepaintBoundary(
                child: _Disc(spin: spin, snapshot: snapshot),
              ),
              const SizedBox(height: 28),
              _TrackInfo(snapshot: snapshot, onOpen: onOpenFile),
              const SizedBox(height: 12),
              _SpectrumBars(controller: controller, playing: snapshot.playing),
              const SizedBox(height: 8),
              _SeekBar(
                position: controller.position,
                snapshot: snapshot,
                waveform: waveform,
                dragging: dragging,
                dragPosition: dragPosition,
                onChangeStart: onDragStart,
                onChanged: onDragChanged,
                onChangeEnd: onDragEnd,
              ),
              const SizedBox(height: 8),
              _Controls(
                snapshot: snapshot,
                position: controller.position,
                onToggle: onToggle,
                onPrevious: controller.previous,
                onNext: controller.next,
                onSeek: controller.seek,
              ),
              const SizedBox(height: 24),
              _FooterRow(
                snapshot: snapshot,
                onVolume: controller.setVolume,
                onLibrary: () =>
                    onOpenSheet(LibrarySheet(controller: controller)),
                onEq: () => onOpenSheet(EqualizerSheet(controller: controller)),
                onQueue: () => onOpenSheet(QueueSheet(controller: controller)),
                onLyrics: () =>
                    onOpenSheet(LyricsSheet(controller: controller)),
                onTools: () => onOpenSheet(
                  ToolsSheet(
                    controller: controller,
                    connections: connections,
                    session: session,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileShellBar extends StatelessWidget {
  const _MobileShellBar({
    required this.snapshot,
    required this.controller,
    required this.selectedIndex,
    required this.onSelected,
  });

  final PlayerSnapshot snapshot;
  final PlayerController controller;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ColoredBox(
        color: chBackground,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (snapshot.hasTrack)
              Container(
                height: 68,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                decoration: BoxDecoration(
                  color: chSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: chBorder),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: snapshot.cover == null
                          ? Container(
                              width: 52,
                              height: 52,
                              color: chPrimary,
                              child: const Icon(
                                Icons.graphic_eq_rounded,
                                color: chAccent,
                              ),
                            )
                          : Image.memory(
                              snapshot.cover!,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            snapshot.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (snapshot.artist.isNotEmpty)
                            Text(
                              snapshot.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: chMuted,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: snapshot.busy ? null : controller.toggle,
                      tooltip: snapshot.playing ? 'Pausar' : 'Reproducir',
                      icon: Icon(
                        snapshot.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    IconButton(
                      onPressed: snapshot.busy ? null : controller.next,
                      tooltip: 'Siguiente',
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              height: 66,
              backgroundColor: chBackground,
              indicatorColor: chAccent.withValues(alpha: 0.16),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.play_circle_outline_rounded),
                  selectedIcon: Icon(Icons.play_circle_fill_rounded),
                  label: 'Ahora',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: 'Biblioteca',
                ),
                NavigationDestination(
                  icon: Icon(Icons.queue_music_outlined),
                  selectedIcon: Icon(Icons.queue_music_rounded),
                  label: 'Cola',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune_rounded),
                  label: 'Ajustes',
                ),
              ],
            ),
          ],
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
        const Text(
          'CYBERHEX',
          style: TextStyle(
            fontFamily: 'Righteous',
            fontSize: 22,
            letterSpacing: 3,
            color: chForeground,
          ),
        ),
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
                    color: chAccent.withValues(
                      alpha: snapshot.playing ? 0.28 : 0.10,
                    ),
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
                  errorBuilder: (_, _, _) => _vinyl(reduceMotion),
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
            style: TextStyle(
              fontFamily: 'Righteous',
              fontSize: 20,
              letterSpacing: 0.5,
            ),
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

    final subtitle = [
      snapshot.artist,
      snapshot.album,
    ].where((part) => part.isNotEmpty).join(' · ');
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
          style: const TextStyle(
            color: chMuted,
            fontSize: 12,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.position,
    required this.snapshot,
    required this.waveform,
    required this.dragging,
    required this.dragPosition,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final ValueListenable<double> position;
  final PlayerSnapshot snapshot;
  final List<double> waveform;
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
        final progress = (current / duration).clamp(0.0, 1.0).toDouble();
        return Column(
          children: [
            if (waveform.isEmpty)
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  value: current.toDouble(),
                  max: duration,
                  onChangeStart: enabled ? onChangeStart : null,
                  onChanged: enabled ? onChanged : null,
                  onChangeEnd: enabled ? onChangeEnd : null,
                ),
              )
            else
              SizedBox(
                height: 48,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(painter: _WaveformPainter(waveform, progress)),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: Slider(
                        value: current.toDouble(),
                        max: duration,
                        onChangeStart: enabled ? onChangeStart : null,
                        onChanged: enabled ? onChanged : null,
                        onChangeEnd: enabled ? onChangeEnd : null,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _clock(current.toDouble()),
                    style: const TextStyle(fontSize: 11, color: chMuted),
                  ),
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

class _Controls extends StatelessWidget {
  const _Controls({
    required this.snapshot,
    required this.position,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
  });

  final PlayerSnapshot snapshot;
  final ValueListenable<double> position;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final enabled = snapshot.hasTrack && !snapshot.busy;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: enabled ? onPrevious : null,
          tooltip: 'Pista anterior',
          iconSize: 30,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: enabled
              ? () => onSeek(math.max(position.value - 10, 0))
              : null,
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
        const SizedBox(width: 8),
        IconButton(
          onPressed: enabled ? onNext : null,
          tooltip: 'Pista siguiente',
          iconSize: 30,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({
    required this.snapshot,
    required this.onVolume,
    required this.onLibrary,
    required this.onEq,
    required this.onQueue,
    required this.onLyrics,
    required this.onTools,
  });

  final PlayerSnapshot snapshot;
  final ValueChanged<double> onVolume;
  final VoidCallback onLibrary;
  final VoidCallback onEq;
  final VoidCallback onQueue;
  final VoidCallback onLyrics;
  final VoidCallback onTools;

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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _SheetButton(
              icon: Icons.library_music_rounded,
              label: 'Biblioteca',
              onTap: onLibrary,
            ),
            _SheetButton(
              icon: Icons.equalizer_rounded,
              label: 'Ecualizador',
              onTap: onEq,
            ),
            _SheetButton(
              icon: Icons.queue_music_rounded,
              label: 'Cola',
              onTap: onQueue,
            ),
            _SheetButton(
              icon: Icons.text_snippet_rounded,
              label: 'Letra',
              onTap: onLyrics,
            ),
            _SheetButton(
              icon: Icons.tune_rounded,
              label: 'Ajustes',
              onTap: onTools,
            ),
          ],
        ),
      ],
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: chForeground,
        side: const BorderSide(color: chBorder),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

/// Espectro del audio que suena (post-EQ y post-volumen).
///
/// Se repinta con la posición (12,5 Hz) y no con cada cambio del motor; en
/// pausa se oculta, así no hay trabajo de dibujo sin audio.
class _SpectrumBars extends StatelessWidget {
  const _SpectrumBars({required this.controller, required this.playing});

  final PlayerController controller;
  final bool playing;

  static const int _bands = 28;

  @override
  Widget build(BuildContext context) {
    if (!playing) return const SizedBox(height: 30);
    return SizedBox(
      height: 30,
      child: ValueListenableBuilder<double>(
        valueListenable: controller.position,
        builder: (context, _, _) {
          return CustomPaint(
            size: const Size.fromHeight(30),
            painter: _SpectrumPainter(controller.spectrum(_bands)),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.values, this.progress);

  final List<double> values;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final step = size.width / values.length;
    final barWidth = math.max(1.0, step * 0.62);
    final centerY = size.height / 2;
    final activeUntil = size.width * progress;
    for (var i = 0; i < values.length; i++) {
      final peak = values[i].isFinite
          ? values[i].clamp(0.0, 1.0).toDouble()
          : 0.0;
      final barHeight = math.max(3.0, peak * (size.height * 0.68));
      final left = i * step + (step - barWidth) / 2;
      final paint = Paint()
        ..color = left + barWidth / 2 <= activeUntil
            ? chAccent
            : chMuted.withValues(alpha: 0.55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, centerY - barHeight / 2, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      !listEquals(oldDelegate.values, values);
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final gap = size.width / (values.length * 3);
    final barWidth = gap * 2;
    final paint = Paint()..color = chAccent.withValues(alpha: 0.8);
    for (var i = 0; i < values.length; i++) {
      final level = values[i].clamp(0.0, 1.0).toDouble();
      final barHeight = (level * size.height).clamp(1.5, size.height);
      final left = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          size.height - barHeight,
          left + barWidth,
          size.height,
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      !listEquals(oldDelegate.values, values);
}

String _clock(double seconds) {
  final total = seconds.isFinite ? seconds.floor() : 0;
  final minutes = total ~/ 60;
  final rest = total % 60;
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}
