import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/automix_engine.dart';
import '../core/lyrics_parser.dart';
import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../core/playlist_store.dart';
import '../core/stats_store.dart';
import '../core/theme_controller.dart';
import '../platform/connections.dart';
import '../platform/desktop_channel.dart';
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
import 'kit/ch_kit.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.controller,
    this.theme,
    this.desktop,
    this.connections,
  });

  final PlayerController controller;

  /// Ajustes visuales compartidos con el resto de la app. Si falta (pruebas),
  /// la página usa uno en memoria.
  final ThemeController? theme;

  /// Puente de escritorio (Linux): MPRIS y drag & drop. En el móvil es `null`.
  final DesktopChannel? desktop;

  /// API local y conexiones MCP. `null` en pruebas o si no se montaron.
  final CyberHexConnections? connections;

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

  /// Atajo: el motor llega por constructor y no cambia en toda la página.
  PlayerController get _controller => widget.controller;

  /// Modo bolsillo activo (bloquea los toques de esta pantalla).
  /// El bloqueo vive en el tema: así el interruptor de Ajustes y el botón de la
  /// cabecera son lo mismo, y sobrevive al reinicio.
  bool get _pocket => _theme.pocketMode;

  /// Posición de la búsqueda fina mientras se arrastra en vertical.
  double? _fineSeek;

  /// Cola abierta como panel derecho fijo (solo en ventanas anchas).
  bool _showQueue = false;

  Offset? _doubleTapAt;

  StreamSubscription<List<String>>? _dropsSubscription;

  /// Volumen previo al silencio, para restaurarlo con otra pulsación.
  double _volumeBeforeMute = 0.8;

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
    _controller.addListener(_onSnapshot);
    _dropsSubscription = widget.desktop?.drops.listen(_onDroppedPaths);
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
    unawaited(_dropsSubscription?.cancel());
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
    final shouldSpin =
        snapshot.playing && snapshot.cover == null && !snapshot.busy;
    if (shouldSpin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!shouldSpin && _spin.isAnimating) {
      _spin.stop();
    }
  }

  void _openQueue() {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760 && size.width > size.height;
    if (!wide) {
      QueueSheet.show(context, _controller, queues: _queues, automix: _automix);
      return;
    }
    setState(() => _showQueue = !_showQueue);
  }

  void _openLab() => AudioLabSheet.show(context, _controller);

  void _openLyrics() => LyricsPage.show(context, _controller);

  void _openTags() => TagEditorSheet.show(context, _controller);

  /// La tarjeta necesita la letra para proponer un verso: se carga antes de
  /// abrir la hoja (si no hay, la hoja deja escribir uno).
  Future<void> _openShare() async {
    final path = _currentPath();
    final lyrics = path.isEmpty
        ? Lyrics.empty
        : await LyricsParser.loadForAudio(path);
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
          onOpenPlayer: () => Navigator.of(context).pop(),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  void _toggle() {
    final snapshot = _controller.snapshot;
    if (snapshot.busy || !snapshot.hasTrack) {
      return;
    }
    chHaptic();
    _controller.toggle();
  }

  void _previous() {
    chHaptic();
    _controller.previous();
  }

  void _next() {
    chHaptic();
    _controller.next();
  }

  void _shuffle() {
    chHaptic();
    _controller.toggleShuffle();
  }

  void _repeat() {
    chHaptic();
    _controller.cycleRepeat();
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
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.space): _PlayerIntent(
              _PlayerCommand.toggle,
            ),
            SingleActivator(LogicalKeyboardKey.arrowLeft): _PlayerIntent(
              _PlayerCommand.seekBack,
            ),
            SingleActivator(LogicalKeyboardKey.arrowRight): _PlayerIntent(
              _PlayerCommand.seekForward,
            ),
            SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
                _PlayerIntent(_PlayerCommand.previous),
            SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
                _PlayerIntent(_PlayerCommand.next),
            SingleActivator(LogicalKeyboardKey.arrowUp): _PlayerIntent(
              _PlayerCommand.volumeUp,
            ),
            SingleActivator(LogicalKeyboardKey.arrowDown): _PlayerIntent(
              _PlayerCommand.volumeDown,
            ),
            SingleActivator(LogicalKeyboardKey.keyM): _PlayerIntent(
              _PlayerCommand.mute,
            ),
            SingleActivator(LogicalKeyboardKey.keyL): _PlayerIntent(
              _PlayerCommand.repeat,
            ),
            SingleActivator(LogicalKeyboardKey.keyS): _PlayerIntent(
              _PlayerCommand.shuffle,
            ),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _PlayerIntent: CallbackAction<_PlayerIntent>(
                onInvoke: (intent) {
                  _runCommand(intent.command);
                  return null;
                },
              ),
            },
            // Foco en la página para que los atajos lleguen sin tocar nada
            // (no hay campos de texto aquí que se lo puedan quedar).
            child: Focus(
              autofocus: true,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
                  children: <Widget>[
                    Positioned.fill(child: _background(snapshot, palette)),
                    SafeArea(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTapDown: (details) =>
                            _doubleTapAt = details.localPosition,
                        onDoubleTap: () =>
                            _handleDoubleTap(context, snapshot, palette),
                        child: Center(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              wide ? 34 : 22,
                              wide ? 14 : 4,
                              wide ? 34 : 22,
                              wide ? 26 : 14,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: wide ? 1060 : 480,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  _Header(
                                    palette: palette,
                                    onQueue: _openQueue,
                                    onLibrary: _openLibrary,
                                    onSettings: _openSettings,
                                    onPocket: _enterPocket,
                                    onOpen: _openFile,
                                  ),
                                  SizedBox(height: wide ? 12 : 4),
                                  if (wide)
                                    Row(
                                      key: const ValueKey<String>(
                                        'player-panes',
                                      ),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Expanded(
                                          flex: 5,
                                          child: _coverArea(snapshot, palette),
                                        ),
                                        const SizedBox(width: 44),
                                        Expanded(
                                          flex: 6,
                                          child: _controls(
                                            context,
                                            snapshot,
                                            palette,
                                          ),
                                        ),
                                        if (_showQueue) ...<Widget>[
                                          const SizedBox(width: 18),
                                          Expanded(
                                            flex: 4,
                                            child: QueueSheet(
                                              controller: _controller,
                                              queues: _queues,
                                              automix: _automix,
                                              onClose: () => setState(
                                                () => _showQueue = false,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                                  else ...<Widget>[
                                    _coverArea(snapshot, palette),
                                    const SizedBox(height: 14),
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
    final top = Color.lerp(palette.background, palette.primary, 0.42)!;
    final bottom = palette.isDark
        ? Color.lerp(palette.background, Colors.black, 0.30)!
        : palette.background;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // La carátula tiñe el fondo incluso sin el estilo «a sangre»: es el
        // color de la sesión, no un adorno.
        if (cover != null && !bleed)
          Positioned.fill(
            child: ChBlurredCover(cover: cover, sigma: 42, opacity: 0.55),
          ),
        if (bleed)
          Image.memory(
            cover,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: 720,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                top.withValues(alpha: bleed ? 0.62 : 1),
                palette.background.withValues(alpha: bleed ? 0.86 : 1),
                bottom,
              ],
              stops: const <double>[0, 0.42, 1],
            ),
          ),
        ),
      ],
    );
  }

  /// Carátula según el estilo elegido, con los gestos de deslizamiento.
  Widget _coverArea(PlayerSnapshot snapshot, CyberHexPalette palette) {
    if (!snapshot.hasTrack) return const SizedBox(height: 108);
    final child = switch (_theme.coverStyle) {
      CoverStyle.spinningDisc => _Disc(spin: _spin, snapshot: snapshot),
      CoverStyle.square => _CoverFrame(snapshot: snapshot, radius: 14),
      CoverStyle.rounded => _CoverFrame(snapshot: snapshot, radius: 34),
      CoverStyle.fullBleed => _CoverFrame(snapshot: snapshot, radius: 0),
    };
    return GestureDetector(
      key: const ValueKey<String>('player-cover'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: _handleHorizontalDrag,
      onVerticalDragUpdate: _handleVerticalDrag,
      onVerticalDragEnd: _handleCoverDragEnd,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 320.0;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : width;
          final side = math.min(width, height * 0.94).clamp(150.0, 360.0);
          return Center(
            child: SizedBox(
              width: side,
              height: side,
              child: RepaintBoundary(child: child),
            ),
          );
        },
      ),
    );
  }

  /// Todo lo que va debajo de la carátula: título, barra, transporte y
  /// herramientas. Una sola columna, sin tarjetas anidadas.
  Widget _controls(
    BuildContext context,
    PlayerSnapshot snapshot,
    CyberHexPalette palette,
  ) {
    if (!snapshot.hasTrack) {
      return _EmptyPlayer(palette: palette, onOpen: _openFile);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TrackInfo(snapshot: snapshot),
        const SizedBox(height: 8),
        // El arrastre vertical sobre la barra hace búsqueda fina: 20 px = 1 s.
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
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              'Búsqueda fina: ${_fineLabel(_fineSeek!)} · 1 px = 50 ms',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: palette.accent),
            ),
          ),
        const SizedBox(height: 2),
        // El espectro es la firma del motor: una franja fina, sin vúmetros.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: VisualizerWidget(
            controller: _controller,
            bands: 28,
            height: 38,
            showMeters: false,
          ),
        ),
        const SizedBox(height: 6),
        _Transport(
          snapshot: snapshot,
          onToggle: _toggle,
          onPrevious: _previous,
          onNext: _next,
          onShuffle: _shuffle,
          onRepeat: _repeat,
        ),
        const SizedBox(height: 2),
        _VolumeRow(
          volume: snapshot.volume,
          onVolume: _setVolume,
          onMute: _toggleMute,
        ),
        const SizedBox(height: 12),
        _ToolStrip(
          actions: _theme.actions,
          palette: palette,
          hasTrack: snapshot.hasTrack,
          onAction: _runAction,
          onEq: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => EqualizerSheet(controller: _controller),
          ),
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
        color: palette.background.withValues(alpha: 0.98),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ChHexBadge(icon: Icons.lock_rounded, palette: palette, size: 76),
              const SizedBox(height: ChSpace.lg),
              Text('Modo bolsillo', style: chTitle(palette, size: 19)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  'Pantalla bloqueada: los toques no hacen nada.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: palette.muted,
                  ),
                ),
              ),
              const SizedBox(height: ChSpace.lg),
              Text(
                'Mantén pulsado para salir',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: palette.accent,
                ),
              ),
              if (snapshot.hasTrack) ...<Widget>[
                const SizedBox(height: ChSpace.xl),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    snapshot.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: chMono(palette, size: 10.5),
                  ),
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
      chHaptic();
      _controller.next();
    } else {
      chHaptic();
      _controller.previous();
    }
  }

  /// Subir en la carátula da volumen; bajar no toca nada (el gesto de bajar
  /// cierra la pantalla, como en Namida).
  void _handleVerticalDrag(DragUpdateDetails details) {
    if (_pocket || details.delta.dy > 0) return;
    final volume = (_controller.snapshot.volume - details.delta.dy / 240)
        .clamp(0.0, 1.0)
        .toDouble();
    _controller.setVolume(volume);
  }

  /// Soltar hacia abajo con impulso cierra el reproductor.
  void _handleCoverDragEnd(DragEndDetails details) {
    if (_pocket) return;
    if ((details.primaryVelocity ?? 0) < 320) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).maybePop();
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

  void _enterPocket() => _theme.setPocketMode(true);

  void _leavePocket() => _theme.setPocketMode(false);

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

  // -----------------------------------------------------------------------
  // Teclado
  // -----------------------------------------------------------------------

  /// Atajos del reproductor: espacio, flechas, M (silencio), L (repetición) y
  /// S (aleatorio). Las teclas multimedia del sistema llegan por MPRIS, no por
  /// aquí: las captura el entorno de escritorio, que es lo correcto.
  void _runCommand(_PlayerCommand command) {
    final snapshot = _controller.snapshot;
    switch (command) {
      case _PlayerCommand.toggle:
        _toggle();
      case _PlayerCommand.seekBack:
        _seekBy(-5);
      case _PlayerCommand.seekForward:
        _seekBy(5);
      case _PlayerCommand.next:
        _controller.next();
      case _PlayerCommand.previous:
        _controller.previous();
      case _PlayerCommand.volumeUp:
        _setVolume(snapshot.volume + 0.05);
      case _PlayerCommand.volumeDown:
        _setVolume(snapshot.volume - 0.05);
      case _PlayerCommand.mute:
        if (snapshot.volume > 0.001) {
          _volumeBeforeMute = snapshot.volume;
          _setVolume(0);
        } else {
          _setVolume(_volumeBeforeMute <= 0.001 ? 0.8 : _volumeBeforeMute);
        }
      case _PlayerCommand.repeat:
        _controller.cycleRepeat();
      case _PlayerCommand.shuffle:
        _controller.toggleShuffle();
    }
  }

  void _setVolume(double value) {
    _controller.setVolume(value.clamp(0.0, 1.0).toDouble());
  }

  /// Silencia y restaura el volumen previo (botón del altavoz).
  void _toggleMute() {
    final snapshot = _controller.snapshot;
    if (snapshot.volume > 0.001) {
      _volumeBeforeMute = snapshot.volume;
      _setVolume(0);
      return;
    }
    _setVolume(_volumeBeforeMute <= 0.001 ? 0.8 : _volumeBeforeMute);
  }

  // -----------------------------------------------------------------------
  // Drag & drop (lo captura GTK y llega por `cyberhex/desktop`)
  // -----------------------------------------------------------------------

  /// Abre el primer archivo (o la primera pista de la primera carpeta) y encola
  /// el resto. Las carpetas se escanean con el motor, no con `dart:io`.
  Future<void> _onDroppedPaths(List<String> paths) async {
    if (paths.isEmpty || !mounted) return;

    var opened = 0;
    var enqueued = 0;
    var scanned = 0;
    var failed = 0;

    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.directory) {
        final tracks = await _controller.scanDirectory(path);
        scanned += tracks.length;
        for (final track in tracks) {
          if (opened == 0) {
            final error = await _controller.openFile(track.path);
            if (error == null) {
              opened += 1;
              _controller.play();
            } else {
              failed += 1;
            }
          } else if (_controller.enqueue(track.path)) {
            enqueued += 1;
          }
        }
        continue;
      }
      if (type != FileSystemEntityType.file) {
        failed += 1;
        continue;
      }
      if (opened == 0) {
        final error = await _controller.openFile(path);
        if (error == null) {
          opened += 1;
          _controller.play();
        } else {
          failed += 1;
        }
      } else if (_controller.enqueue(path)) {
        enqueued += 1;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened == 0
              ? 'No se pudo abrir nada de lo que soltaste ($failed fallo(s)).'
              : 'Soltado: $opened en reproducción, $enqueued en cola'
                    '${scanned > 0 ? ', $scanned pista(s) escaneadas' : ''}'
                    '${failed > 0 ? ', $failed fallo(s)' : ''}.',
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          theme: _theme,
          player: _controller,
          desktop: widget.desktop,
          connections: widget.connections,
        ),
      ),
    );
  }
}

