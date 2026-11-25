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
import 'design/ch_ambient.dart';
import 'kit/ch_kit.dart';
import 'search_sheet.dart';

/// Pestaña de inicio: la portada de la app.
///
/// La jerarquía es la de un disco: primero suena algo, después lo que estabas
/// escuchando, luego tu biblioteca y al final las herramientas. En ventanas
/// anchas las herramientas pasan a una columna lateral para que la portada no
/// se estire en una sola tira vertical.
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

        final main = <Widget>[
          _Hero(
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
            const SizedBox(height: ChSpace.md),
            _RecentRail(
              entries: recents,
              palette: palette,
              onPlay: (path) => unawaited(_play(context, controller, path)),
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
            const SizedBox(height: ChSpace.md),
            _AlbumRail(
              albums: albums.take(12).toList(growable: false),
              palette: palette,
              onOpen: (album) => onOpenAlbum!(album.name),
            ),
          ],
        ];

        final side = <Widget>[
          ChSectionHeader('Explorar', palette: palette),
          const SizedBox(height: ChSpace.md),
          _ExploreGrid(
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
            const SizedBox(height: ChSpace.md),
            _TopTracks(
              tracks: top,
              palette: palette,
              playingPath: currentPath,
              onPlay: (path) => unawaited(_play(context, controller, path)),
            ),
          ],
          const SizedBox(height: ChSpace.xl),
          ChSectionHeader(
            'Tu actividad',
            palette: palette,
            actionLabel: 'Detalle',
            onAction: onOpenStats,
          ),
          const SizedBox(height: ChSpace.md),
          _ActivityCard(stats: stats, palette: palette, onOpen: onOpenStats),
        ];

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
              backgroundColor: Colors.transparent,
              body: ChAmbient(
                palette: palette,
                child: SafeArea(
                  bottom: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 920;
                      final pad = wide ? 30.0 : 18.0;
                      return ListView(
                        padding: EdgeInsets.fromLTRB(pad, 16, pad, 34),
                        children: <Widget>[
                          _Header(
                            palette: palette,
                            onSearch: openSearch,
                            compact: constraints.maxWidth < 620,
                          ),
                          const SizedBox(height: ChSpace.xl),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  flex: 6,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      ...main,
                                      if (recents.isEmpty &&
                                          albums.isEmpty) ...[
                                        const SizedBox(height: ChSpace.xl),
                                        _GettingStarted(
                                          palette: palette,
                                          onOpenLibrary: onOpenLibrary,
                                          onOpenStats: onOpenStats,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: ChSpace.xl),
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: side,
                                  ),
                                ),
                              ],
                            )
                          else
                            ...main,
                          if (!wide) ...<Widget>[
                            const SizedBox(height: ChSpace.xl),
                            ...side,
                          ],
                          if (!wide && recents.isEmpty && albums.isEmpty) ...[
                            const SizedBox(height: ChSpace.xl),
                            _GettingStarted(
                              palette: palette,
                              onOpenLibrary: onOpenLibrary,
                              onOpenStats: onOpenStats,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
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

/// Cabecera: ceja, titular grande, fecha y buscador.
class _Header extends StatelessWidget {
  const _Header({required this.palette, this.onSearch, this.compact = false});

  final CyberHexPalette palette;
  final VoidCallback? onSearch;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: ChEditorialHeader(
            eyebrow: 'CyberHex · biblioteca local',
            title: 'Tu música, tu máquina',
            palette: palette,
            titleSize: compact ? 28 : 36,
            subtitle: '${_dateLabel()} · motor nativo · 48 kHz',
          ),
        ),
        const SizedBox(width: ChSpace.md),
        if (onSearch != null)
          _IconGlass(
            palette: palette,
            icon: Icons.search_rounded,
            tooltip: 'Buscar (Ctrl+F)',
            onTap: onSearch!,
          ),
        if (!compact) ...<Widget>[
          const SizedBox(width: ChSpace.sm),
          _StatusPill(palette: palette),
        ],
      ],
    );
  }

  static const List<String> _months = <String>[
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  static String _dateLabel() {
    final now = DateTime.now();
    return '${now.day} de ${_months[now.month - 1]}';
  }
}

class _IconGlass extends StatelessWidget {
  const _IconGlass({
    required this.palette,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final CyberHexPalette palette;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ChPressable(
        onTap: onTap,
        radius: _size / 2,
        semanticLabel: tooltip,
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.surfaceHigh.withValues(alpha: 0.5),
            border: Border.all(
              color: palette.foreground.withValues(alpha: 0.09),
            ),
          ),
          child: Icon(icon, size: _size * 0.46, color: palette.foreground),
        ),
      ),
    );
  }
}

