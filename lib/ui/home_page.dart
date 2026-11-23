import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/library_browse.dart';
import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../core/stats_store.dart';
import '../core/theme_controller.dart';
import '../theme.dart';
import 'hex_cover.dart';
import 'search_sheet.dart';

/// Pestaña de inicio: el punto de entrada de la app.
///
/// Muestra qué está sonando (o invita a escanear una carpeta), cuatro accesos
/// directos al resto de la app y un resumen de la actividad guardada por
/// [StatsStore]. No reproduce nada por su cuenta: delega en el controlador y en
/// las páginas que ya existen.
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
              body: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color.lerp(palette.background, palette.primary, 0.38)!,
                      palette.background,
                    ],
                    stops: const <double>[0, 0.45],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                    children: [
                      _Header(palette: palette, onSearch: openSearch),
                      const SizedBox(height: 20),
                      _ContinueCard(
                        snapshot: snapshot,
                        position: controller.position,
                        palette: palette,
                        onOpen: onOpenPlayer,
                        onToggle: controller.toggle,
                        onOpenLibrary: onOpenLibrary,
                      ),
                      const SizedBox(height: 26),
                      if (recents.isNotEmpty) ...[
                        _SectionHeader(
                          'Sigue escuchando',
                          palette: palette,
                          onSeeAll: onOpenStats,
                        ),
                        const SizedBox(height: 10),
                        _RecentRail(
                          entries: recents,
                          palette: palette,
                          onPlay: (path) =>
                              unawaited(_play(context, controller, path)),
                        ),
                        const SizedBox(height: 26),
                      ],
                      if (albums.isNotEmpty) ...[
                        _SectionHeader(
                          'Álbumes',
                          palette: palette,
                          onSeeAll: onOpenLibrary,
                        ),
                        const SizedBox(height: 10),
                        _AlbumRail(
                          albums: albums.take(12).toList(growable: false),
                          palette: palette,
                          onOpen: (album) => onOpenAlbum!(album.name),
                        ),
                        const SizedBox(height: 26),
                      ],
                      _SectionTitle('Explorar', palette: palette),
                      const SizedBox(height: 12),
                      _Shortcuts(
                        palette: palette,
                        onLibrary: onOpenLibrary,
                        onPlaylists: onOpenPlaylists,
                        onRadio: onOpenRadio,
                        onStats: onOpenStats,
                      ),
                      if (top.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        _SectionHeader(
                          'Lo que más suena',
                          palette: palette,
                          onSeeAll: onOpenStats,
                        ),
                        const SizedBox(height: 10),
                        _TopTracks(
                          tracks: top,
                          palette: palette,
                          onPlay: (path) =>
                              unawaited(_play(context, controller, path)),
                        ),
                      ],
                      const SizedBox(height: 26),
                      _SectionTitle('Tu actividad', palette: palette),
                      const SizedBox(height: 12),
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
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: 'Righteous',
                  fontSize: 26,
                  letterSpacing: 4,
                  color: palette.foreground,
                ),
                children: [
                  const TextSpan(text: 'CYBER'),
                  TextSpan(
                    text: 'HEX',
                    style: TextStyle(
                      color: palette.accent,
                      shadows: [
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
            const SizedBox(height: 2),
            Text(
              'Tu música, tu máquina',
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ],
        ),
        const Spacer(),
        if (onSearch != null) ...[
          IconButton(
            tooltip: 'Buscar (Ctrl+F)',
            onPressed: onSearch,
            icon: Icon(Icons.search_rounded, color: palette.foreground),
          ),
          const SizedBox(width: 4),
        ],
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.accent.withValues(alpha: 0.14),
            border: Border.all(color: palette.accent.withValues(alpha: 0.35)),
          ),
          child: Icon(
            Icons.graphic_eq_rounded,
            color: palette.accent,
            size: 22,
          ),
        ),
      ],
    );
  }
}

/// Carrusel horizontal de álbumes de la biblioteca escaneada.
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
      height: 178,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final album = albums[index];
          return SizedBox(
            width: 108,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onOpen(album),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HexCover(seed: album.seed, palette: palette, size: 108),
                  const SizedBox(height: 8),
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
                    style: TextStyle(fontSize: 11, color: palette.muted),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.palette});

  final String text;
  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: palette.foreground,
      ),
    );
  }
}