/// Comandos de teclado del reproductor (ver `_runCommand`).
enum _PlayerCommand {
  toggle,
  seekBack,
  seekForward,
  next,
  previous,
  volumeUp,
  volumeDown,
  mute,
  repeat,
  shuffle,
}

class _PlayerIntent extends Intent {
  const _PlayerIntent(this.command);

  final _PlayerCommand command;
}

/// Cabecera mínima: cerrar, palabra, bolsillo y un menú con lo demás.
class _Header extends StatelessWidget {
  const _Header({
    required this.palette,
    required this.onQueue,
    required this.onLibrary,
    required this.onSettings,
    required this.onPocket,
    required this.onOpen,
  });

  final CyberHexPalette palette;
  final VoidCallback onQueue;
  final VoidCallback onLibrary;
  final VoidCallback onSettings;
  final VoidCallback onPocket;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (Navigator.of(context).canPop())
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Cerrar reproductor',
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: palette.muted),
          ),
        Text(
          'CYBERHEX',
          style: TextStyle(
            fontFamily: 'Righteous',
            fontSize: 13,
            letterSpacing: 2.8,
            color: palette.foreground.withValues(alpha: 0.92),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onPocket,
          tooltip: 'Modo bolsillo',
          icon: Icon(
            Icons.lock_outline_rounded,
            size: 20,
            color: palette.muted,
          ),
        ),
        PopupMenuButton<_PlayerMenu>(
          tooltip: 'Más',
          icon: Icon(Icons.more_horiz_rounded, color: palette.muted),
          onSelected: (value) => switch (value) {
            _PlayerMenu.queue => onQueue(),
            _PlayerMenu.library => onLibrary(),
            _PlayerMenu.settings => onSettings(),
            _PlayerMenu.open => onOpen(),
          },
          itemBuilder: (context) => <PopupMenuEntry<_PlayerMenu>>[
            const PopupMenuItem<_PlayerMenu>(
              value: _PlayerMenu.queue,
              child: Text('Cola de reproducción'),
            ),
            const PopupMenuItem<_PlayerMenu>(
              value: _PlayerMenu.library,
              child: Text('Biblioteca'),
            ),
            const PopupMenuItem<_PlayerMenu>(
              value: _PlayerMenu.settings,
              child: Text('Ajustes'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<_PlayerMenu>(
              value: _PlayerMenu.open,
              child: Text('Abrir audio'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Opciones del menú de la cabecera.
enum _PlayerMenu { queue, library, settings, open }

/// Pantalla sin pista: la bienvenida y la puerta de entrada.
class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer({required this.palette, required this.onOpen});

  final CyberHexPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ChHexBadge(
            icon: Icons.graphic_eq_rounded,
            palette: palette,
            size: 92,
          ),
          const SizedBox(height: ChSpace.lg),
          Text(
            'Tu música, en tu máquina',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Righteous',
              fontSize: 21,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: ChSpace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              'Abre un archivo y CyberHex lo decodifica con su propio motor en '
              'Zig y C23. Nada sale de tu equipo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.55,
                color: palette.muted,
              ),
            ),
          ),
          const SizedBox(height: ChSpace.lg),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Abrir audio'),
          ),
        ],
      ),
    );
  }
}

