import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../core/favorites_store.dart';
import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../core/playlist_store.dart';
import '../core/radio_store.dart';
import '../core/stats_store.dart';
import '../core/text_search.dart';
import '../theme.dart';
import 'audio_export_sheet.dart';
import 'design/ch_ambient.dart';
import 'downloader_page.dart';
import 'kit/ch_kit.dart';
import 'network_page.dart';
import 'radio_page.dart';
import 'mini_player.dart';
import 'playlists_page.dart';
import 'stats_page.dart';

/// Cómo se ordena la lista.
enum LibrarySort { title, artist, album, duration }

/// Pestañas de la biblioteca.
enum LibraryTab { songs, albums, artists, folders, favorites }

/// Acciones del menú contextual de una pista.
enum _TrackAction { playNow, playNext, enqueue, favorite, details }

/// Pantalla de biblioteca: escanea una carpeta con el núcleo y la presenta por
/// canciones, álbumes, artistas, carpetas y favoritos.
///
/// El núcleo solo entrega rutas (ver `docs/INFORME.md`), así que artista y
/// álbum se deducen de la jerarquía de carpetas:
/// `<raíz>/Artista/Álbum/pista.flac` → artista y álbum; si el archivo está
/// suelto en la raíz, ambos quedan sin clasificar.
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.controller,
    this.favorites,
    this.initialRoot,
    this.playlists,
    this.stats,
    this.longTracks,
    this.onOpenPlayer,
    this.showMiniPlayer = true,
    this.focusAlbum,
    this.focusRequest = 0,
  });

  final PlayerController controller;

  /// Almacenes compartidos con el resto de la app (listas, estadísticas y la
  /// memoria de posición en pistas largas). Si faltan, la página crea los suyos.
  final PlaylistStore? playlists;
  final StatsStore? stats;
  final LongTrackMemory? longTracks;

  /// Se inyecta en las pruebas; en producción la página crea la suya.
  final FavoritesStore? favorites;

  /// Carpeta a escanear nada más abrir. Solo lo usan las pruebas.
  final String? initialRoot;

  /// Abre el reproductor completo desde el mini-reproductor. Si falta (página
  /// usada suelta), se vuelve a la raíz de la pila.
  final VoidCallback? onOpenPlayer;

  /// Si es `false`, el mini-reproductor lo dibuja el armazón que contiene la
  /// página (así no se duplica cuando la biblioteca es una pestaña).
  final bool showMiniPlayer;

  /// Álbum por el que saltar al abrirse (lo pide la sección Álbumes de Inicio).
  final String? focusAlbum;

  /// Cambia cuando el armazón quiere forzar el salto; así tocar dos álbumes
  /// distintos seguidos vuelve a aplicar el foco.
  final int focusRequest;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: LibraryTab.values.length,
    vsync: this,
  )..addListener(_onTabChanged);

  late final FavoritesStore _favorites = widget.favorites ?? FavoritesStore();

  late final LongTrackMemory _longTracks =
      widget.longTracks ?? LongTrackMemory();

  final Map<String, double> _durations = <String, double>{};
  final TextEditingController _search = TextEditingController();

  String? _root;
  List<_Entry> _entries = const <_Entry>[];
  String _query = '';
  LibrarySort _sort = LibrarySort.title;
  bool _hideShort = false;
  bool _scanning = false;
  String? _error;
  int _scanId = 0;

  PlayerController get _controller => widget.controller;

  LibraryTab get _tab => LibraryTab.values[_tabs.index];

  @override
  void initState() {
    super.initState();
    if (widget.longTracks == null) _longTracks.load();
    _favorites.addListener(_onFavoritesChanged);
    if (widget.favorites == null) {
      // Sin await: la lista se pinta sin favoritos y se repinta al llegar.
      unawaited(_favorites.load());
    }
    _controller.addListener(_onPlayerChanged);
    final root = widget.initialRoot;
    if (root != null) unawaited(_scan(root));
    if (widget.focusRequest > 0) _applyFocus();
  }

  @override
  void didUpdateWidget(LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusRequest != oldWidget.focusRequest) _applyFocus();
  }

  /// Salta a la pestaña Álbumes con la búsqueda puesta en ese álbum.
  void _applyFocus() {
    final album = widget.focusAlbum;
    if (album == null || album.isEmpty) return;
    _tabs.index = LibraryTab.albums.index;
    _search.text = album;
    setState(() => _query = _normalize(album));
  }

  @override
  void dispose() {
    _controller.removeListener(_onPlayerChanged);
    _favorites.removeListener(_onFavoritesChanged);
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _onFavoritesChanged() {
    if (mounted) setState(() {});
  }

  /// Aprovecha cada cambio del motor para apuntar la duración de la pista que
  /// suena: el núcleo no tiene consulta de duración por ruta, así que la lista
  /// solo conoce las de lo ya reproducido.
  void _onPlayerChanged() {
    if (!mounted) return;
    final snapshot = _controller.snapshot;
    final index = snapshot.queueIndex;
    if (index < 0 || index >= snapshot.queue.length) return;
    final track = snapshot.queue[index];
    if (!track.isPlayable || snapshot.duration <= 0) return;
    _longTracks.remember(
      track.path,
      _controller.position.value,
      snapshot.duration,
    );
    if (_durations[track.path] == snapshot.duration) return;
    setState(() => _durations[track.path] = snapshot.duration);
  }

  Future<void> _openPlaylists() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistsPage(
          controller: _controller,
          store: widget.playlists,
          stats: widget.stats,
        ),
      ),
    );
  }

  Future<void> _openStats() async {
    final stats = widget.stats ?? StatsStore.memory();
    await stats.load();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => StatsPage(stats: stats)));
  }

  /// Radios por Internet. El almacén se lee de disco al abrir la página, así
  /// que no hace falta compartir instancia con el resto de la app.
  void _openRadio() {
    final store = RadioStore();
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => RadioPage(
              store: store,
              controller: _controller,
              onOpenPlayer: widget.onOpenPlayer,
            ),
          ),
        )
        .whenComplete(store.dispose);
  }

  /// Explorador WebDAV / enlaces de nube.
  void _openNetwork() {
    final store = NetworkStore();
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => NetworkPage(
              store: store,
              controller: _controller,
              onOpenPlayer: widget.onOpenPlayer,
            ),
          ),
        )
        .whenComplete(store.dispose);
  }

  /// Exportador de la pista actual (rango + DSP → WAV/tono).
  void _openExport() {
    unawaited(AudioExportSheet.show(context, _controller));
  }

  Future<void> _openDownloads() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DownloaderPage(controller: _controller),
      ),
    );
  }

  Future<void> _scan(String root) async {
    // Un identificador por escaneo: si el usuario elige otra carpeta mientras
    // la primera sigue recorriéndose, solo la última manda.
    final id = ++_scanId;
    setState(() {
      _scanning = true;
      _error = null;
    });
    List<LibraryTrack> tracks;
    try {
      tracks = await _controller.scanDirectory(root);
    } catch (error) {
      if (!mounted || id != _scanId) return;
      setState(() {
        _scanning = false;
        _error = 'No se pudo escanear la carpeta: $error';
      });
      return;
    }
    if (!mounted || id != _scanId) return;
    setState(() {
      _root = root;
      _entries = [for (final track in tracks) _Entry.of(track, root)];
      _scanning = false;
    });
    // «Añadidas este mes» sale de aquí: la biblioteca apunta lo que ha visto.
    widget.playlists?.remember(<String>[
      for (final track in tracks) track.path,
    ]);
  }

  Future<void> _pickFolder() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: 'Escanear');
      if (path == null || !mounted) return;
      await _scan(path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo abrir el selector: $error');
    }
  }

  // -----------------------------------------------------------------------
  // Acciones sobre una pista
  // -----------------------------------------------------------------------

  void _playNow(_Entry entry) {
    unawaited(_openAndReport(entry));
  }

  Future<void> _openAndReport(_Entry entry) async {
    final error = await _controller.openFile(entry.track.path);
    if (!mounted) return;
    if (error != null) {
      _say('No se pudo reproducir: $error');
      return;
    }
    // Audiolibros y directos se retoman donde iban (solo pistas > 15 min).
    final remembered = _longTracks.positionFor(entry.track.path);
    if (remembered != null && remembered > 30) {
      _controller.seek(remembered);
      _say('Retomando «${entry.track.title}» en ${_clock(remembered)}');
    }
  }

  static String _clock(double seconds) {
    final total = seconds.floor();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  void _playNext(_Entry entry) {
    final ok = _controller.playNext(entry.track.path);
    _say(
      ok
          ? '«${entry.track.title}» suena después'
          : 'El motor no aceptó la pista',
    );
  }

  void _enqueue(_Entry entry) {
    final ok = _controller.enqueue(entry.track.path);
    _say(
      ok
          ? '«${entry.track.title}» añadida a la cola'
          : 'El motor no aceptó la pista',
    );
  }

  Future<void> _toggleFavorite(_Entry entry) async {
    final nowFavorite = await _favorites.toggle(entry.track.path);
    if (!mounted) return;
    _say(nowFavorite ? 'Añadida a favoritos' : 'Quitada de favoritos');
  }

  void _say(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showDetails(_Entry entry) {
    final path = entry.track.path;
    String size = '—';
    try {
      final file = File(path);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        size = bytes >= 1024 * 1024
            ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
            : '${(bytes / 1024).toStringAsFixed(0)} KB';
      }
    } catch (_) {
      // Sin permisos para mirar el tamaño; el resto de la ficha vale igual.
    }
    final duration = _durations[path];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paletteOf(context).surface,
        title: Text(entry.track.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow('Formato', entry.track.extension.toUpperCase()),
              _DetailRow(
                'Duración',
                duration == null ? 'desconocida' : _mmss(duration),
              ),
              _DetailRow('Tamaño', size),
              _DetailRow(
                'Artista',
                entry.artist.isEmpty ? 'sin clasificar' : entry.artist,
              ),
              _DetailRow(
                'Álbum',
                entry.album.isEmpty ? 'sin clasificar' : entry.album,
              ),
              _DetailRow('Carpeta', entry.folder),
              const SizedBox(height: 10),
              Text(
                'Ruta',
                style: TextStyle(fontSize: 12, color: paletteOf(context).muted),
              ),
              const SizedBox(height: 2),
              SelectableText(path, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _handle(_TrackAction action, _Entry entry) {
    switch (action) {
      case _TrackAction.playNow:
        _playNow(entry);
      case _TrackAction.playNext:
        _playNext(entry);
      case _TrackAction.enqueue:
        _enqueue(entry);
      case _TrackAction.favorite:
        unawaited(_toggleFavorite(entry));
      case _TrackAction.details:
        _showDetails(entry);
    }
  }

  // -----------------------------------------------------------------------
  // Filtro, orden y agrupación
  // -----------------------------------------------------------------------

  double _durationOf(_Entry entry) => _durations[entry.track.path] ?? 0;

  List<_Entry> get _visible {
    final query = _normalize(_query);
    final favoritesOnly = _tab == LibraryTab.favorites;
    final list = <_Entry>[];
    for (final entry in _entries) {
      if (favoritesOnly && !_favorites.contains(entry.track.path)) continue;
      if (_hideShort) {
        final duration = _durationOf(entry);
        // Solo se ocultan las que se sabe que son cortas: una duración
        // desconocida (0) no puede descartar una canción.
        if (duration > 0 && duration < 30) continue;
      }
      if (query.isNotEmpty) {
        final haystack = _normalize(
          '${entry.track.title} ${entry.artist} ${entry.album} ${entry.folder}',
        );
        if (!haystack.contains(query)) continue;
      }
      list.add(entry);
    }
    list.sort(_compare);
    return list;
  }

  int _compare(_Entry a, _Entry b) {
    final byTitle = _cmp(a.track.title, b.track.title);
    switch (_sort) {
      case LibrarySort.title:
        return byTitle;
      case LibrarySort.artist:
        final byArtist = _cmp(a.artist, b.artist);
        return byArtist != 0 ? byArtist : byTitle;
      case LibrarySort.album:
        final byAlbum = _cmp(a.album, b.album);
        return byAlbum != 0 ? byAlbum : byTitle;
      case LibrarySort.duration:
        final da = _durationOf(a);
        final db = _durationOf(b);
        if (da == 0 && db == 0) return byTitle;
        // Las desconocidas, al final: mejor eso que un orden inventado.
        if (da == 0) return 1;
        if (db == 0) return -1;
        final byDuration = da.compareTo(db);
        return byDuration != 0 ? byDuration : byTitle;
    }
  }

  Map<String, List<_Entry>> _group(
    String Function(_Entry) keyOf, {
    required String fallback,
  }) {
    final groups = <String, List<_Entry>>{};
    for (final entry in _visible) {
      final raw = keyOf(entry).trim();
      final key = raw.isEmpty ? fallback : raw;
      groups.putIfAbsent(key, () => <_Entry>[]).add(entry);
    }
    return groups;
  }

  static int _cmp(String a, String b) => _normalize(a).compareTo(_normalize(b));

  /// Búsqueda insensible a mayúsculas y a tildes.
  static String _normalize(String value) => normalizeForSearch(value);

  // -----------------------------------------------------------------------
  // Pintado
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pad = wide ? 28.0 : 16.0;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ChAmbient(
        palette: palette,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 14, pad, 10),
                child: _header(palette),
              ),
              if (_root != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad - 8),
                  child: TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: palette.foreground.withValues(alpha: 0.06),
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: const [
                      Tab(text: 'Canciones'),
                      Tab(text: 'Álbumes'),
                      Tab(text: 'Artistas'),
                      Tab(text: 'Carpetas'),
                      Tab(text: 'Favoritos'),
                    ],
                  ),
                ),
              Expanded(child: ChContent(maxWidth: 1080, child: _body())),
              if (widget.showMiniPlayer)
                MiniPlayer(
                  controller: _controller,
                  onOpen:
                      widget.onOpenPlayer ??
                      () =>
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cabecera editorial: ceja, titular y acciones de orden y menú.
  Widget _header(CyberHexPalette palette) {
    final root = _root;
    final count = _entries.length;
    final subtitle = root == null
        ? 'Sin carpeta elegida · elige dónde vive tu música'
        : '$count ${count == 1 ? 'pista' : 'pistas'} · $_rootLabel';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: ChEditorialHeader(
            eyebrow: 'CyberHex · biblioteca local',
            title: 'Biblioteca',
            palette: palette,
            titleSize: 30,
            subtitle: subtitle,
          ),
        ),
        const SizedBox(width: ChSpace.md),
        _RoundMenu<LibrarySort>(
          palette: palette,
          icon: Icons.sort_rounded,
          tooltip: 'Ordenar',
          initialValue: _sort,
          onSelected: (value) => setState(() => _sort = value),
          itemBuilder: (context) => const [
            PopupMenuItem(value: LibrarySort.title, child: Text('Título')),
            PopupMenuItem(value: LibrarySort.artist, child: Text('Artista')),
            PopupMenuItem(value: LibrarySort.album, child: Text('Álbum')),
            PopupMenuItem(value: LibrarySort.duration, child: Text('Duración')),
          ],
        ),
        const SizedBox(width: ChSpace.sm),
        _RoundMenu<String>(
          palette: palette,
          icon: Icons.more_horiz_rounded,
          tooltip: 'Más',
          onSelected: (value) {
            switch (value) {
              case 'folder':
                _pickFolder();
              case 'playlists':
                _openPlaylists();
              case 'stats':
                _openStats();
              case 'downloads':
                _openDownloads();
              case 'radio':
                _openRadio();
              case 'network':
                _openNetwork();
              case 'export':
                _openExport();
            }
          },
          itemBuilder: (context) => const <PopupMenuEntry<String>>[
            PopupMenuItem(value: 'folder', child: Text('Elegir carpeta')),
            PopupMenuItem(value: 'playlists', child: Text('Listas y colas')),
            PopupMenuItem(value: 'stats', child: Text('Estadísticas')),
            PopupMenuItem(value: 'downloads', child: Text('Descargas')),
            PopupMenuItem(value: 'radio', child: Text('Radios por Internet')),
            PopupMenuItem(value: 'network', child: Text('Red y nube')),
            PopupMenuItem(
              value: 'export',
              child: Text('Exportar la pista actual'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _body() {
    if (_scanning) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_root == null) return _welcome();
    final palette = paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Buscar en la biblioteca',
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Limpiar',
                                icon: const Icon(Icons.close_rounded, size: 17),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: ChSpace.sm),
                  Tooltip(
                    message: 'Ocultar pistas de menos de 30 s',
                    child: FilterChip(
                      avatar: const Icon(Icons.timer_outlined, size: 16),
                      label: Text(compact ? '> 30 s' : 'Ocultar < 30 s'),
                      selected: _hideShort,
                      onSelected: (value) => setState(() => _hideShort = value),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Text(
                '${_visible.length} de ${_entries.length}',
                style: chMono(palette, size: 10),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  _rootLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: chMono(palette, size: 9.5),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _list()),
      ],
    );
  }

  String get _rootLabel {
    final root = _root;
    if (root == null) return '';
    final trimmed = root.length > 40
        ? '…${root.substring(root.length - 39)}'
        : root;
    return trimmed;
  }

  Widget _list() {
    final visible = _visible;
    if (visible.isEmpty) {
      final palette = paletteOf(context);
      return ChEmptyState(
        icon: _entries.isEmpty
            ? Icons.library_music_rounded
            : Icons.filter_alt_off_rounded,
        palette: palette,
        title: _entries.isEmpty ? 'Sin audio aquí' : 'Sin resultados',
        message: _entries.isEmpty
            ? 'No hay archivos compatibles en esta carpeta.'
            : 'Nada que mostrar con estos filtros',
      );
    }
    switch (_tab) {
      case LibraryTab.songs:
      case LibraryTab.favorites:
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: visible.length,
          separatorBuilder: (_, _) => Padding(
            padding: const EdgeInsets.only(left: 68),
            child: ChHairline(palette: paletteOf(context), opacity: 0.28),
          ),
          itemBuilder: (context, index) => _trackTile(visible[index]),
        );
      case LibraryTab.albums:
        return _groups(_group((e) => e.album, fallback: 'Sin álbum'));
      case LibraryTab.artists:
        return _groups(_group((e) => e.artist, fallback: 'Sin clasificar'));
      case LibraryTab.folders:
        return _groups(_group((e) => e.folder, fallback: 'Raíz'));
    }
  }

  Widget _groups(Map<String, List<_Entry>> groups) {
    final palette = paletteOf(context);
    final keys = groups.keys.toList()..sort(_cmp);
    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, index) {
        final key = keys[index];
        final items = groups[key]!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ChRadius.md),
            child: Material(
              color: palette.surface.withValues(alpha: 0.62),
              child: ExpansionTile(
                key: PageStorageKey<String>('group-$key'),
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                childrenPadding: const EdgeInsets.only(bottom: 4),
                leading: ChCoverThumb(
                  seed: key,
                  palette: palette,
                  size: 46,
                  radius: ChRadius.sm,
                  hex: true,
                ),
                title: Text(
                  key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: chTitle(palette, size: 14.5),
                ),
                subtitle: Text(
                  items.length == 1 ? '1 pista' : '${items.length} pistas',
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
                iconColor: palette.accent,
                collapsedIconColor: palette.muted,
                children: <Widget>[
                  for (final entry in items) _trackTile(entry, inner: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _trackTile(_Entry entry, {bool inner = false}) {
    final palette = paletteOf(context);
    final favorite = _favorites.contains(entry.track.path);
    final duration = _durationOf(entry);
    final subtitle = <String>[
      if (entry.artist.isNotEmpty) entry.artist,
      if (entry.album.isNotEmpty) entry.album,
      entry.track.extension.toUpperCase(),
    ].join(' · ');
    return ListTile(
      dense: inner,
      contentPadding: EdgeInsets.only(left: inner ? 44 : 14, right: 2),
      onTap: () => _playNow(entry),
      leading: SizedBox(
        width: 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ChCoverThumb(
              seed: entry.track.title,
              palette: palette,
              size: 42,
              radius: ChRadius.sm,
              hex: true,
            ),
            if (favorite)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: palette.border.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 9,
                    color: palette.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
      title: Text(
        entry.track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: chTitle(palette, size: 14.5),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: palette.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            duration > 0 ? _mmss(duration) : '—',
            style: chMono(palette, size: 10),
          ),
          PopupMenuButton<_TrackAction>(
            tooltip: 'Opciones',
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (action) => _handle(action, entry),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _TrackAction.playNow,
                child: Text('Reproducir ahora'),
              ),
              const PopupMenuItem(
                value: _TrackAction.playNext,
                child: Text('Reproducir siguiente'),
              ),
              const PopupMenuItem(
                value: _TrackAction.enqueue,
                child: Text('Añadir a la cola'),
              ),
              PopupMenuItem(
                value: _TrackAction.favorite,
                child: Text(
                  favorite ? 'Quitar de favoritos' : 'Marcar favorito',
                ),
              ),
              const PopupMenuItem(
                value: _TrackAction.details,
                child: Text('Ficha técnica'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _welcome() {
    final palette = paletteOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ChGlass(
            radius: ChRadius.xl,
            padding: const EdgeInsets.all(ChSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ChHexBadge(
                      icon: Icons.library_music_rounded,
                      palette: palette,
                      size: 64,
                    ),
                    const SizedBox(width: ChSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'PRIMER PASO',
                            style: chEyebrow(
                              palette,
                              size: 9,
                              color: palette.accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tu biblioteca',
                            style: chTitle(palette, size: 24),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ChSpace.md),
                Text(
                  'Elige una carpeta y CyberHex la recorrerá en tu equipo, sin '
                  'subir nada a ningún sitio. Los metadatos se leen del archivo '
                  'y las carátulas se guardan en caché local.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
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
                const SizedBox(height: ChSpace.lg),
                Wrap(
                  spacing: ChSpace.sm,
                  runSpacing: ChSpace.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _pickFolder,
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('Elegir carpeta'),
                    ),
                    Text(
                      'Nada sale de este equipo.',
                      style: chMono(palette, size: 9.5),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: ChSpace.md),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 11.5, color: palette.error),
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

/// Menú circular de cristal para las acciones de la cabecera.
class _RoundMenu<T> extends StatelessWidget {
  const _RoundMenu({
    required this.palette,
    required this.icon,
    required this.tooltip,
    required this.onSelected,
    required this.itemBuilder,
    this.initialValue,
  });

  final CyberHexPalette palette;
  final IconData icon;
  final String tooltip;
  final ValueChanged<T> onSelected;
  final PopupMenuItemBuilder<T> itemBuilder;
  final T? initialValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.surfaceHigh.withValues(alpha: 0.5),
        border: Border.all(color: palette.foreground.withValues(alpha: 0.09)),
      ),
      child: PopupMenuButton<T>(
        tooltip: tooltip,
        icon: Icon(icon, size: 20, color: palette.foreground),
        initialValue: initialValue,
        onSelected: onSelected,
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Insignia de formato del estado vacío.
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

/// Una pista de la biblioteca con lo que se deduce de su ruta.
class _Entry {
  const _Entry({
    required this.track,
    required this.artist,
    required this.album,
    required this.folder,
  });

  final LibraryTrack track;
  final String artist;
  final String album;

  /// Carpeta relativa a la raíz escaneada ('.' si la pista está en la raíz).
  final String folder;

  /// `<raíz>/Artista/Álbum/pista.flac` → álbum es la carpeta de la pista y
  /// artista la de encima. Es una heurística declarada: el núcleo todavía no
  /// da etiquetas para la biblioteca.
  factory _Entry.of(LibraryTrack track, String root) {
    var relative = track.directory;
    if (root.isNotEmpty && relative.startsWith(root)) {
      relative = relative.substring(root.length);
    }
    relative = relative.replaceAll('\\', '/');
    final levels = [
      for (final part in relative.split('/'))
        if (part.isNotEmpty) part,
    ];
    return _Entry(
      track: track,
      artist: levels.length >= 2 ? levels[levels.length - 2] : '',
      album: levels.isNotEmpty ? levels.last : '',
      folder: levels.isEmpty ? '.' : levels.join('/'),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: paletteOf(context).muted),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

/// `205.4` → `3:25`. Horas si hace falta, para audios largos.
String _mmss(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final secs = total % 60;
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = secs.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}
