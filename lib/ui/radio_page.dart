import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../core/radio_store.dart';
import '../theme.dart';
import 'mini_player.dart';

/// Emisoras por Internet.
///
/// El núcleo abre **archivos**, no sockets: cada emisora se baja a un archivo
/// temporal con [RadioStore.buffer] (una ventana de audio) y se reproduce desde
/// ahí. La UI lo dice tal cual: «Flujo bajado: N MB».
class RadioPage extends StatefulWidget {
  const RadioPage({super.key, required this.store, required this.controller});

  final RadioStore store;
  final PlayerController controller;

  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
  String? _busyId;
  int _bytes = 0;
  String? _message;

  RadioStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _say(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  // ---------------------------------------------------------------------------
  // Reproducir
  // ---------------------------------------------------------------------------

  Future<void> _play(RadioStation station) async {
    if (_busyId != null) return;
    final uri = station.uri;
    if (uri == null) {
      _say('La URL de ${station.name} no es válida.');
      return;
    }
    setState(() {
      _busyId = station.id;
      _bytes = 0;
      _message = 'Conectando con ${station.host}…';
    });
    try {
      final buffer = await _store.buffer(
        uri,
        onProgress: (bytes) {
          if (!mounted) return;
          setState(() => _bytes = bytes);
        },
      );
      final error = await widget.controller.openFile(buffer.file.path);
      if (error != null) {
        _say('El motor no pudo abrir el flujo: $error');
        return;
      }
      widget.controller.play();
      _say(
        '${station.name}: ${buffer.label}'
        '${buffer.truncated ? ' · ventana de ${buffer.elapsed.inSeconds} s' : ''}',
      );
    } on RadioException catch (error) {
      _say(error.message);
    } catch (error) {
      _say('No se pudo reproducir ${station.name}: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busyId = null;
          _bytes = 0;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Alta, importación y exportación
  // ---------------------------------------------------------------------------

  Future<void> _add() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final genreController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva emisora'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL del flujo o de la lista',
                hintText: 'https://host/stream.mp3',
              ),
            ),
            TextField(
              controller: genreController,
              decoration: const InputDecoration(labelText: 'Género (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    final url = urlController.text.trim();
    if (accepted == true && url.isNotEmpty) {
      _store.add(
        name: nameController.text,
        url: url,
        genre: genreController.text,
      );
      _say('Añadida ${nameController.text.trim().isEmpty ? url : nameController.text.trim()}.');
    }
    nameController.dispose();
    urlController.dispose();
    genreController.dispose();
  }

  Future<void> _import() async {
    const group = XTypeGroup(
      label: 'Listas de radio',
      extensions: <String>['m3u', 'm3u8', 'pls'],
    );
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null || !mounted) return;
    try {
      final added = await _store.importPlaylist(File(file.path));
      _say(added.isEmpty
          ? 'La lista no traía emisoras nuevas.'
          : 'Importadas ${added.length} emisora(s).');
    } catch (error) {
      _say('No se pudo leer la lista: $error');
    }
  }

  Future<void> _export() async {
    if (_store.isEmpty) {
      _say('No hay emisoras propias que exportar.');
      return;
    }
    const group = XTypeGroup(label: 'M3U', extensions: <String>['m3u']);
    final location = await getSaveLocation(
      suggestedName: 'cyberhex-radios.m3u',
      acceptedTypeGroups: const <XTypeGroup>[group],
    );
    if (location == null || !mounted) return;
    try {
      await _store.exportM3u(File(location.path));
      _say('Exportadas ${_store.length} emisora(s) a ${location.path}.');
    } catch (error) {
      _say('No se pudo exportar: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final mine = _store.stations;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radios'),
        actions: [
          IconButton(
            tooltip: 'Importar .m3u/.m3u8/.pls',
            onPressed: _import,
            icon: const Icon(Icons.playlist_add_rounded),
          ),
          IconButton(
            tooltip: 'Exportar .m3u',
            onPressed: _export,
            icon: const Icon(Icons.save_alt_rounded),
          ),
          IconButton(
            tooltip: 'Nueva emisora',
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busyId != null)
            LinearProgressIndicator(
              value: _bytes == 0 ? null : (_bytes / RadioStore.maxBufferBytes).clamp(0.0, 1.0),
              minHeight: 3,
              color: palette.accent,
            ),
          Expanded(
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
                const _SectionLabel('Mis emisoras'),
                if (mine.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Text(
                      'Aún no hay emisoras. Añade una URL o importa una lista '
                      '.m3u/.pls.',
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                  ),
                for (final station in mine)
                  _StationTile(
                    station: station,
                    palette: palette,
                    busy: _busyId == station.id,
                    enabled: _busyId == null,
                    onPlay: () => _play(station),
                    onRename: () => _rename(station),
                    onDelete: () => _store.remove(station.id),
                  ),
                const _SectionLabel('Sugeridas'),
                for (final station in RadioStore.builtinStations)
                  _StationTile(
                    station: station,
                    palette: palette,
                    busy: _busyId == station.id,
                    enabled: _busyId == null,
                    onPlay: () => _play(station),
                    onAdd: () => _store.add(
                      name: station.name,
                      url: station.url,
                      genre: station.genre,
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'El motor reproduce archivos: cada emisora se baja a un archivo '
                  'temporal (ventana de ${RadioStore.defaultWindow.inSeconds} s o '
                  '${RadioStore.maxBufferBytes >> 20} MB) y suena desde ahí. Es '
                  'radio con búfer, no directo continuo.',
                  style: TextStyle(fontSize: 11, color: palette.muted, height: 1.5),
                ),
              ],
            ),
          ),
          MiniPlayer(
            controller: widget.controller,
            onOpen: () => Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(RadioStation station) async {
    final controller = TextEditingController(text: station.name);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renombrar emisora'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (accepted == true && controller.text.trim().isNotEmpty) {
      _store.rename(station.id, controller.text);
    }
    controller.dispose();
  }
}

class _StationTile extends StatelessWidget {
  const _StationTile({
    required this.station,
    required this.palette,
    required this.busy,
    required this.enabled,
    required this.onPlay,
    this.onRename,
    this.onDelete,
    this.onAdd,
  });

  final RadioStation station;
  final CyberHexPalette palette;
  final bool busy;
  final bool enabled;
  final VoidCallback onPlay;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (station.genre.isNotEmpty) station.genre,
      station.host,
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: Icon(
        station.isPlaylist ? Icons.queue_music_rounded : Icons.radio_rounded,
        color: palette.accent,
      ),
      title: Text(station.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: palette.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: 'Reproducir',
              onPressed: enabled ? onPlay : null,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          if (onAdd != null)
            IconButton(
              tooltip: 'Guardar en mis emisoras',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          if (onRename != null || onDelete != null)
            PopupMenuButton<String>(
              tooltip: 'Más',
              onSelected: (value) {
                if (value == 'rename') onRename?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (context) => [
                if (onRename != null)
                  const PopupMenuItem<String>(
                    value: 'rename',
                    child: Text('Renombrar'),
                  ),
                if (onDelete != null)
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Quitar'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w600,
          color: paletteOf(context).muted,
        ),
      ),
    );
  }
}