/// Carátula en los estilos que no giran: cuadrada, redondeada y a sangre.
class _CoverFrame extends StatelessWidget {
  const _CoverFrame({required this.snapshot, required this.radius});

  final PlayerSnapshot snapshot;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = snapshot.cover;
    final palette = paletteOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return SizedBox(
          width: side,
          height: side,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color.lerp(palette.surfaceHigh, palette.accent, 0.22)!,
                      palette.surface,
                    ],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: palette.accent.withValues(
                        alpha: snapshot.playing ? 0.30 : 0.14,
                      ),
                      blurRadius: snapshot.playing ? 64 : 30,
                      spreadRadius: snapshot.playing ? 6 : 1,
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
                    cacheWidth: 640,
                    errorBuilder: (_, _, _) => _fallback(side, palette),
                  ),
                )
              else
                _fallback(side, palette),
              if (snapshot.busy)
                ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: ColoredBox(
                    color: palette.background.withValues(alpha: 0.55),
                    child: Center(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: palette.accent,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _fallback(double side, CyberHexPalette palette) {
    return Center(
      child: Icon(
        Icons.album_rounded,
        size: side * 0.32,
        color: palette.foreground.withValues(alpha: 0.55),
      ),
    );
  }
}

/// Disco de vinilo: gira mientras suena y no hay carátula.
class _Disc extends StatelessWidget {
  const _Disc({required this.spin, required this.snapshot});

  final AnimationController spin;
  final PlayerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final image = snapshot.cover;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final label = side * 0.30;
        return SizedBox(
          width: side,
          height: side,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: palette.accent.withValues(
                        alpha: snapshot.playing ? 0.26 : 0.12,
                      ),
                      blurRadius: snapshot.playing ? 68 : 34,
                      spreadRadius: snapshot.playing ? 10 : 2,
                    ),
                  ],
                ),
              ),
              if (image != null)
                ClipOval(
                  child: Image.memory(
                    image,
                    width: side,
                    height: side,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: 640,
                    errorBuilder: (_, _, _) =>
                        _vinyl(side, label, reduceMotion, palette),
                  ),
                )
              else
                _vinyl(side, label, reduceMotion, palette),
              if (snapshot.busy)
                Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.background.withValues(alpha: 0.62),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: palette.accent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _vinyl(
    double side,
    double label,
    bool reduceMotion,
    CyberHexPalette palette,
  ) {
    return RotationTransition(
      turns: reduceMotion ? const AlwaysStoppedAnimation(0.08) : spin,
      child: Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: <Color>[
              palette.surfaceHigh,
              palette.surface,
              Color.lerp(palette.surface, palette.accent, 0.30)!,
              palette.surface,
              palette.surfaceHigh,
            ],
            stops: const <double>[0, 0.28, 0.5, 0.74, 1],
          ),
          border: Border.all(
            color: palette.border.withValues(alpha: 0.8),
            width: 1,
          ),
        ),
        child: Center(
          child: Container(
            width: label,
            height: label,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.background,
              border: Border.all(color: palette.border.withValues(alpha: 0.7)),
            ),
            child: Icon(
              snapshot.hasTrack
                  ? Icons.graphic_eq_rounded
                  : Icons.music_note_rounded,
              size: label * 0.46,
              color: snapshot.hasTrack ? palette.accent : palette.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Título, artista y sello técnico: la única cabecera de texto de la pantalla.
class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.snapshot});

  final PlayerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final subtitle = <String>[
      snapshot.artist,
      snapshot.album,
    ].where((part) => part.isNotEmpty).join(' · ');
    return Column(
      children: <Widget>[
        Text(
          snapshot.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: chTitle(palette, size: 21),
        ),
        if (subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: palette.muted),
          ),
        ],
        const SizedBox(height: 5),
        Text(
          '${_clock(snapshot.duration)} · motor nativo 48 kHz',
          style: chMono(palette, size: 10),
        ),
      ],
    );
  }
}

