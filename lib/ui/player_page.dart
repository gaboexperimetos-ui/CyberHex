import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/automix_engine.dart';
import '../core/lyrics_parser.dart';
import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../core/playlist_store.dart';
import '../core/stats_store.dart';
import '../core/theme_controller.dart';
import '../theme.dart';
import 'settings_page.dart';
import 'audio_lab_sheet.dart';
import 'library_page.dart';
import 'lyrics_page.dart';
import 'queue_sheet.dart';
import 'eq_sheet.dart';
import 'share_card_sheet.dart';
import 'tag_editor_sheet.dart';
import 'visualizer_widget.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.controller, this.theme});

  final PlayerController controller;

  /// Ajustes visuales compartidos con el resto de la app. Si falta (pruebas),
  /// la página usa uno en memoria.
  final ThemeController? theme;

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


  late final ThemeController _theme = widget.theme ?? ThemeController.memory();

  /// Modo bolsillo activo (bloquea los toques de esta pantalla).
  bool _pocket = false;

  /// Posición de la búsqueda fina mientras se arrastra en vertical.
  double? _fineSeek;

  Offset? _doubleTapAt;

  /// Las cinco colas y el automix viven en la página: así sobreviven a abrir y
  /// cerrar la hoja de la cola.
  late final MultiQueueStore _queues = MultiQueueStore();
  late final AutomixEngine _automix = AutomixEngine(controller: _controller);

  /// Almacenes compartidos: listas, estadísticas y posición de pistas largas.
  /// Viven en la página para que biblioteca, listas y estadísticas usen los
  /// mismos objetos (y el mismo archivo) en toda la app.
  late final PlaylistStore _playlists = PlaylistStore();
  late final StatsStore _stats = StatsStore();
  late final LongTrackMemory _longTracks = LongTrackMemory();

  /// Última pista apuntada en las estadísticas (evita contar dos veces).
  String _recordedPath = '';

  @override
  void initState() {
    super.initState();
    _pocket = _theme.pocketMode;
    _controller.addListener(_onSnapshot);
    _controller.position.addListener(_rememberPosition);
    _queues.load();
    _playlists.load();
    _stats.load();
    _longTracks.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onSnapshot);
    _controller.position.removeListener(_rememberPosition);
    _automix.dispose();
    _queues.dispose();
    _playlists.dispose();
    _stats.dispose();
    _longTracks.dispose();
    if (widget.theme == null) _theme.dispose();
    _spin.dispose();
    super.dispose();
  }

  /// Gira el disco y apunta la reproducción en las estadísticas al empezar una
  /// pista nueva.
  void _onSnapshot() {
    _syncSpin();
    if (!mounted) return;
    // El color dinámico sale de la carátula de lo que suena.
    unawaited(_theme.updateCover(_controller.snapshot.cover));
    final snapshot = _controller.snapshot;
    if (!snapshot.playing) return;
    final path = _currentPath();
    if (path.isEmpty || path == _recordedPath) return;
    _recordedPath = path;
    _stats.record(
      path: path,
      title: snapshot.title,
      artist: snapshot.artist,
      seconds: snapshot.duration,
    );
  }

  /// Solo las pistas largas guardan posición, y como mucho cada 10 s.
  double _lastRemembered = 0;

  void _rememberPosition() {
    final snapshot = _controller.snapshot;
    final path = _currentPath();
    if (path.isEmpty || !snapshot.hasTrack) return;
    final position = _controller.position.value;
    if ((position - _lastRemembered).abs() < 10) return;
    _lastRemembered = position;
    _longTracks.remember(path, position, snapshot.duration);
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

  void _openQueue() => QueueSheet.show(
        context,
        _controller,
        queues: _queues,
        automix: _automix,
      );

  void _openLab() => AudioLabSheet.show(context, _controller);

  void _openLyrics() => LyricsPage.show(context, _controller);

  void _openTags() => TagEditorSheet.show(context, _controller);

  /// La tarjeta necesita la letra para proponer un verso: se carga antes de
  /// abrir la hoja (si no hay, la hoja deja escribir uno).
  Future<void> _openShare() async {
    final path = _currentPath();
    final lyrics = path.isEmpty ? Lyrics.empty : await LyricsParser.loadForAudio(path);
    if (!mounted) return;
    await ShareCardSheet.show(context, _controller, lyrics: lyrics);
  }

  String _currentPath() {
    final snapshot = _controller.snapshot;
    final index = snapshot.queueIndex;
    if (index < 0 || index >= snapshot.queue.length) return '';
    return snapshot.queue[index].path;
  }

  void _openLibrary() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryPage(
          controller: _controller,
          playlists: _playlists,
          stats: _stats,
          longTracks: _longTracks,
        ),
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
      listenable: Listenable.merge(<Listenable>[_controller, _theme]),
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        final palette = _theme.palette;
        final size = MediaQuery.sizeOf(context);
        final wide = size.width >= 760 && size.width > size.height;
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
              body: Stack(
                children: [
                  Positioned.fill(child: _background(snapshot, palette)),
                  SafeArea(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTapDown: (details) =>
                          _doubleTapAt = details.localPosition,
                      onDoubleTap: () => _handleDoubleTap(context, snapshot, palette),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 20,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: wide ? 980 : 460),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _Header(
                                  onOpen: _openFile,
                                  onQueue: _openQueue,
                                  onLibrary: _openLibrary,
                                  onSettings: _openSettings,
                                  onPocket: _enterPocket,
                                  palette: palette,
                                ),
                                const SizedBox(height: 20),
                                if (wide)
                                  Row(
                                    key: const ValueKey<String>('player-panes'),
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: _coverArea(snapshot, palette),
                                      ),
                                      const SizedBox(width: 28),
                                      Expanded(
                                        flex: 6,
                                        child: _controls(context, snapshot, palette),
                                      ),
                                    ],
                                  )
                                else ...[
                                  _coverArea(snapshot, palette),
                                  const SizedBox(height: 24),
                                  _controls(context, snapshot, palette),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_pocket)
                    Positioned.fill(child: _pocketOverlay(snapshot, palette)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // Capas visuales
  // -----------------------------------------------------------------------

  /// Fondo: degradado del tema o, en estilo «a sangre», la carátula.
  Widget _background(PlayerSnapshot snapshot, CyberHexPalette palette) {
    final cover = snapshot.cover;
    final bleed = _theme.coverStyle == CoverStyle.fullBleed && cover != null;
    final top = Color.lerp(palette.background, palette.primary, 0.35)!;
    final bottom = palette.isDark
        ? Color.lerp(palette.background, Colors.black, 0.28)!
        : palette.background;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (bleed)
          Image.memory(
            cover,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: 720,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                top.withValues(alpha: bleed ? 0.55 : 1),
                palette.background.withValues(alpha: bleed ? 0.82 : 1),
                bottom,
              ],
              stops: const <double>[0, 0.45, 1],
            ),
          ),
        ),
      ],
    );
  }

  /// Carátula según el estilo elegido, con los gestos de deslizamiento.
  Widget _coverArea(PlayerSnapshot snapshot, CyberHexPalette palette) {
    final child = switch (_theme.coverStyle) {
      CoverStyle.spinningDisc => _Disc(spin: _spin, snapshot: snapshot),
      CoverStyle.square => _CoverFrame(snapshot: snapshot, radius: 12),
      CoverStyle.rounded => _CoverFrame(snapshot: snapshot, radius: 44),
      CoverStyle.fullBleed => _CoverFrame(snapshot: snapshot, radius: 0, size: 300),
    };
    return GestureDetector(
      key: const ValueKey<String>('player-cover'),
      onHorizontalDragEnd: _handleHorizontalDrag,
      onVerticalDragUpdate: _handleVerticalDrag,
      child: RepaintBoundary(child: child),
    );
  }

  /// Todo lo que va debajo de la carátula: título, barra, controles y accesos.
  Widget _controls(
    BuildContext context,
    PlayerSnapshot snapshot,
    CyberHexPalette palette,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TrackInfo(snapshot: snapshot, onOpen: _openFile),
        const SizedBox(height: 20),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _handleFineSeek,
          onVerticalDragEnd: (_) => _commitFineSeek(),
          onVerticalDragCancel: _commitFineSeek,
          child: _SeekBar(
            position: _controller.position,
            snapshot: snapshot,
            dragging: _dragging || _fineSeek != null,
            dragPosition: _fineSeek ?? _dragPosition,
            onChangeStart: (value) => setState(() {
              _dragging = true;
              _dragPosition = value;
            }),
            onChanged: (value) => setState(() => _dragPosition = value),
            onChangeEnd: (value) {
              _controller.seek(value);
              setState(() => _dragging = false);
            },
          ),
        ),
        if (_fineSeek != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Búsqueda fina: ${_fineLabel(_fineSeek!)} (arrastra en vertical)',
              style: TextStyle(fontSize: 10, color: palette.accent),
            ),
          ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: VisualizerWidget(
            controller: _controller,
            bands: 24,
            height: 74,
            showMeters: false,
          ),
        ),
        const SizedBox(height: 6),
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
        _QuickActions(
          actions: _theme.actions,
          onAction: _runAction,
          hasTrack: snapshot.hasTrack,
          palette: palette,
        ),
        const SizedBox(height: 10),
        _FooterRow(
          snapshot: snapshot,
          onVolume: _controller.setVolume,
          onEq: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => EqualizerSheet(controller: _controller),
          ),
          onLab: _openLab,
          soundscape: _controller.soundscape,
          onSoundscape: _controller.cycleSoundscape,
        ),
      ],
    );
  }

  /// Bloqueo táctil: se sale manteniendo pulsado (nunca con un toque suelto).
  Widget _pocketOverlay(PlayerSnapshot snapshot, CyberHexPalette palette) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _leavePocket,
      child: Container(
        color: palette.background.withValues(alpha: 0.97),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 54, color: palette.accent),
              const SizedBox(height: 14),
              Text(
                'Modo bolsillo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pantalla bloqueada: los toques no hacen nada.',
                style: TextStyle(fontSize: 12, color: palette.muted),
              ),
              const SizedBox(height: 18),
              Text(
                'Mantén pulsado para salir',
                style: TextStyle(fontSize: 13, color: palette.accent),
              ),
              if (snapshot.hasTrack) ...[
                const SizedBox(height: 22),
                Text(
                  snapshot.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: palette.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Gestos
  // -----------------------------------------------------------------------

  void _handleDoubleTap(
    BuildContext context,
    PlayerSnapshot snapshot,
    CyberHexPalette palette,
  ) {
    if (_pocket) return;
    final width = MediaQuery.sizeOf(context).width;
    final dx = _doubleTapAt?.dx ?? width / 2;
    if (dx < width / 3) {
      _seekBy(-10);
    } else if (dx > width * 2 / 3) {
      _seekBy(10);
    } else {
      _toggle();
    }
  }

  void _seekBy(double delta) {
    final duration = _controller.snapshot.duration;
    final base = _controller.position.value;
    final target = base + delta;
    if (target <= 0) {
      _controller.seek(0);
      return;
    }
    _controller.seek(duration > 0 && target > duration ? duration : target);
  }

  void _handleHorizontalDrag(DragEndDetails details) {
    if (_pocket) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 250) return;
    if (velocity < 0) {
      _controller.next();
    } else {
      _controller.previous();
    }
  }

  void _handleVerticalDrag(DragUpdateDetails details) {
    if (_pocket) return;
    final volume = (_controller.snapshot.volume - details.delta.dy / 240)
        .clamp(0.0, 1.0)
        .toDouble();
    _controller.setVolume(volume);
  }

  void _handleFineSeek(DragUpdateDetails details) {
    if (_pocket) return;
    if (!_controller.snapshot.hasTrack) return;
    final base = _fineSeek ?? _controller.position.value;
    final duration = _controller.snapshot.duration;
    var next = base - details.delta.dy * 0.05; // 20 px = 1 s, 1 px = 50 ms
    if (next < 0) next = 0;
    if (duration > 0 && next > duration) next = duration;
    setState(() => _fineSeek = next);
  }

  void _commitFineSeek() {
    final value = _fineSeek;
    if (value == null) return;
    _controller.seek(value);
    setState(() => _fineSeek = null);
  }

  static String _fineLabel(double seconds) {
    final total = seconds.floor();
    final millis = ((seconds - total) * 1000).round();
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}.'
        '${millis.toString().padLeft(3, '0')}';
  }

  void _enterPocket() {
    setState(() => _pocket = true);
  }

  void _leavePocket() {
    if (!mounted) return;
    setState(() => _pocket = false);
  }

  void _runAction(PlayerAction action) {
    switch (action) {
      case PlayerAction.lyrics:
        _openLyrics();
      case PlayerAction.tags:
        _openTags();
      case PlayerAction.share:
        unawaited(_openShare());
      case PlayerAction.lab:
        _openLab();
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsPage(theme: _theme)),
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
    required this.onSettings,
    required this.onPocket,
    required this.palette,
  });

  final VoidCallback onOpen;
  final VoidCallback onQueue;
  final VoidCallback onLibrary;
  final VoidCallback onSettings;
  final VoidCallback onPocket;
  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            'CYBERHEX',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Righteous',
              fontSize: 22,
              letterSpacing: 3,
              color: palette.foreground,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onPocket,
          tooltip: 'Modo bolsillo',
          icon: Icon(Icons.lock_outline_rounded, color: palette.muted),
        ),
        IconButton(
          onPressed: onSettings,
          tooltip: 'Ajustes',
          icon: Icon(Icons.palette_outlined, color: palette.muted),
        ),
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

