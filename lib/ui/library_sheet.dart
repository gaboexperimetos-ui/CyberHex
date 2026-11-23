import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../theme.dart';

class LibrarySheet extends StatefulWidget {
  const LibrarySheet({
    super.key,
    required this.controller,
    this.fullPage = false,
  });

  final PlayerController controller;
  final bool fullPage;

  @override
  State<LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends State<LibrarySheet> {
  final TextEditingController _search = TextEditingController();
  List<String> _tracks = const [];
  bool _scanning = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final root = await getDirectoryPath(confirmButtonText: 'Escanear');
    if (root == null || !mounted) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    final result = await Future.sync(() => widget.controller.scanLibrary(root));
    if (!mounted) return;
    setState(() {
      _scanning = false;
      if (result == null) {
        _error = 'No se pudo escanear esta carpeta.';
      } else {
        _tracks = result.tracks;
      }
    });
  }

  List<String> get _filteredTracks {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _tracks;
    return _tracks.where((path) {
      final name = _fileName(path).toLowerCase();
      return name.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _filteredTracks;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
          child: Row(
            children: [
              Text('Biblioteca', style: chDisplay.copyWith(fontSize: 20)),
              const Spacer(),
              IconButton(
                onPressed: _scanning ? null : _scan,
                tooltip: 'Escanear carpeta',
                icon: _scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            controller: _search,
            enabled: _tracks.isNotEmpty,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Buscar en la biblioteca',
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(_error!, style: const TextStyle(color: chMuted)),
          ),
        if (_tracks.isEmpty && _error == null)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.library_music_outlined,
                      size: 42,
                      color: chMuted,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Escanea una carpeta para crear tu biblioteca local.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: chMuted, height: 1.5),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _scanning ? null : _scan,
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Elegir carpeta'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final path = tracks[index];
                return ListTile(
                  leading: const Icon(
                    Icons.music_note_rounded,
                    color: chAccent,
                  ),
                  title: Text(
                    _fileName(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: chMuted, fontSize: 11),
                  ),
                  onTap: () {
                    final ok = widget.controller.loadAndPlay(path);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No se pudo abrir la pista.'),
                        ),
                      );
                    } else if (context.mounted && !widget.fullPage) {
                      Navigator.of(context).pop();
                    }
                  },
                  trailing: IconButton(
                    tooltip: 'Agregar a la cola',
                    icon: const Icon(Icons.playlist_add_rounded),
                    onPressed: () {
                      final ok = widget.controller.enqueue(path);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Agregado a la cola'
                                : 'No se pudo agregar a la cola',
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
    return widget.fullPage
        ? content
        : SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: content,
          );
  }
}

String _fileName(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
