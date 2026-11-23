import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/audio_downloader.dart';
import '../core/player_controller.dart';
import '../theme.dart';

/// Gestor de descargas: catálogo abierto (Internet Archive) o URL directa.
///
/// Dos caminos, la misma barra de progreso:
///
/// * **Buscar** en `archive.org` (API pública, sin clave): resultados → archivos
///   de audio del ítem → descargar.
/// * **Pegar** una URL directa a un MP3/FLAC/OGG (podcast, radio grabada, lo
///   que sea).
///
/// Lo descargado se guarda en la carpeta de música de la app y se puede añadir a
/// la cola en un toque; para que aparezca en la **biblioteca** hay que reescanear
/// la carpeta (el núcleo indexa, no se le puede «inyectar» una ruta).
class DownloaderPage extends StatefulWidget {
  const DownloaderPage({
    super.key,
    required this.controller,
    this.downloader,
  });

  final PlayerController controller;

  /// Inyectable: las pruebas usan un cliente HTTP contra un servidor local.
  final AudioDownloader? downloader;

  @override
  State<DownloaderPage> createState() => _DownloaderPageState();
}

class _DownloaderPageState extends State<DownloaderPage> {
  late final AudioDownloader _downloader = widget.downloader ?? AudioDownloader();
  final TextEditingController _query = TextEditingController();
  final TextEditingController _url = TextEditingController();

  List<ArchiveItem> _results = const <ArchiveItem>[];
  ArchiveItem? _selected;
  List<AudioCandidate> _files = const <AudioCandidate>[];
  bool _searching = false;
  bool _loadingFiles = false;
  String? _message;

  DownloadProgress? _progress;
  AudioCandidate? _downloading;

  @override
  void initState() {
    super.initState();
    _downloader.directory = _musicDirectory();
  }

  @override
  void dispose() {
    if (widget.downloader == null) _downloader.close();
    _query.dispose();
    _url.dispose();
    super.dispose();
  }

  /// Carpeta de descargas: si la biblioteca ya escaneó algo, la carpeta de la
  /// pista que suena es el mejor destino posible.
  String _musicDirectory() {
    final snapshot = widget.controller.snapshot;
    final index = snapshot.queueIndex;
    if (index >= 0 && index < snapshot.queue.length) {
      final path = snapshot.queue[index].path;
      final slash = path.lastIndexOf(Platform.pathSeparator);
      if (slash > 0) return path.substring(0, slash);
    }
    return _downloader.directory;
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) {
      setState(() => _message = 'Escribe algo que buscar.');
      return;
    }
    setState(() {
      _searching = true;
      _message = null;
      _results = const <ArchiveItem>[];
      _files = const <AudioCandidate>[];
      _selected = null;
    });
    final results = await _downloader.search(query);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = results;
      _message = results.isEmpty
          ? 'Sin resultados (o sin conexión).'
          : '${results.length} resultados en Internet Archive.';
    });
  }

  Future<void> _openItem(ArchiveItem item) async {
    setState(() {
      _selected = item;
      _loadingFiles = true;
      _files = const <AudioCandidate>[];
      _message = null;
    });
    final files = await _downloader.files(item.identifier);
    if (!mounted) return;
    setState(() {
      _loadingFiles = false;
      _files = files;
      _message = files.isEmpty
          ? 'Ese ítem no tiene archivos de audio reconocibles.'
          : '${files.length} archivos de audio.';
    });
  }

  Future<void> _download(AudioCandidate candidate) async {
    setState(() {
      _downloading = candidate;
      _progress = const DownloadProgress(received: 0, total: -1);
      _message = null;
    });
    final file = await _downloader.download(
      candidate,
      onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      },
    );
    if (!mounted) return;
    setState(() {
      _downloading = null;
      _progress = null;
      _message = file == null
          ? 'No se pudo descargar ${candidate.name}.'
          : 'Guardado en ${file.path}';
    });
    if (file != null) _downloaded = file;
  }

  File? _downloaded;

  void _enqueueLast() {
    final file = _downloaded;
    if (file == null) return;
    final ok = widget.controller.enqueue(file.path);
    setState(() => _message = ok
        ? '«${file.path.split(Platform.pathSeparator).last}» añadida a la cola.'
        : 'El motor no aceptó la pista.');
  }

  Future<void> _downloadUrl() async {
    final url = _url.text.trim();
    if (!url.startsWith('http')) {
      setState(() => _message = 'Pega una URL que empiece por http(s).');
      return;
    }
    await _download(candidateFromUrl(url));
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final fraction = progress?.fraction;
    return Scaffold(
      appBar: AppBar(title: const Text('Descargas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Buscar en Internet Archive',
              hintText: 'por ejemplo: blues 1927, piano nocturno…',
              labelStyle: const TextStyle(fontSize: 12, color: chMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'URL directa de audio',
              hintText: 'https://…/episodio.mp3',
              labelStyle: const TextStyle(fontSize: 12, color: chMuted),
              prefixIcon: const Icon(Icons.link_rounded, size: 20),
              suffixIcon: IconButton(
                tooltip: 'Descargar la URL',
                onPressed: _downloading == null ? _downloadUrl : null,
                icon: const Icon(Icons.download_rounded, size: 20),
              ),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _message!,
                style: const TextStyle(fontSize: 12, color: chAccent),
              ),
            ),
          if (_downloading != null) ...[
            const SizedBox(height: 14),
            Text(
              'Descargando ${_downloading!.name}',
              style: const TextStyle(fontSize: 12, color: chForeground),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: chSurfaceHigh,
              color: chAccent,
            ),
            const SizedBox(height: 4),
            Text(
              progress == null
                  ? ''
                  : fraction == null
                      ? '${_kib(progress.received)} recibidos'
                      : '${(fraction * 100).round()} % · '
                          '${_kib(progress.received)} de ${_kib(progress.total)}',
              style: const TextStyle(fontSize: 11, color: chMuted),
            ),
          ],
          if (_downloaded != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _enqueueLast,
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text('Añadir a la cola'),
              ),
            ),
          if (_results.isNotEmpty) ...[
            const _Label('Resultados'),
            for (final item in _results)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _selected?.identifier == item.identifier
                      ? Icons.radio_button_checked_rounded
                      : Icons.album_outlined,
                  color: chAccent,
                  size: 20,
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  item.subtitle.isEmpty ? item.identifier : item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: chMuted),
                ),
                onTap: _loadingFiles ? null : () => _openItem(item),
              ),
          ],
          if (_loadingFiles)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_files.isNotEmpty) ...[
            _Label('Archivos de ${_selected?.title ?? ''}'),
            for (final candidate in _files)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.audio_file_outlined, size: 20, color: chMuted),
                title: Text(
                  candidate.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${candidate.format} · ${candidate.sizeLabel}',
                  style: const TextStyle(fontSize: 11, color: chMuted),
                ),
                trailing: IconButton(
                  tooltip: 'Descargar',
                  onPressed: _downloading == null
                      ? () => _download(candidate)
                      : null,
                  icon: const Icon(Icons.download_rounded, size: 20),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _kib(int bytes) {
    if (bytes <= 0) return '0 KiB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: chMuted),
      ),
    );
  }
}
