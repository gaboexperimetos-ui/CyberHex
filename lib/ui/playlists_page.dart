import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../core/playlist_store.dart';
import '../core/stats_store.dart';
import '../theme.dart';
import 'design/ch_ambient.dart';
import 'kit/ch_kit.dart';
import 'mini_player.dart';

/// Playlists: las del usuario y las tres inteligentes.
///
/// Las listas se guardan en `playlists.json` ([PlaylistStore]); las
/// inteligentes se recalculan cada vez que se abre la pantalla a partir de
/// [StatsStore] y de lo que la biblioteca haya recordado.
class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({
    super.key,
    required this.controller,
    this.store,
    this.stats,
    this.onOpenPlayer,
    this.showMiniPlayer = true,
  });

  final PlayerController controller;

  /// Inyectables para pruebas/vistas previas.
  final PlaylistStore? store;
  final StatsStore? stats;

  /// Abre el reproductor completo desde el mini-reproductor.
  final VoidCallback? onOpenPlayer;

  /// Si es `false`, el mini-reproductor lo dibuja el armazón contenedor.
  final bool showMiniPlayer;

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  late final PlaylistStore _store = widget.store ?? PlaylistStore();
  late final StatsStore _stats = widget.stats ?? StatsStore();

  String? _message;

  PlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    _stats.addListener(_onChanged);
    if (widget.store == null) _store.load();
    if (widget.stats == null) _stats.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    _stats.removeListener(_onChanged);
    if (widget.store == null) _store.dispose();
    if (widget.stats == null) _stats.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<Playlist> get _smart => _store.smartLists(
    library: <String>[
      for (final track in _controller.libraryTracks) track.path,
    ],
    plays: _stats.playsOf,
  );

  Future<void> _create() async {
    final name = await _prompt('Nueva lista', 'Nombre de la lista');
    if (name == null) return;
    final playlist = _store.create(name);
    setState(() => _message = 'Creada «${playlist.name}»');
  }

  Future<String?> _prompt(String title, String hint, {String? initial}) {
    final text = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paletteOf(context).surface,
        title: Text(title),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(text.text),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    const group = XTypeGroup(
      label: 'Listas',
      extensions: <String>['m3u', 'm3u8', 'pls'],
    );
    try {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[group],
      );
      if (file == null) return;
      final playlist = await _store.importFile(File(file.path));
      if (!mounted) return;
      setState(
        () => _message = playlist == null
            ? 'No se pudo leer «${file.name}».'
            : 'Importadas ${playlist.length} pistas en «${playlist.name}».',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'No se pudo importar: $error');
    }
  }

  Future<void> _export(Playlist playlist) async {
    if (playlist.isEmpty) {
      setState(() => _message = 'Esa lista está vacía.');
      return;
    }
    const group = XTypeGroup(label: 'M3U', extensions: <String>['m3u8']);
    try {
      final location = await getSaveLocation(
        suggestedName: '${_slug(playlist.name)}.m3u8',
        acceptedTypeGroups: const <XTypeGroup>[group],
      );
      if (location == null) return;
      final written = await _store.exportPlaylist(
        playlist,
        File(location.path),
      );
      if (!mounted) return;
      setState(
        () => _message = written == null
            ? 'No se pudo escribir el archivo.'
            : 'Exportada a ${written.path}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'No se pudo exportar: $error');
    }
  }

  Future<void> _playAll(Playlist playlist) async {
    if (playlist.isEmpty) return;
    final paths = playlist.paths;
    _controller.queueProtected = true;
    _controller.clearQueue();
    for (final path in paths) {
      _controller.enqueue(path);
    }
    await _controller.openFile(paths.first);
    if (!mounted) return;
    setState(
      () => _message = 'Sonando «${playlist.name}» (${paths.length} pistas).',
    );
  }

  void _open(Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailPage(
          controller: _controller,
          store: _store,
          playlistId: playlist.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChPageScaffold(
      eyebrow: 'CyberHex · colecciones',
      title: 'Listas',
      subtitle: 'Inteligentes y tuyas · en este equipo',
      actions: <Widget>[
        IconButton(
          tooltip: 'Importar .m3u / .m3u8 / .pls',
          onPressed: _import,
          icon: const Icon(Icons.file_open_rounded),
        ),
        IconButton(
          tooltip: 'Nueva lista',
          onPressed: _create,
          icon: const Icon(Icons.playlist_add_rounded),
        ),
      ],
      body: Column(
        children: [
          Expanded(child: _list()),
          if (widget.showMiniPlayer)
            MiniPlayer(
              controller: _controller,
              onOpen:
                  widget.onOpenPlayer ??
                  () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
            ),
        ],
      ),
    );
  }

  Widget _list() {
    final palette = paletteOf(context);
    final smart = _smart;
    final mine = _store.playlists;
    return ChContent(
      maxWidth: 920,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(
                _message!,
                style: TextStyle(fontSize: 12, color: palette.accent),
              ),
            ),
          const _SectionLabel('Inteligentes'),
          for (final playlist in smart) ...[
            _PlaylistTile(
              playlist: playlist,
              onTap: playlist.isEmpty ? null : () => _open(playlist),
              onPlay: playlist.isEmpty ? null : () => _playAll(playlist),
              onExport: null,
              onRename: null,
              onDuplicate: null,
              onDelete: null,
            ),
            if (playlist.id == SmartList.top25.id && playlist.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Aún no hay reproducciones: escucha algo y vuelve.',
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ),
          ],
          const SizedBox(height: 8),
          const _SectionLabel('Tus listas'),
          if (mine.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
              child: ChSurface(
                radius: ChRadius.md,
                child: Row(
                  children: <Widget>[
                    ChHexBadge(
                      icon: Icons.queue_music_rounded,
                      palette: palette,
                      size: 40,
                    ),
                    const SizedBox(width: ChSpace.md),
                    Expanded(
                      child: Text(
                        'Crea una lista con el botón + o importa un .m3u de '
                        'otro reproductor.',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final playlist in mine)
            _PlaylistTile(
              playlist: playlist,
              onTap: () => _open(playlist),
              onPlay: () => _playAll(playlist),
              onExport: () => _export(playlist),
              onRename: () async {
                final name = await _prompt(
                  'Renombrar',
                  'Nuevo nombre',
                  initial: playlist.name,
                );
                if (name != null) _store.rename(playlist.id, name);
              },
              onDuplicate: () {
                final copy = _store.duplicate(playlist.id);
                setState(
                  () => _message = copy == null
                      ? null
                      : 'Duplicada «${copy.name}»',
                );
              },
              onDelete: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: paletteOf(context).surface,
                    title: const Text('¿Borrar la lista?'),
                    content: Text(
                      '«${playlist.name}» se quitará. Los archivos no.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Borrar'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) _store.delete(playlist.id);
              },
            ),
        ],
      ),
    );
  }

  static String _slug(String name) => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
      child: ChSectionHeader(text, palette: paletteOf(context)),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlist,
    required this.onTap,
    required this.onPlay,
    required this.onExport,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Playlist playlist;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onExport;
  final VoidCallback? onRename;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final editable = onRename != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Material(
        color: palette.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChRadius.md),
          side: BorderSide(color: palette.border.withValues(alpha: 0.42)),
        ),
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChRadius.md),
          ),
          leading: playlist.smart
              ? ChHexBadge(
                  icon: Icons.auto_awesome_rounded,
                  palette: palette,
                  size: 44,
                  color: palette.secondary,
                )
              : ChCoverThumb(
                  seed: playlist.name,
                  palette: palette,
                  size: 44,
                  hex: true,
                ),
          title: Text(
            playlist.name,
            style: chTitle(palette, size: 14.5, letterSpacing: -0.1),
          ),
          subtitle: Text(
            playlist.summary,
            style: TextStyle(fontSize: 11, color: palette.muted),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Reproducir',
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              if (editable)
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: (value) {
                    switch (value) {
                      case 'export':
                        onExport?.call();
                      case 'rename':
                        onRename?.call();
                      case 'duplicate':
                        onDuplicate?.call();
                      case 'delete':
                        onDelete?.call();
                    }
                  },
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: 'export',
                      child: Text('Exportar .m3u8'),
                    ),
                    PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                    PopupMenuItem(value: 'duplicate', child: Text('Duplicar')),
                    PopupMenuItem(value: 'delete', child: Text('Borrar')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detalle de una lista: pistas, quitar, reordenar y reproducir.
class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.controller,
    required this.store,
    required this.playlistId,
  });

  final PlayerController controller;
  final PlaylistStore store;
  final String playlistId;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Playlist? get _playlist => widget.store.byId(widget.playlistId);

  Future<void> _play(Playlist playlist, int index) async {
    widget.controller.queueProtected = true;
    widget.controller.clearQueue();
    for (final path in playlist.paths) {
      widget.controller.enqueue(path);
    }
    await widget.controller.openFile(playlist.paths[index]);
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final playlist = _playlist;
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lista')),
        body: const Center(child: Text('La lista ya no existe.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            tooltip: 'Reproducir todo',
            onPressed: playlist.isEmpty ? null : () => _play(playlist, 0),
            icon: const Icon(Icons.play_circle_fill_rounded),
          ),
        ],
      ),
      body: playlist.isEmpty
          ? ChEmptyState(
              icon: Icons.queue_music_rounded,
              title: 'Lista vacía',
              message:
                  'Añade pistas desde la biblioteca (menú de cada pista → '
                  '«Añadir a lista»).',
              palette: palette,
            )
          : ListView.separated(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              itemCount: playlist.paths.length,
              separatorBuilder: (_, _) =>
                  ChHairline(palette: palette, indent: 66, opacity: 0.28),
              itemBuilder: (context, index) {
                final path = playlist.paths[index];
                final name = path.split(RegExp(r'[/\\]')).last;
                return ListTile(
                  leading: ChCoverThumb(
                    seed: name,
                    palette: palette,
                    size: 40,
                    hex: true,
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: chTitle(palette, size: 13.5),
                  ),
                  subtitle: Text(
                    '${index + 1} · $path',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: chMono(palette, size: 10),
                  ),
                  onTap: () => _play(playlist, index),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Subir',
                        onPressed: index == 0
                            ? null
                            : () => widget.store.move(
                                playlist.id,
                                index,
                                index - 1,
                              ),
                        icon: const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 18,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar de la lista',
                        onPressed: () =>
                            widget.store.removeAt(playlist.id, index),
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
