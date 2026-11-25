import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../core/tag_editor.dart';
import '../theme.dart';
import 'kit/ch_kit.dart';

/// Editor de etiquetas y carátula de la pista actual (o de todo el álbum).
///
/// Escribe **en el archivo**, no en una base de datos: ID3v2.3 para `.mp3` y
/// Vorbis comment para `.flac`. El motor entrega lo que suena, así que el
/// cambio se nota al volver a abrir la pista (la hoja lo dice en vez de
/// prometer un refresco que el núcleo no tiene).
///
/// Lo que **no** hace: tocar `.m4a`/`.ogg`/`.wav` —`TagEditor.canWrite` lo
/// comprueba y la hoja lo explica— ni re-codificar la carátula (se incrustan los
/// bytes elegidos tal cual).
class TagEditorSheet extends StatefulWidget {
  const TagEditorSheet({super.key, required this.controller, this.path});

  final PlayerController controller;

  /// Ruta a editar. Si falta, se usa la pista que está sonando.
  final String? path;

  static Future<void> show(
    BuildContext context,
    PlayerController controller, {
    String? path,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: TagEditorSheet(controller: controller, path: path),
      ),
    );
  }

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _artist = TextEditingController();
  final TextEditingController _album = TextEditingController();
  final TextEditingController _year = TextEditingController();
  final TextEditingController _genre = TextEditingController();
  final TextEditingController _track = TextEditingController();

  TrackTags _original = TrackTags.empty;
  Uint8List? _cover;
  bool _dropCover = false;
  bool _albumScope = false;
  bool _busy = false;
  bool _loaded = false;
  String? _message;

  PlayerController get _controller => widget.controller;

  String get _path {
    final explicit = widget.path;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final snapshot = _controller.snapshot;
    final index = snapshot.queueIndex;
    if (index < 0 || index >= snapshot.queue.length) return '';
    return snapshot.queue[index].path;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _year.dispose();
    _genre.dispose();
    _track.dispose();
    super.dispose();
  }

  void _load() {
    final path = _path;
    if (path.isEmpty) {
      setState(() {
        _loaded = true;
        _message = 'Abre una pista antes de editar sus etiquetas.';
      });
      return;
    }
    final tags = TagEditor.read(File(path));
    _original = tags;
    _title.text = tags.title;
    _artist.text = tags.artist;
    _album.text = tags.album;
    _year.text = tags.year;
    _genre.text = tags.genre;
    _track.text = tags.track == 0 ? '' : '${tags.track}';
    setState(() {
      _cover = tags.cover;
      _dropCover = false;
      _loaded = true;
      _message = tags.isEmpty
          ? 'Este archivo no trae etiquetas todavía.'
          : null;
    });
  }

  TrackTags get _edited => TrackTags(
    title: _title.text.trim(),
    artist: _artist.text.trim(),
    album: _album.text.trim(),
    year: _year.text.trim(),
    genre: _genre.text.trim(),
    track: int.tryParse(_track.text.trim()) ?? 0,
    cover: _dropCover ? null : _cover,
  );

  Future<void> _pickCover() async {
    const group = XTypeGroup(
      label: 'Imagen',
      extensions: <String>['jpg', 'jpeg', 'png'],
    );
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null) return;
    try {
      final bytes = await File(file.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _cover = bytes;
        _dropCover = false;
        _message = 'Carátula lista (${(bytes.length / 1024).round()} KiB).';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'No se pudo leer la imagen: $error');
    }
  }

  Future<void> _save() async {
    final path = _path;
    if (path.isEmpty) {
      setState(() => _message = 'Abre una pista antes de guardar.');
      return;
    }
    final file = File(path);
    if (!TagEditor.canWrite(path)) {
      setState(
        () => _message =
            'Este formato no admite edición de etiquetas (solo .mp3 y .flac).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Guardando…';
    });
    final tags = _edited;
    final report = _albumScope
        ? await TagEditor.writeMany(TagEditor.albumSiblings(file), tags)
        : await TagEditor.write(file, tags);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = report.ok
          ? '${report.written} archivo(s) actualizados. '
                'Vuelve a abrir la pista para ver los datos nuevos.'
          : 'Falló ${report.failed.length} archivo(s): ${report.error ?? ''}';
      if (report.ok) _original = tags;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final path = _path;
    final name = path.isEmpty ? '' : path.split(RegExp(r'[/\\]')).last;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChSheetHeader(
                icon: Icons.sell_rounded,
                title: 'Etiquetas y carátula',
                palette: palette,
                subtitle: name.isEmpty ? null : name,
                trailing: IconButton(
                  tooltip: 'Recargar del archivo',
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(height: ChSpace.lg),
              if (!_loaded)
                const Center(child: CircularProgressIndicator())
              else ...[
                _CoverRow(
                  cover: _dropCover ? null : _cover,
                  busy: _busy,
                  onPick: _pickCover,
                  onDrop: () => setState(() {
                    _dropCover = true;
                    _cover = null;
                  }),
                ),
                const SizedBox(height: 14),
                _field(_title, 'Título', Icons.music_note_rounded),
                _field(_artist, 'Artista', Icons.person_rounded),
                _field(_album, 'Álbum', Icons.album_rounded),
                Row(
                  children: [
                    Expanded(child: _field(_year, 'Año', Icons.event_rounded)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(_genre, 'Género', Icons.category_rounded),
                    ),
                  ],
                ),
                _field(
                  _track,
                  'Número de pista',
                  Icons.format_list_numbered_rounded,
                  keyboard: TextInputType.number,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _albumScope,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _albumScope = value),
                  title: Text(
                    'Aplicar al álbum completo',
                    style: chTitle(palette, size: 13.5),
                  ),
                  subtitle: Text(
                    'Mismo artista, álbum y carátula a los archivos del directorio '
                    'con el mismo álbum; cada uno conserva su título y su número.',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          _albumScope ? 'Guardar en el álbum' : 'Guardar',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor: palette.onAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _busy || !_loaded ? null : _load,
                      child: const Text('Descartar'),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _message!,
                    style: TextStyle(fontSize: 12, color: palette.accent),
                  ),
                ],
                if (!_original.isEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'En el archivo: ${_original.summary}'
                    '${_original.hasCover ? ' · carátula incrustada' : ''}',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
  }) {
    final palette = paletteOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 12, color: palette.muted),
          prefixIcon: Icon(icon, size: 18, color: palette.muted),
          filled: true,
          fillColor: palette.surface,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: palette.border),
          ),
        ),
      ),
    );
  }
}

