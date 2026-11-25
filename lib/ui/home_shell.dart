import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/favorites_store.dart';
import '../core/home_tab_store.dart';
import '../core/player_controller.dart';
import '../core/playlist_store.dart';
import '../core/radio_store.dart';
import '../core/stats_store.dart';
import '../core/theme_controller.dart';
import '../platform/connections.dart';
import '../platform/desktop_channel.dart';
import '../theme.dart';
import 'home_page.dart';
import 'kit/ch_kit.dart';
import 'library_page.dart';
import 'mini_player.dart';
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
    this.tabs,
  });

  final PlayerController controller;
  final ThemeController theme;
  final DesktopChannel? desktop;
  final CyberHexConnections? connections;

  /// Se inyecta en las pruebas; en producción el armazón crea el suyo.
  final HomeTabStore? tabs;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final HomeTabStore _tabs = widget.tabs ?? HomeTabStore();
  late final bool _ownsTabs = widget.tabs == null;

  late final PlaylistStore _playlists = PlaylistStore();
  late final StatsStore _stats = StatsStore();
  late final FavoritesStore _favorites = FavoritesStore();
  late final LongTrackMemory _longTracks = LongTrackMemory();
  late final RadioStore _radio = RadioStore();

  int get _index => _tabs.tab;

  String? _albumFocus;
  int _libraryFocus = 0;

  void _openAlbum(String album) {
    setState(() {
      _albumFocus = album;
      _libraryFocus++;
    });
    _tabs.setTab(1);
  }

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTabChanged);
    unawaited(_tabs.load());
    // Si se inyectan, las páginas no cargan los almacenes por su cuenta: lo
    // hace el armazón, una sola vez, sin bloquear el primer frame.
    unawaited(_playlists.load());
    unawaited(_stats.load());
    unawaited(_favorites.load());
    unawaited(_longTracks.load());
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    if (_ownsTabs) _tabs.dispose();
    _playlists.dispose();
    _stats.dispose();
    _favorites.dispose();
    _longTracks.dispose();
    _radio.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    chHaptic();
    _tabs.setTab(index);
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
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => StatsPage(stats: _stats)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.theme.palette;
    final size = MediaQuery.sizeOf(context);
    // En ventanas anchas (PC) la navegación pasa a una barra lateral: la
    // barra inferior se queda para el móvil. El umbral deja intacta la
    // disposición de una ventana de 800 px.
    final wide = size.width >= 900 && size.width > size.height;
    final navigationBar = _navigationBar(palette);
    final content = Column(
      children: [
        Expanded(
          child: IndexedStack(
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
                onOpenAlbum: _openAlbum,
              ),
              LibraryPage(
                controller: widget.controller,
                playlists: _playlists,
                stats: _stats,
                favorites: _favorites,
                longTracks: _longTracks,
                onOpenPlayer: _openPlayer,
                showMiniPlayer: false,
                focusAlbum: _albumFocus,
                focusRequest: _libraryFocus,
              ),
              PlaylistsPage(
                controller: widget.controller,
                store: _playlists,
                stats: _stats,
                onOpenPlayer: _openPlayer,
                showMiniPlayer: false,
              ),
              SettingsPage(
                theme: widget.theme,
                player: widget.controller,
                desktop: widget.desktop,
                connections: widget.connections,
              ),
            ],
          ),
        ),
        // Un único mini-reproductor para todas las pestañas: vive encima de
        // la barra de navegación y no se re-monta al cambiar de sección.
        MiniPlayer(controller: widget.controller, onOpen: _openPlayer),
      ],
    );
    // Una sola forma de árbol: el contenido vive siempre en el tercer hueco de
    // la fila. Al cruzar el umbral solo se sustituyen los dos primeros huecos
    // (barra lateral ↔ hueco vacío), así que las páginas no se recrean ni
    // pierden su estado al cambiar el tamaño de la ventana.
    final scaffold = Scaffold(
      body: Row(
        children: [
          if (wide) _navigationRail(palette) else const SizedBox.shrink(),
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: wide ? null : navigationBar,
    );
    // Atajos de escritorio: Ctrl/⌘ + 1..4 salta de pestaña sin soltar el
    // teclado. Los dígitos solos se dejan libres para los campos de búsqueda.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        for (var i = 0; i < 4; i++) ...<ShortcutActivator, VoidCallback>{
          SingleActivator(_digits[i], control: true): () => _select(i),
          SingleActivator(_digits[i], meta: true): () => _select(i),
        },
      },
      child: Focus(autofocus: true, child: scaffold),
    );
  }

  static const List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
  ];

  Widget _navigationBar(CyberHexPalette palette) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.border.withValues(alpha: 0.5)),
        ),
      ),
      child: NavigationBarTheme(
        data: _navigationTheme(palette),
        child: NavigationBar(
          height: 68,
          elevation: 0,
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: _destinations,
        ),
      ),
    );
  }

  Widget _navigationRail(CyberHexPalette palette) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomLeft,
          colors: <Color>[
            Color.lerp(palette.surface, palette.primary, 0.30)!,
            palette.surface,
            palette.background,
          ],
          stops: const <double>[0, 0.55, 1],
        ),
        border: Border(
          right: BorderSide(color: palette.foreground.withValues(alpha: 0.06)),
        ),
      ),
      child: NavigationRailTheme(
        data: NavigationRailThemeData(
          backgroundColor: Colors.transparent,
          indicatorColor: palette.accent.withValues(alpha: 0.16),
          indicatorShape: const StadiumBorder(),
          useIndicator: true,
          selectedIconTheme: IconThemeData(color: palette.accent, size: 22),
          unselectedIconTheme: IconThemeData(color: palette.muted, size: 22),
          selectedLabelTextStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: palette.foreground,
          ),
          unselectedLabelTextStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
            color: palette.muted,
          ),
        ),
        child: NavigationRail(
          extended: true,
          minExtendedWidth: 214,
          labelType: NavigationRailLabelType.none,
          groupAlignment: -0.72,
          selectedIndex: _index,
          onDestinationSelected: _select,
          leading: _RailBrand(palette: palette),
          trailing: _RailEngine(palette: palette),
          destinations: const <NavigationRailDestination>[
            NavigationRailDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: Text('Inicio'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music_rounded),
              label: Text('Biblioteca'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.queue_music_outlined),
              selectedIcon: Icon(Icons.queue_music_rounded),
              label: Text('Listas'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune_rounded),
              label: Text('Ajustes'),
            ),
          ],
        ),
      ),
    );
  }

  NavigationBarThemeData _navigationTheme(CyberHexPalette palette) {
    return NavigationBarThemeData(
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
    );
  }

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
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
      ];
}