/// Barra de posición con los tiempos en monoespaciada.
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
    final palette = paletteOf(context);
    final duration = math.max(snapshot.duration, 0.001);
    final enabled = snapshot.hasTrack && !snapshot.busy;
    return ValueListenableBuilder<double>(
      valueListenable: position,
      builder: (context, value, _) {
        final current = (dragging ? dragPosition : value).clamp(0.0, duration);
        return Column(
          children: <Widget>[
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    _clock(current.toDouble()),
                    style: chMono(
                      palette,
                      size: 10,
                      color: dragging ? palette.accent : palette.muted,
                    ),
                  ),
                  Text(
                    snapshot.hasTrack ? _clock(snapshot.duration) : '--:--',
                    style: chMono(palette, size: 10),
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

/// Transporte estándar: aleatorio · anterior · play · siguiente · repetir.
class _Transport extends StatelessWidget {
  const _Transport({
    required this.snapshot,
    required this.onToggle,
    required this.onPrevious,
    required this.onNext,
    required this.onShuffle,
    required this.onRepeat,
  });

  final PlayerSnapshot snapshot;
  final VoidCallback onToggle;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final enabled = snapshot.hasTrack && !snapshot.busy;
    final repeat = snapshot.repeatMode;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ChToggleIcon(
          icon: Icons.shuffle_rounded,
          active: snapshot.shuffle,
          tooltip: snapshot.shuffle
              ? 'Aleatorio activado · quitar'
              : 'Aleatorio desactivado · activar',
          onPressed: onShuffle,
        ),
        const SizedBox(width: 2),
        IconButton(
          onPressed: enabled ? onPrevious : null,
          tooltip: 'Anterior',
          iconSize: 27,
          icon: Icon(Icons.skip_previous_rounded, color: palette.foreground),
        ),
        const SizedBox(width: 4),
        ChPlayButton(
          playing: snapshot.playing,
          busy: snapshot.busy,
          onPressed: enabled ? onToggle : null,
          size: 68,
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: enabled ? onNext : null,
          tooltip: 'Siguiente',
          iconSize: 27,
          icon: Icon(Icons.skip_next_rounded, color: palette.foreground),
        ),
        const SizedBox(width: 2),
        ChToggleIcon(
          icon: repeat == 2 ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          active: repeat != 0,
          tooltip: switch (repeat) {
            1 => 'Repetir todo · una sola',
            2 => 'Repetir una · apagar',
            _ => 'Repetición apagada · repetir todo',
          },
          onPressed: onRepeat,
        ),
      ],
    );
  }
}

/// Volumen en una línea: icono de silencio, deslizador y porcentaje.
class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.volume,
    required this.onVolume,
    required this.onMute,
  });

  final double volume;
  final ValueChanged<double> onVolume;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final muted = volume <= 0.001;
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: onMute,
          tooltip: muted ? 'Activar sonido' : 'Silenciar',
          icon: Icon(
            muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            size: 20,
            color: muted ? palette.accent : palette.muted,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0).toDouble(),
              onChanged: onVolume,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${(volume * 100).round()}%',
            textAlign: TextAlign.end,
            style: chMono(palette, size: 9.5),
          ),
        ),
      ],
    );
  }
}

