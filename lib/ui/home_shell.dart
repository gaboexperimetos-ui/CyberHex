import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/favorites_store.dart';
import '../core/player_controller.dart';
import '../core/playlist_store.dart';
import '../core/radio_store.dart';
import '../core/stats_store.dart';
import '../core/theme_controller.dart';
import '../platform/connections.dart';
import '../platform/desktop_channel.dart';
import '../theme.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'now_playing_route.dart';
import 'playlists_page.dart';
import 'radio_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';

/// Armazón de la app: cuatro pestañas, barra inferior y mini-reproductor.
///
/// Cada pestaña conserva su estado (se apilan en un [IndexedStack]) y los
/// almacenes viven aquí para que biblioteca, listas, estadísticas e inicio
/// compartan la misma instancia. El reproductor completo se abre encima,
/// deslizando desde abajo, y vuelve a la pestaña que estuviera activa.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.controller,
    required this.theme,
    this.desktop,
    this.connections,
  });

  final PlayerController controller;
  final ThemeController theme;
  final DesktopChannel? desktop;
  final CyberHexConnections? connections;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final PlaylistStore _playlists = PlaylistStore();
  late final StatsStore _stats = StatsStore();
  late final FavoritesStore _favorites = FavoritesStore();
  late final LongTrackMemory _longTracks = LongTrackMemory();
  late final RadioStore _radio = RadioStore();

  @override
  void initState() {
    super.initState();
    // Si se inyectan, las páginas no cargan los almacenes por su cuenta: lo
    // hace el armazón, una sola vez, sin bloquear el primer frame.
    unawaited(_playlists.load());
    unawaited(_stats.load());
    unawaited(_favorites.load());
    unawaited(_longTracks.load());
  }

  @override
  void dispose() {
    _playlists.dispose();
    _stats.dispose();
    _favorites.dispose();
    _longTracks.dispose();
    _radio.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  void _openPlayer() {
    openNowPlaying(
      context,
      controller: widget.controller,
      theme: widget.theme,
      desktop: widget.desktop,
      connections: widget.connections,
    );
  }

  void _openRadio() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RadioPage(
          store: _radio,
          controller: widget.controller,
          onOpenPlayer: _openPlayer,
        ),
      ),
    );
  }

  Future<void> _openStats() async {
    await _stats.load();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatsPage(stats: _stats),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.theme.palette;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(
            controller: widget.controller,
            theme: widget.theme,
            stats: _stats,
            onOpenPlayer: _openPlayer,
            onOpenLibrary: () => _select(1),
            onOpenPlaylists: () => _select(2),
            onOpenRadio: _openRadio,
            onOpenStats: () => unawaited(_openStats()),
          ),
          LibraryPage(
            controller: widget.controller,
            playlists: _playlists,
            stats: _stats,
            favorites: _favorites,
            longTracks: _longTracks,
            onOpenPlayer: _openPlayer,
          ),
          PlaylistsPage(
            controller: widget.controller,
            store: _playlists,
            stats: _stats,
            onOpenPlayer: _openPlayer,
          ),
          SettingsPage(
            theme: widget.theme,
            player: widget.controller,
            desktop: widget.desktop,
            connections: widget.connections,
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: palette.border.withValues(alpha: 0.5)),
          ),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: palette.surface,
            surfaceTintColor: Colors.transparent,
            indicatorColor: palette.accent.withValues(alpha: 0.16),
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? palette.accent : palette.muted,
              );
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: 24,
                color: selected ? palette.accent : palette.muted,
              );
            }),
          ),
          child: NavigationBar(
            height: 68,
            elevation: 0,
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Biblioteca',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_outlined),
                selectedIcon: Icon(Icons.queue_music_rounded),
                label: 'Listas',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: 'Ajustes',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