/// Marca de la barra lateral: sello hexagonal y palabra.
class _RailBrand extends StatelessWidget {
  const _RailBrand({required this.palette});

  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 26),
        child: Row(
          children: <Widget>[
            ChHexBadge(
              icon: Icons.graphic_eq_rounded,
              palette: palette,
              size: 44,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontFamily: 'Righteous',
                        fontSize: 15,
                        letterSpacing: 1.0,
                        color: palette.foreground,
                      ),
                      children: <InlineSpan>[
                        const TextSpan(text: 'CYBER'),
                        TextSpan(
                          text: 'HEX',
                          style: TextStyle(color: palette.accent),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'AUDIO ENGINE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: chMono(palette, size: 7.5, letterSpacing: 0.9),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ficha técnica al pie de la barra lateral.
class _RailEngine extends StatelessWidget {
  const _RailEngine({required this.palette});

  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.surfaceHigh.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: palette.foreground.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
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
                          blurRadius: 7,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'MOTOR NATIVO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: chEyebrow(palette, size: 8, color: palette.accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '48 kHz · 24 bit',
                style: chMono(palette, size: 10, color: palette.foreground),
              ),
              const SizedBox(height: 2),
              Text(
                'FLAC · WAV · MP3 · OGG',
                style: chMono(palette, size: 8, color: palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