/// Miniatura de la carátula con los botones para cambiarla o quitarla.
class _CoverRow extends StatelessWidget {
  const _CoverRow({
    required this.cover,
    required this.busy,
    required this.onPick,
    required this.onDrop,
  });

  final Uint8List? cover;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final image = cover;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 84,
            height: 84,
            child: image == null
                ? ColoredBox(
                    color: palette.surfaceHigh,
                    child: Icon(Icons.image_outlined, color: palette.muted),
                  )
                : Image.memory(
                    image,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: 168,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: palette.surfaceHigh,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: palette.muted,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                image == null ? 'Sin carátula' : 'Carátula incrustada',
                style: chTitle(palette, size: 13.5),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: busy ? null : onPick,
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text(
                      'Elegir…',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (image != null)
                    TextButton(
                      onPressed: busy ? null : onDrop,
                      child: const Text(
                        'Quitar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Entrada rápida desde el reproductor: edita la pista que suena.
Future<void> openTagEditor(BuildContext context, PlayerController controller) =>
    TagEditorSheet.show(context, controller);

/// Texto de ayuda para la fila de la biblioteca (qué se puede editar).
String tagEditorHint(PlayerSnapshot snapshot) => snapshot.hasTrack
    ? 'Edita título, artista, álbum, año, género, pista y carátula'
    : 'Abre una pista para editar sus etiquetas';