/// Insignia técnica de la cabecera: recuerda que el motor es propio.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.palette});

  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Motor nativo CyberHex · 48 kHz',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: palette.surfaceHigh.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(ChRadius.pill),
          border: Border.all(color: palette.foreground.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.7),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
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
class _Hero extends StatelessWidget {
  const _Hero({
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
    return snapshot.hasTrack ? _nowPlaying(context) : _onboarding(context);
  }

  Widget _onboarding(BuildContext context) {
    return ChGlass(
      radius: ChRadius.xl,
      padding: const EdgeInsets.all(ChSpace.lg),
      onTap: onOpenLibrary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 520;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'SIN PISTA',
                style: chEyebrow(palette, size: 9.5, color: palette.accent),
              ),
              const SizedBox(height: 6),
              Text(
                'Tu biblioteca empieza aquí',
                style: chTitle(palette, size: narrow ? 20 : 24),
              ),
              const SizedBox(height: 6),
              Text(
                'Elige una carpeta: CyberHex la recorre en tu equipo, '
                'sin subir nada a ningún sitio.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: palette.muted,
                ),
              ),
              const SizedBox(height: ChSpace.md),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final format in const <String>[
                    'FLAC',
                    'MP3',
                    'WAV',
                    'OGG',
                    'OPUS',
                    'M4A',
                    'AAC',
                    'ALAC',
                  ])
                    _FormatChip(label: format, palette: palette),
                ],
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: onOpenLibrary,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Escanear'),
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ChHexBadge(
                  icon: Icons.graphic_eq_rounded,
                  palette: palette,
                  size: 58,
                ),
                const SizedBox(height: ChSpace.md),
                copy,
                const SizedBox(height: ChSpace.md),
                button,
              ],
            );
          }
          return Row(
            children: <Widget>[
              ChHexBadge(
                icon: Icons.graphic_eq_rounded,
                palette: palette,
                size: 92,
              ),
              const SizedBox(width: ChSpace.lg),
              Expanded(child: copy),
              const SizedBox(width: ChSpace.md),
              button,
            ],
          );
        },
      ),
    );
  }

  Widget _nowPlaying(BuildContext context) {
    final title = snapshot.title.isEmpty ? 'Sin título' : snapshot.title;
    final subtitle = <String>[
      if (snapshot.artist.isNotEmpty) snapshot.artist,
      if (snapshot.album.isNotEmpty) snapshot.album,
    ].join(' · ');
    final cover = snapshot.cover;
    return ChGlass(
      radius: ChRadius.xl,
      padding: EdgeInsets.zero,
      onTap: onOpen,
      tint: palette.surface,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ChRadius.xl),
        child: Stack(
          children: <Widget>[
            if (cover != null)
              Positioned.fill(
                child: ChBlurredCover(cover: cover, sigma: 40, opacity: 0.6),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color.lerp(
                        palette.surfaceHigh,
                        palette.accent,
                        0.16,
                      )!.withValues(alpha: 0.72),
                      palette.surface.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(ChSpace.lg),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 520;
                  final art = ChCoverThumb(
                    seed: title,
                    palette: palette,
                    cover: cover,
                    size: narrow ? 104 : 148,
                    radius: 22,
                    hex: cover == null,
                    glow: snapshot.playing,
                  );
                  final copy = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (snapshot.playing)
                            Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: ChPlayingBars(
                                color: palette.accent,
                                size: 13,
                              ),
                            ),
                          Text(
                            snapshot.playing ? 'EN REPRODUCCIÓN' : 'EN PAUSA',
                            style: chEyebrow(
                              palette,
                              size: 9,
                              color: palette.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: chTitle(palette, size: narrow ? 20 : 26),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle.isEmpty ? 'Desconocido' : subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: palette.muted),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  ChRadius.pill,
                                ),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 4,
                                  backgroundColor: palette.background
                                      .withValues(alpha: 0.55),
                                  color: palette.accent,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
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
                  );
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            art,
                            const SizedBox(width: ChSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
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
                                  const SizedBox(height: 4),
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: chTitle(palette, size: 19),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle.isEmpty ? 'Desconocido' : subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: palette.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ChPlayButton(
                              playing: snapshot.playing,
                              busy: snapshot.busy,
                              onPressed: snapshot.busy ? null : onToggle,
                              size: 46,
                            ),
                          ],
                        ),
                        const SizedBox(height: ChSpace.md),
                        _progress(),
                      ],
                    );
                  }
                  return Row(
                    children: <Widget>[
                      art,
                      const SizedBox(width: ChSpace.lg),
                      Expanded(child: copy),
                      const SizedBox(width: ChSpace.md),
                      ChPlayButton(
                        playing: snapshot.playing,
                        busy: snapshot.busy,
                        onPressed: snapshot.busy ? null : onToggle,
                        size: 58,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progress() {
    return ValueListenableBuilder<double>(
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
                backgroundColor: palette.background.withValues(alpha: 0.55),
                color: palette.accent,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(_clock(value), style: chMono(palette, size: 9.5)),
                Text(
                  duration > 0 ? _clock(duration) : '--:--',
                  style: chMono(palette, size: 9.5),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _clock(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.label, required this.palette});

  final String label;
  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ChRadius.pill),
        border: Border.all(color: palette.accent.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: chMono(
          palette,
          size: 9,
          weight: FontWeight.w600,
          color: palette.accent,
        ),
      ),
    );
  }
}

/// Fila horizontal de tarjetas con carátula grande.
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
      height: 206,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: ChSpace.md),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _MediaCard(
            palette: palette,
            seed: entry.label,
            title: entry.label,
            subtitle: entry.artist.trim().isEmpty
                ? 'Desconocido'
                : entry.artist,
            size: 150,
            onTap: () => onPlay(entry.path),
            semanticLabel: 'Reproducir ${entry.label}',
          );
        },
      ),
    );
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
      height: 216,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: ChSpace.md),
        itemBuilder: (context, index) {
          final album = albums[index];
          return _MediaCard(
            palette: palette,
            seed: album.name,
            title: album.name,
            subtitle: album.artist.isEmpty
                ? (album.count == 1 ? '1 pista' : '${album.count} pistas')
                : '${album.artist} · ${album.count}',
            size: 160,
            onTap: () => onOpen(album),
            semanticLabel: 'Álbum ${album.name}',
          );
        },
      ),
    );
  }
}

