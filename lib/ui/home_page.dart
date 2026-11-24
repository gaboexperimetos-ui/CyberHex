import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/library_browse.dart';
import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../core/stats_store.dart';
import '../core/theme_controller.dart';
import '../theme.dart';
import 'hex_grid.dart';
import 'kit/ch_kit.dart';
import 'search_sheet.dart';

/// Pestaña de inicio: la portada de la app.
///
/// La jerarquía es deliberada: primero lo que está sonando, después lo que
/// estabas escuchando, luego tu biblioteca y por último las herramientas. Nada
/// reproduce por su cuenta: todo delega en el controlador y en las páginas que
/// ya existen.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.theme,
    required this.stats,
    required this.onOpenPlayer,
    required this.onOpenLibrary,
    required this.onOpenPlaylists,
    required this.onOpenRadio,
    required this.onOpenStats,
    this.onOpenAlbum,
  });

  final PlayerController controller;
  final ThemeController theme;
  final StatsStore stats;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenPlaylists;
  final VoidCallback onOpenRadio;
  final VoidCallback onOpenStats;

  /// Abre la biblioteca filtrada por un álbum. Si falta, la sección de álbumes
  /// no se pinta (pruebas de la portada aislada).
  final void Function(String album)? onOpenAlbum;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, stats, theme]),
      builder: (context, _) {
        final palette = theme.palette;
        final snapshot = controller.snapshot;
        final currentPath =
            snapshot.queueIndex >= 0 &&
                snapshot.queueIndex < snapshot.queue.length
            ? snapshot.queue[snapshot.queueIndex].path
            : null;
        final recents = _recentTracks(
          stats,
          excludePath: currentPath,
          limit: 10,
        );
        final top = <TrackStat>[
          for (final stat in stats.topTracks(5))
            if (stat.plays > 0) stat,
        ];
        final albums = onOpenAlbum == null
            ? const <LibraryAlbum>[]
            : albumsFromTracks(controller.libraryTracks);
        void openSearch() => unawaited(_openSearch(context, controller, stats));
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                openSearch,
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                openSearch,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                openSearch,
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                openSearch,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: palette.background,
              body: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color.lerp(palette.background, palette.primary, 0.34)!,
                      palette.background,
                    ],
                    stops: const <double>[0, 0.38],
                  ),
                ),
                child: Stack(
                  children: <Widget>[
                    // Patrón hexagonal sutil detrás del contenido.
                    HexGridBackground(palette: palette),
                    SafeArea(
                      bottom: false,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                            children: <Widget>[
                              _Header(palette: palette, onSearch: openSearch),
                              const SizedBox(height: ChSpace.xl - 4),
                              _ContinueCard(
                                snapshot: snapshot,
                                position: controller.position,
                                palette: palette,
                                onOpen: onOpenPlayer,
                                onToggle: controller.toggle,
                                onOpenLibrary: onOpenLibrary,
                              ),
                              if (recents.isNotEmpty) ...<Widget>[
                                const SizedBox(height: ChSpace.xl),
                                ChSectionHeader(
                                  'Sigue escuchando',
                                  palette: palette,
                                  count: recents.length,
                                  onAction: onOpenStats,
                                ),
                                const SizedBox(height: ChSpace.sm + 2),
                                _RecentRail(
                                  entries: recents,
                                  palette: palette,
                                  onPlay: (path) => unawaited(
                                    _play(context, controller, path),
                                  ),
                                ),
                              ],
                              if (albums.isNotEmpty) ...<Widget>[
                                const SizedBox(height: ChSpace.xl),
                                ChSectionHeader(
                                  'Álbumes',
                                  palette: palette,
                                  count: albums.length,
                                  onAction: onOpenLibrary,
                                ),
                                const SizedBox(height: ChSpace.sm + 2),
                                _AlbumRail(
                                  albums: albums
                                      .take(12)
                                      .toList(growable: false),
                                  palette: palette,
                                  onOpen: (album) => onOpenAlbum!(album.name),
                                ),
                              ],
                              const SizedBox(height: ChSpace.xl),
                              ChSectionHeader('Explorar', palette: palette),
                              const SizedBox(height: ChSpace.sm + 2),
                              _Shortcuts(
                                palette: palette,
                                onLibrary: onOpenLibrary,
                                onPlaylists: onOpenPlaylists,
                                onRadio: onOpenRadio,
                                onStats: onOpenStats,
                              ),
                              if (top.isNotEmpty) ...<Widget>[
                                const SizedBox(height: ChSpace.xl),
                                ChSectionHeader(
                                  'Lo que más suena',
                                  palette: palette,
                                  onAction: onOpenStats,
                                ),
                                const SizedBox(height: ChSpace.sm + 2),
                                _TopTracks(
                                  tracks: top,
                                  palette: palette,
                                  playingPath: currentPath,
                                  onPlay: (path) => unawaited(
                                    _play(context, controller, path),
                                  ),
                                ),
                              ],
                              const SizedBox(height: ChSpace.xl),
                              ChSectionHeader(
                                'Tu actividad',
                                palette: palette,
                                actionLabel: 'Detalle',
                                onAction: onOpenStats,
                              ),
                              const SizedBox(height: ChSpace.sm + 2),
                              _ActivityCard(
                                stats: stats,
                                palette: palette,
                                onOpen: onOpenStats,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Historial reciente sin repetir pistas; deja fuera la que ya suena.
  static List<HistoryEntry> _recentTracks(
    StatsStore stats, {
    String? excludePath,
    int limit = 10,
  }) {
    final seen = <String>{};
    final out = <HistoryEntry>[];
    for (final entry in stats.history) {
      if (entry.path.isEmpty) continue;
      if (excludePath != null && entry.path == excludePath) continue;
      if (!seen.add(entry.path)) continue;
      out.add(entry);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Reproduce una ruta ya conocida por las estadísticas.
  static Future<void> _play(
    BuildContext context,
    PlayerController controller,
    String path,
  ) async {
    final error = await controller.openFile(path);
    if (error == null || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('No se pudo reproducir: $error')));
  }

  /// Abre la búsqueda global (biblioteca + historial) desde Inicio.
  static Future<void> _openSearch(
    BuildContext context,
    PlayerController controller,
    StatsStore stats,
  ) {
    return SearchSheet.show(context, controller: controller, stats: stats);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.palette, this.onSearch});

  final CyberHexPalette palette;

  /// Abre la búsqueda global. Sin callback no se pinta la lupa (portada usada
  /// suelta, sin armazón).
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        // La marca manda, pero cede: en un móvil estrecho se encoge en vez de
        // empujar la insignia y la lupa fuera de la pantalla.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: 'Righteous',
                      fontSize: 22,
                      letterSpacing: 3.2,
                      color: palette.foreground,
                    ),
                    children: <InlineSpan>[
                      const TextSpan(text: 'CYBER'),
                      TextSpan(
                        text: 'HEX',
                        style: TextStyle(
                          color: palette.accent,
                          shadows: <Shadow>[
                            Shadow(
                              color: palette.accent.withValues(alpha: 0.55),
                              blurRadius: 14,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Tu música, tu máquina',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: palette.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: ChSpace.sm),
        const _StatusPill(),
        if (onSearch != null) ...<Widget>[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Buscar (Ctrl+F)',
            onPressed: onSearch,
            icon: Icon(Icons.search_rounded, color: palette.foreground),
          ),
        ],
      ],
    );
  }
}

/// Insignia técnica de la cabecera: recuerda que el motor es propio.
class _StatusPill extends StatelessWidget {
  const _StatusPill();

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Tooltip(
      message: 'Motor nativo CyberHex · 48 kHz',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: palette.surfaceHigh.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(ChRadius.pill),
          border: Border.all(color: palette.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '48 kHz',
              style: chMono(palette, size: 9.5, color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta principal: lo que suena, o la puerta de entrada a la biblioteca.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.snapshot,
    required this.position,
    required this.palette,
    required this.onOpen,
    required this.onToggle,
    required this.onOpenLibrary,
  });

  final PlayerSnapshot snapshot;
  final ValueListenable<double> position;
  final CyberHexPalette palette;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    return snapshot.hasTrack ? _nowPlaying() : _onboarding();
  }

  Widget _onboarding() {
    return ChSurface(
      radius: ChRadius.xl,
      elevated: true,
      padding: const EdgeInsets.all(ChSpace.lg),
      onTap: onOpenLibrary,
      gradient: ChGradient.accentCard(palette),
      child: Row(
        children: <Widget>[
          ChHexBadge(
            icon: Icons.graphic_eq_rounded,
            palette: palette,
            size: 62,
          ),
          const SizedBox(width: ChSpace.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'SIN PISTA',
                  style: chEyebrow(palette, size: 9.5, color: palette.accent),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tu biblioteca empieza aquí',
                  style: chTitle(palette, size: 17),
                ),
                const SizedBox(height: 3),
                Text(
                  'Elige una carpeta: CyberHex la recorre en tu equipo, sin subir nada.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ChSpace.sm),
          FilledButton(
            onPressed: onOpenLibrary,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('Escanear'),
          ),
        ],
      ),
    );
  }

  Widget _nowPlaying() {
    final title = snapshot.title.isEmpty ? 'Sin título' : snapshot.title;
    final subtitle = <String>[
      if (snapshot.artist.isNotEmpty) snapshot.artist,
      if (snapshot.album.isNotEmpty) snapshot.album,
    ].join(' · ');
    return ChSurface(
      radius: ChRadius.xl,
      elevated: true,
      padding: EdgeInsets.zero,
      onTap: onOpen,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ChRadius.xl),
        child: Stack(
          children: <Widget>[
            if (snapshot.cover != null)
              Positioned.fill(
                child: ChBlurredCover(
                  cover: snapshot.cover!,
                  sigma: 34,
                  opacity: 0.55,
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      palette.surfaceHigh.withValues(alpha: 0.72),
                      palette.surface.withValues(alpha: 0.94),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(ChSpace.lg - 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      ChCoverThumb(
                        seed: title,
                        palette: palette,
                        cover: snapshot.cover,
                        size: 72,
                        radius: 16,
                        hex: snapshot.cover == null,
                        glow: snapshot.playing,
                      ),
                      const SizedBox(width: ChSpace.md + 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                if (snapshot.playing)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChPlayingBars(
                                      color: palette.accent,
                                      size: 12,
                                    ),
                                  ),
                                Text(
                                  snapshot.playing
                                      ? 'EN REPRODUCCIÓN'
                                      : 'EN PAUSA',
                                  style: chEyebrow(
                                    palette,
                                    size: 9,
                                    color: palette.accent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: chTitle(palette, size: 17),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle.isEmpty ? 'Desconocido' : subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: ChSpace.sm),
                      ChPlayButton(
                        playing: snapshot.playing,
                        busy: snapshot.busy,
                        onPressed: snapshot.busy ? null : onToggle,
                        size: 50,
                      ),
                    ],
                  ),
                  const SizedBox(height: ChSpace.md),
                  ValueListenableBuilder<double>(
                    valueListenable: position,
                    builder: (context, value, _) {
                      final duration = snapshot.duration;
                      final progress = duration > 0
                          ? (value / duration).clamp(0.0, 1.0).toDouble()
                          : 0.0;
                      return Column(
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(ChRadius.pill),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: palette.surfaceHigh,
                              color: palette.accent,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                _clock(value),
                                style: chMono(palette, size: 9.5),
                              ),
                              Text(
                                duration > 0 ? _clock(duration) : '--:--',
                                style: chMono(palette, size: 9.5),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

class _AlbumRail extends StatelessWidget {
  const _AlbumRail({
    required this.albums,
    required this.palette,
    required this.onOpen,
  });

  final List<LibraryAlbum> albums;
  final CyberHexPalette palette;
  final ValueChanged<LibraryAlbum> onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: ChSpace.md),
        itemBuilder: (context, index) {
          final album = albums[index];
          return SizedBox(
            width: 136,
            child: ChPressable(
              onTap: () => onOpen(album),
              radius: ChRadius.md,
              semanticLabel: 'Álbum ${album.name}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ChCoverThumb(
                    seed: album.name,
                    palette: palette,
                    size: 136,
                    hex: true,
                  ),
                  const SizedBox(height: ChSpace.sm),
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.foreground,
                    ),
                  ),
                  Text(
                    album.artist.isEmpty
                        ? '${album.count} pistas'
                        : '${album.artist} · ${album.count}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: palette.muted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({
    required this.palette,
    required this.onLibrary,
    required this.onPlaylists,
    required this.onRadio,
    required this.onStats,
  });

  final CyberHexPalette palette;
  final VoidCallback onLibrary;
  final VoidCallback onPlaylists;
  final VoidCallback onRadio;
  final VoidCallback onStats;

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.library_music_rounded,
        label: 'Biblioteca',
        onTap: onLibrary,
      ),
      (icon: Icons.queue_music_rounded, label: 'Listas', onTap: onPlaylists),
      (icon: Icons.radio_rounded, label: 'Radio', onTap: onRadio),
      (icon: Icons.insights_rounded, label: 'Estadísticas', onTap: onStats),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.none,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: ChSpace.sm),
            _Shortcut(item: items[i], palette: palette),
          ],
        ],
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.item, required this.palette});

  final ({IconData icon, String label, VoidCallback onTap}) item;
  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return ChPressable(
      onTap: item.onTap,
      radius: ChRadius.pill,
      semanticLabel: item.label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: ChSpace.lg,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: palette.surfaceHigh.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(ChRadius.pill),
          border: Border.all(color: palette.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(item.icon, size: 17, color: palette.accent),
            const SizedBox(width: ChSpace.sm),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.stats,
    required this.palette,
    required this.onOpen,
  });

  final StatsStore stats;
  final CyberHexPalette palette;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final empty = stats.totalPlays == 0;
    return ChSurface(
      radius: ChRadius.lg,
      padding: EdgeInsets.zero,
      onTap: onOpen,
      gradient: ChGradient.accentCard(palette, strength: 0.16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: empty
            ? Row(
                children: <Widget>[
                  Icon(Icons.history_rounded, color: palette.muted, size: 18),
                  const SizedBox(width: ChSpace.sm + 2),
                  Expanded(
                    child: Text(
                      'Aún no hay reproducciones registradas.',
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  Expanded(
                    child: _Metric(
                      value: '${stats.tracks.length}',
                      label: 'PISTAS',
                      palette: palette,
                    ),
                  ),
                  _Divider(palette: palette),
                  Expanded(
                    child: _Metric(
                      value: '${stats.totalPlays}',
                      label: 'REPRODUCCIONES',
                      palette: palette,
                    ),
                  ),
                  _Divider(palette: palette),
                  Expanded(
                    child: _Metric(
                      value: _minutes(stats.totalMinutes),
                      label: 'MINUTOS',
                      palette: palette,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static String _minutes(double value) {
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
    return value.round().toString();
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.palette,
  });

  final String value;
  final String label;
  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(value, style: chTitle(palette, size: 19, letterSpacing: 0)),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: chMono(palette, size: 8, letterSpacing: 0.8),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: palette.border.withValues(alpha: 0.45),
    );
  }
}

class _RecentRail extends StatelessWidget {
  const _RecentRail({
    required this.entries,
    required this.palette,
    required this.onPlay,
  });

  final List<HistoryEntry> entries;
  final CyberHexPalette palette;
  final ValueChanged<String> onPlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 186,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: ChSpace.md),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _RecentCard(
            entry: entry,
            palette: palette,
            onTap: () => onPlay(entry.path),
          );
        },
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.entry,
    required this.palette,
    required this.onTap,
  });

  final HistoryEntry entry;
  final CyberHexPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final artist = entry.artist.trim();
    return SizedBox(
      width: 132,
      child: ChPressable(
        onTap: onTap,
        radius: ChRadius.md,
        semanticLabel: 'Reproducir ${entry.label}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ChCoverThumb(
              seed: entry.label,
              palette: palette,
              size: 132,
              hex: true,
            ),
            const SizedBox(height: ChSpace.sm),
            Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.foreground,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              artist.isEmpty ? 'Desconocido' : artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopTracks extends StatelessWidget {
  const _TopTracks({
    required this.tracks,
    required this.palette,
    required this.playingPath,
    required this.onPlay,
  });

  final List<TrackStat> tracks;
  final CyberHexPalette palette;
  final String? playingPath;
  final ValueChanged<String> onPlay;

  @override
  Widget build(BuildContext context) {
    return ChSurface(
      radius: ChRadius.lg,
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (var i = 0; i < tracks.length; i++) ...<Widget>[
            if (i > 0) ChHairline(palette: palette, indent: 64),
            _TopTrackRow(
              rank: i + 1,
              stat: tracks[i],
              palette: palette,
              playing: tracks[i].path == playingPath,
              onTap: () => onPlay(tracks[i].path),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopTrackRow extends StatelessWidget {
  const _TopTrackRow({
    required this.rank,
    required this.stat,
    required this.palette,
    required this.playing,
    required this.onTap,
  });

  final int rank;
  final TrackStat stat;
  final CyberHexPalette palette;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 22,
              child: Text(
                rank.toString().padLeft(2, '0'),
                style: chMono(
                  palette,
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: palette.accent,
                ),
              ),
            ),
            const SizedBox(width: ChSpace.sm),
            ChCoverThumb(
              seed: stat.label,
              palette: palette,
              size: 40,
              radius: ChRadius.sm,
              hex: true,
            ),
            const SizedBox(width: ChSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    stat.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.foreground,
                    ),
                  ),
                  Text(
                    stat.artist.trim().isEmpty ? 'Desconocido' : stat.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: palette.muted),
                  ),
                ],
              ),
            ),
            if (playing) ...<Widget>[
              ChPlayingBars(color: palette.accent, size: 12),
              const SizedBox(width: ChSpace.sm),
            ],
            Text('${stat.plays}×', style: chMono(palette, size: 11)),
          ],
        ),
      ),
    );
  }
}