/// Herramientas secundarias: ecualizador, acciones configurables y ambiente.
class _ToolStrip extends StatelessWidget {
  const _ToolStrip({
    required this.actions,
    required this.palette,
    required this.hasTrack,
    required this.onAction,
    required this.onEq,
    required this.soundscape,
    required this.onSoundscape,
  });

  final Set<PlayerAction> actions;
  final CyberHexPalette palette;
  final bool hasTrack;
  final void Function(PlayerAction action) onAction;
  final VoidCallback onEq;
  final SoundscapePreset soundscape;
  final VoidCallback onSoundscape;

  @override
  Widget build(BuildContext context) {
    final soundOn = soundscape != SoundscapePreset.off;
    final tools = <_Tool>[
      _Tool(
        icon: Icons.equalizer_rounded,
        label: 'Ecualizador',
        onTap: onEq,
        enabled: true,
        active: false,
      ),
      for (final action in PlayerAction.values)
        if (actions.contains(action))
          _Tool(
            icon: action.icon,
            label: action.label,
            onTap: () => onAction(action),
            enabled: hasTrack || action == PlayerAction.share,
            active: false,
          ),
      _Tool(
        icon: soundOn ? Icons.water_drop_rounded : Icons.nights_stay_outlined,
        label: switch (soundscape) {
          SoundscapePreset.off => 'Ambiente',
          SoundscapePreset.rain => 'Lluvia',
          SoundscapePreset.brown => 'Marrón',
          SoundscapePreset.vinyl => 'Vinilo',
        },
        onTap: onSoundscape,
        enabled: true,
        active: soundOn,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / tools.length;
        return Row(
          children: <Widget>[
            for (var i = 0; i < tools.length; i++)
              SizedBox(
                width: width,
                child: _ToolButton(tool: tools[i], palette: palette),
              ),
          ],
        );
      },
    );
  }
}

class _Tool {
  const _Tool({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.enabled,
    required this.active,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool active;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool, required this.palette});

  final _Tool tool;
  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = !tool.enabled
        ? palette.muted.withValues(alpha: 0.55)
        : tool.active
        ? palette.accent
        : palette.foreground.withValues(alpha: 0.86);
    return Tooltip(
      message: tool.label,
      child: InkWell(
        onTap: tool.enabled ? tool.onTap : null,
        borderRadius: BorderRadius.circular(ChRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(tool.icon, size: 19, color: color),
              const SizedBox(height: 3),
              Text(
                tool.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 8.5, color: color, height: 1.2),
              ),
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