/// Tarjeta de carátula: arte grande, título y contexto.
class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.palette,
    required this.seed,
    required this.title,
    required this.subtitle,
    required this.size,
    required this.onTap,
    required this.semanticLabel,
  });

  final CyberHexPalette palette;
  final String seed;
  final String title;
  final String subtitle;
  final double size;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: ChPressable(
        onTap: onTap,
        radius: ChRadius.lg,
        semanticLabel: semanticLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ChCoverThumb(seed: seed, palette: palette, size: size, hex: true),
            const SizedBox(height: ChSpace.sm + 2),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: palette.foreground,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
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

/// Accesos a las herramientas, como baldosas de cristal.
class _ExploreGrid extends StatelessWidget {
  const _ExploreGrid({
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
    final items =
        <({IconData icon, String label, String hint, VoidCallback onTap})>[
          (
            icon: Icons.library_music_rounded,
            label: 'Biblioteca',
            hint: 'Tus pistas',
            onTap: onLibrary,
          ),
          (
            icon: Icons.queue_music_rounded,
            label: 'Listas',
            hint: 'Colecciones',
            onTap: onPlaylists,
          ),
          (
            icon: Icons.radio_rounded,
            label: 'Radio',
            hint: 'En directo',
            onTap: onRadio,
          ),
          (
            icon: Icons.insights_rounded,
            label: 'Estadísticas',
            hint: 'Tu historial',
            onTap: onStats,
          ),
        ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 4 : 2;
        final spacing = ChSpace.sm;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final item in items)
              SizedBox(
                width: width,
                child: _ExploreTile(
                  palette: palette,
                  icon: item.icon,
                  label: item.label,
                  hint: item.hint,
                  onTap: item.onTap,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ExploreTile extends StatelessWidget {
  const _ExploreTile({
    required this.palette,
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final CyberHexPalette palette;
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChPressable(
      onTap: onTap,
      radius: ChRadius.lg,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.all(ChSpace.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ChRadius.lg),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              palette.surfaceHigh.withValues(alpha: 0.55),
              palette.surface.withValues(alpha: 0.42),
            ],
          ),
          border: Border.all(color: palette.foreground.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ChHexBadge(icon: icon, palette: palette, size: 34),
            const SizedBox(height: ChSpace.sm),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.foreground,
              ),
            ),
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: palette.muted),
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
    return ChGlass(
      radius: ChRadius.lg,
      padding: EdgeInsets.zero,
      blur: 12,
      elevated: false,
      child: Column(
        children: <Widget>[
          for (var i = 0; i < tracks.length; i++) ...<Widget>[
            if (i > 0) ChHairline(palette: palette, indent: 64, opacity: 0.22),
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
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
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
              size: 38,
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
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.foreground,
                    ),
                  ),
                  Text(
                    stat.artist.trim().isEmpty ? 'Desconocido' : stat.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: palette.muted),
                  ),
                ],
              ),
            ),
            if (playing) ...<Widget>[
              ChPlayingBars(color: palette.accent, size: 12),
              const SizedBox(width: ChSpace.sm),
            ],
            Text('${stat.plays}×', style: chMono(palette, size: 10.5)),
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
    return ChGlass(
      radius: ChRadius.lg,
      padding: EdgeInsets.zero,
      blur: 12,
      elevated: false,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
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
                      label: stats.tracks.length == 1 ? 'PISTA' : 'PISTAS',
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
        Text(value, style: chTitle(palette, size: 21, letterSpacing: 0)),
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
      height: 30,
      color: palette.foreground.withValues(alpha: 0.08),
    );
  }
}

/// Primeros pasos cuando aún no hay nada escaneado: llena la portada con una
/// ruta concreta en vez de dejar un vacío.
class _GettingStarted extends StatelessWidget {
  const _GettingStarted({
    required this.palette,
    required this.onOpenLibrary,
    required this.onOpenStats,
  });

  final CyberHexPalette palette;
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenStats;

  @override
  Widget build(BuildContext context) {
    final steps =
        <({IconData icon, String title, String body, VoidCallback onTap})>[
          (
            icon: Icons.folder_open_rounded,
            title: 'Elige una carpeta',
            body:
                'CyberHex recorre FLAC, MP3, WAV, OGG, OPUS, M4A, AAC y ALAC '
                'en tu disco.',
            onTap: onOpenLibrary,
          ),
          (
            icon: Icons.graphic_eq_rounded,
            title: 'Escucha sin nube',
            body:
                'El motor nativo decodifica y procesa en local. Nada sale de '
                'este equipo.',
            onTap: onOpenLibrary,
          ),
          (
            icon: Icons.insights_rounded,
            title: 'Mira tu historial',
            body:
                'Reproducciones, minutos y pistas favoritas se guardan en tu '
                'máquina.',
            onTap: onOpenStats,
          ),
        ];
    return ChGlass(
      radius: ChRadius.xl,
      padding: const EdgeInsets.all(ChSpace.lg),
      blur: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'PRIMEROS PASOS',
                  style: chEyebrow(palette, size: 9.5, color: palette.accent),
                ),
              ),
              TextButton.icon(
                onPressed: onOpenLibrary,
                icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                label: const Text('Abrir biblioteca'),
              ),
            ],
          ),
          const SizedBox(height: ChSpace.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 3 : 1;
              const spacing = ChSpace.md;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: <Widget>[
                  for (final step in steps)
                    SizedBox(
                      width: width,
                      child: ChPressable(
                        onTap: step.onTap,
                        radius: ChRadius.md,
                        semanticLabel: step.title,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ChHexBadge(
                              icon: step.icon,
                              palette: palette,
                              size: 38,
                            ),
                            const SizedBox(height: ChSpace.sm),
                            Text(
                              step.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                                color: palette.foreground,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              step.body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.45,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