/// Tarjeta «continuar»: la pista actual o una invitación a abrir la biblioteca.
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
    final hasTrack = snapshot.hasTrack;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: hasTrack ? onOpen : onOpenLibrary,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.border.withValues(alpha: 0.6)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                palette.surfaceHigh,
                Color.lerp(palette.surface, palette.primary, 0.22)!,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Cover(cover: snapshot.cover, palette: palette),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hasTrack
                                ? (snapshot.title.isEmpty
                                      ? 'Sin título'
                                      : snapshot.title)
                                : 'Aún no hay nada sonando',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: palette.foreground,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            hasTrack
                                ? (snapshot.artist.isEmpty
                                      ? 'Desconocido'
                                      : snapshot.artist)
                                : 'Escanea una carpeta o abre un archivo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasTrack)
                      IconButton.filled(
                        tooltip: snapshot.playing ? 'Pausa' : 'Reproducir',
                        onPressed: snapshot.busy ? null : onToggle,
                        style: IconButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor: palette.onAccent,
                          minimumSize: const Size(46, 46),
                        ),
                        icon: Icon(
                          snapshot.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 26,
                        ),
                      )
                    else
                      IconButton.filledTonal(
                        tooltip: 'Abrir biblioteca',
                        onPressed: onOpenLibrary,
                        icon: const Icon(Icons.library_music_rounded),
                      ),
                  ],
                ),
                if (hasTrack) ...[
                  const SizedBox(height: 12),
                  ValueListenableBuilder<double>(
                    valueListenable: position,
                    builder: (context, value, _) {
                      final progress = snapshot.duration > 0
                          ? (value / snapshot.duration)
                                .clamp(0.0, 1.0)
                                .toDouble()
                          : 0.0;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: palette.surface,
                          color: palette.accent,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.cover, required this.palette});

  final Uint8List? cover;
  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    final image = cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 64,
        height: 64,
        child: image == null
            ? ColoredBox(
                color: palette.surface,
                child: Icon(
                  Icons.album_rounded,
                  color: palette.accent,
                  size: 30,
                ),
              )
            : Image.memory(
                image,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: 160,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: palette.surface,
                  child: Icon(
                    Icons.album_rounded,
                    color: palette.accent,
                    size: 30,
                  ),
                ),
              ),
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
    final items =
        <({IconData icon, String label, String hint, VoidCallback onTap})>[
          (
            icon: Icons.library_music_rounded,
            label: 'Biblioteca',
            hint: 'Escanea y ordena',
            onTap: onLibrary,
          ),
          (
            icon: Icons.queue_music_rounded,
            label: 'Listas',
            hint: 'Tus colecciones',
            onTap: onPlaylists,
          ),
          (
            icon: Icons.radio_rounded,
            label: 'Radio',
            hint: 'Emisoras online',
            onTap: onRadio,
          ),
          (
            icon: Icons.insights_rounded,
            label: 'Estadísticas',
            hint: 'Lo que escuchas',
            onTap: onStats,
          ),
        ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.05,
      children: [
        for (final item in items)
          _ShortcutCard(
            icon: item.icon,
            label: item.label,
            hint: item.hint,
            palette: palette,
            onTap: item.onTap,
          ),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final CyberHexPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: palette.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.foreground,
                      ),
                    ),
                    Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border.withValues(alpha: 0.5)),
          ),
          child: empty
              ? Row(
                  children: [
                    Icon(Icons.history_rounded, color: palette.muted, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Aún no hay reproducciones registradas.',
                        style: TextStyle(fontSize: 12, color: palette.muted),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        value: '${stats.tracks.length}',
                        label: 'pistas',
                        palette: palette,
                      ),
                    ),
                    _Divider(palette: palette),
                    Expanded(
                      child: _Metric(
                        value: '${stats.totalPlays}',
                        label: 'reproducciones',
                        palette: palette,
                      ),
                    ),
                    _Divider(palette: palette),
                    Expanded(
                      child: _Metric(
                        value: _minutes(stats.totalMinutes),
                        label: 'minutos',
                        palette: palette,
                      ),
                    ),
                  ],
                ),
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
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10.5, color: palette.muted)),
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
      color: palette.border.withValues(alpha: 0.5),
    );
  }
}

/// Título de sección con un acceso opcional «Ver todo» a la derecha.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {required this.palette, this.onSeeAll});

  final String text;
  final CyberHexPalette palette;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SectionTitle(text, palette: palette)),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              foregroundColor: palette.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Ver todo'),
          ),
      ],
    );
  }
}

/// Carrusel horizontal de lo último escuchado.
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
      height: 166,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
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
      width: 112,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HexCover(seed: entry.label, palette: palette),
            const SizedBox(height: 8),
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
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lista compacta de las pistas más reproducidas.
class _TopTracks extends StatelessWidget {
  const _TopTracks({
    required this.tracks,
    required this.palette,
    required this.onPlay,
  });

  final List<TrackStat> tracks;
  final CyberHexPalette palette;
  final ValueChanged<String> onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            for (var i = 0; i < tracks.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: palette.border.withValues(alpha: 0.35),
                ),
              _TopTrackRow(
                rank: i + 1,
                stat: tracks[i],
                palette: palette,
                onTap: () => onPlay(tracks[i].path),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopTrackRow extends StatelessWidget {
  const _TopTrackRow({
    required this.rank,
    required this.stat,
    required this.palette,
    required this.onTap,
  });

  final int rank;
  final TrackStat stat;
  final CyberHexPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                rank.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontFamily: 'Righteous',
                  fontSize: 13,
                  color: palette.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${stat.plays}×',
              style: TextStyle(fontSize: 11.5, color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