/// Carátula en los estilos que no giran: cuadrada, redondeada y a sangre.
class _CoverFrame extends StatelessWidget {
  const _CoverFrame({
    required this.snapshot,
    required this.radius,
    this.size = 260,
  });

  final PlayerSnapshot snapshot;
  final double radius;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = snapshot.cover;
    final palette = paletteOf(context);
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    palette.secondary.withValues(alpha: 0.55),
                    palette.surfaceHigh,
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: palette.accent.withValues(
                      alpha: snapshot.playing ? 0.26 : 0.10,
                    ),
                    blurRadius: snapshot.playing ? 60 : 34,
                    spreadRadius: snapshot.playing ? 8 : 2,
                  ),
                ],
              ),
            ),
            if (image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Image.memory(
                  image,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: 520,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              )
            else
              Center(
                child: Icon(
                  Icons.album_rounded,
                  size: size * 0.34,
                  color: palette.foreground.withValues(alpha: 0.6),
                ),
              ),
            if (snapshot.busy)
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: ColoredBox(
                  color: palette.background.withValues(alpha: 0.55),
                  child: const Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(strokeWidth: 3),
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

/// Accesos rápidos configurables (letras, etiquetas, compartir y laboratorio).
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.actions,
    required this.onAction,
    required this.hasTrack,
    required this.palette,
  });

  final Set<PlayerAction> actions;
  final void Function(PlayerAction action) onAction;
  final bool hasTrack;
  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    final visible = <PlayerAction>[
      for (final action in PlayerAction.values)
        if (actions.contains(action)) action,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _Action(
              action: visible[i],
              palette: palette,
              onTap: _enabled(visible[i]) ? () => onAction(visible[i]) : null,
            ),
          ),
        ],
      ],
    );
  }

  bool _enabled(PlayerAction action) {
    if (action == PlayerAction.share) return true;
    return hasTrack;
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.action,
    required this.palette,
    required this.onTap,
  });

  final PlayerAction action;
  final CyberHexPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: enabled ? 0.85 : 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Icon(
              action.icon,
              size: 20,
              color: enabled ? palette.accent : palette.muted,
            ),
            const SizedBox(height: 4),
            Text(
              action.label,
              style: TextStyle(
                fontSize: 11,
                color: enabled ? palette.foreground : palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({
    required this.snapshot,
    required this.onVolume,
    required this.onEq,
    required this.onLab,
    required this.soundscape,
    required this.onSoundscape,
  });

  final PlayerSnapshot snapshot;
  final ValueChanged<double> onVolume;
  final VoidCallback onEq;
  final VoidCallback onLab;
  final SoundscapePreset soundscape;
  final VoidCallback onSoundscape;

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
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onEq,
                icon: const Icon(Icons.equalizer_rounded, size: 18),
                label: const Text('Ecualizador'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: chForeground,
                  side: const BorderSide(color: chBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onLab,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Laboratorio'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: chForeground,
                  side: const BorderSide(color: chBorder),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Tooltip(
          message: 'Paisaje sonoro (lluvia, ruido marrón, vinilo)',
          child: OutlinedButton.icon(
            onPressed: onSoundscape,
            icon: Icon(
              soundscape == SoundscapePreset.off
                  ? Icons.nights_stay_outlined
                  : Icons.water_drop_rounded,
              size: 18,
              color: soundscape == SoundscapePreset.off ? chMuted : chAccent,
            ),
            label: Text(
              switch (soundscape) {
                SoundscapePreset.off => 'Paisaje: no',
                SoundscapePreset.rain => 'Paisaje: lluvia',
                SoundscapePreset.brown => 'Paisaje: marrón',
                SoundscapePreset.vinyl => 'Paisaje: vinilo',
              },
              style: TextStyle(
                fontSize: 12,
                color: soundscape == SoundscapePreset.off ? chMuted : chAccent,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: soundscape == SoundscapePreset.off ? chBorder : chAccent,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
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
