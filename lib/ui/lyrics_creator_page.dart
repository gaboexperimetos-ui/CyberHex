import 'package:material_ui/material_ui.dart';

import '../core/lyrics_parser.dart';
import '../core/player_controller.dart';
import '../theme.dart';

/// Estudio de letras: convierte un texto pegado en un `.lrc` sincronizado.
///
/// El flujo es el de un karaoké casero: se pega la letra, se da al play y se
/// pulsa **«Marcar verso»** al ritmo de la música. Cada pulsación sella la línea
/// actual con la posición del motor y avanza a la siguiente; si un verso se fue
/// largo, `±0,1 s` lo corrige sin volver a empezar y «Deshacer» recula.
///
/// Al guardar escribe `tema.lrc` **junto al audio** (misma carpeta, mismo
/// nombre base), que es donde lo busca el visor la próxima vez.
class LyricsCreatorPage extends StatefulWidget {
  const LyricsCreatorPage({super.key, required this.controller, this.lyrics});

  final PlayerController controller;

  /// Letra de partida (si ya existía). Solo se usa el texto, no los tiempos.
  final Lyrics? lyrics;

  @override
  State<LyricsCreatorPage> createState() => _LyricsCreatorPageState();
}

class _LyricsCreatorPageState extends State<LyricsCreatorPage> {
  late final TextEditingController _text = TextEditingController(
    text: (widget.lyrics?.lines ?? const <LyricLine>[])
        .map((line) => line.text)
        .join('\n'),
  );

  List<LyricLine> _lines = const <LyricLine>[];
  List<double> _stamps = <double>[];
  int _cursor = 0;
  String? _message;

  PlayerController get _controller => widget.controller;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _path {
    final snapshot = _controller.snapshot;
    final index = snapshot.queueIndex;
    if (index < 0 || index >= snapshot.queue.length) return '';
    return snapshot.queue[index].path;
  }

  void _prepare() {
    final lines = LyricsParser.parsePlain(_text.text).lines;
    setState(() {
      _lines = lines;
      _stamps = List<double>.filled(lines.length, -1);
      _cursor = 0;
      _message = lines.isEmpty
          ? 'Pega la letra primero: una línea por renglón.'
          : '${lines.length} versos listos. Dale al play y marca.';
    });
  }

  void _mark() {
    if (_lines.isEmpty) {
      _prepare();
      return;
    }
    if (_cursor >= _lines.length) {
      setState(() => _message = 'Ya están todos marcados. Guarda el .lrc.');
      return;
    }
    final seconds = _controller.position.value;
    setState(() {
      _stamps[_cursor] = (seconds * 100).round() / 100;
      _cursor += 1;
      _message = _cursor >= _lines.length
          ? 'Último verso marcado. Guarda el .lrc.'
          : 'Verso ${_cursor} de ${_lines.length}.';
    });
    _scrollToCursor();
  }

  /// Ajuste fino del último verso marcado (o del que toca, si aún no hay).
  void _nudge(double delta) {
    if (_lines.isEmpty || _stamps.isEmpty) return;
    final index = (_cursor > 0 ? _cursor - 1 : 0).clamp(0, _lines.length - 1);
    if (_stamps[index] < 0) return;
    setState(() {
      final next = (_stamps[index] + delta).clamp(0.0, double.infinity);
      _stamps[index] = (next * 100).round() / 100;
      _message = 'Verso ${index + 1}: ${_stamps[index].toStringAsFixed(2)} s';
    });
  }

  void _undo() {
    if (_cursor == 0 || _stamps.isEmpty) return;
    setState(() {
      _cursor -= 1;
      _stamps[_cursor] = -1;
      _message = 'Deshecho: verso ${_cursor + 1}.';
    });
    _scrollToCursor();
  }

  void _scrollToCursor() {
    // La lista es corta (una canción): no hace falta controlar el scroll más
    // allá de dejar el verso actual a la vista.
    final index = _cursor.clamp(0, _lines.isEmpty ? 0 : _lines.length - 1);
    if (index < 0) return;
    final key = _rowKeys[index];
    final context = key?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 220));
    }
  }

  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};

  Future<void> _save() async {
    final path = _path;
    if (path.isEmpty) {
      setState(() => _message = 'Abre una pista antes de guardar la letra.');
      return;
    }
    final timed = <LyricLine>[];
    for (var i = 0; i < _lines.length; i++) {
      final stamp = i < _stamps.length ? _stamps[i] : -1.0;
      if (stamp < 0) continue;
      timed.add(_lines[i].copyWith(time: stamp));
    }
    if (timed.isEmpty) {
      setState(() => _message = 'Marca al menos un verso antes de guardar.');
      return;
    }
    final snapshot = _controller.snapshot;
    final lyrics = Lyrics(
      lines: timed,
      tags: <String, String>{
        if (snapshot.title.isNotEmpty) 'ti': snapshot.title,
        if (snapshot.artist.isNotEmpty) 'ar': snapshot.artist,
        if (snapshot.album.isNotEmpty) 'al': snapshot.album,
        'by': 'CyberHex',
      },
      origin: 'lrc',
    );
    final file = LrcWriter.saveNextTo(path, lyrics);
    if (!mounted) return;
    setState(() {
      _message = file == null
          ? (LrcWriter.lastError ?? 'No se pudo guardar la letra.')
          : 'Guardado en ${file.path}';
    });
    if (file != null && Navigator.of(context).canPop()) {
      // El visor recarga al volver.
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _controller.snapshot;
    return Scaffold(
      backgroundColor: chBackground,
      appBar: AppBar(
        backgroundColor: chBackground,
        foregroundColor: chForeground,
        title: const Text('Estudio de letras', style: TextStyle(fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'Guardar .lrc junto al audio',
            onPressed: _lines.isEmpty ? null : _save,
            icon: const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _Transport(
              controller: _controller,
              title: snapshot.title.isEmpty ? 'Sin pista' : snapshot.title,
              artist: snapshot.artist,
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  _message!,
                  style: const TextStyle(fontSize: 12, color: chAccent),
                ),
              ),
            if (_lines.isEmpty) _pastePanel() else _editorPanel(),
          ],
        ),
      ),
    );
  }

  Widget _pastePanel() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pega la letra (una línea por verso)',
              style: TextStyle(fontSize: 13, color: chMuted),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: chSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: chBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _text,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'La primera línea es el primer verso…',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _prepare,
              icon: const Icon(Icons.format_list_numbered_rounded, size: 18),
              label: const Text('Preparar versos'),
              style: FilledButton.styleFrom(
                backgroundColor: chAccent,
                foregroundColor: chOnAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorPanel() {
    final position = _controller.position;
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final key = _rowKeys.putIfAbsent(index, GlobalKey.new);
                final stamp = index < _stamps.length ? _stamps[index] : -1.0;
                final current = index == _cursor;
                return Padding(
                  key: key,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _cursor = index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: current
                            ? chAccent.withValues(alpha: 0.12)
                            : chSurface.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _lines[index].text,
                              style: TextStyle(
                                fontSize: 14,
                                color: stamp >= 0 ? chForeground : chMuted,
                                fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            stamp >= 0 ? _stamp(stamp) : '—',
                            style: TextStyle(
                              fontSize: 11,
                              color: stamp >= 0 ? chAccent : chMuted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: position,
            builder: (context, seconds, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Posición: ${_stamp(seconds)} · verso ${(_cursor + 1).clamp(1, _lines.length)} de ${_lines.length}',
                style: const TextStyle(fontSize: 11, color: chMuted),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _mark,
                    icon: const Icon(Icons.flag_rounded, size: 18),
                    label: const Text('Marcar verso'),
                    style: FilledButton.styleFrom(
                      backgroundColor: chAccent,
                      foregroundColor: chOnAccent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _nudge(-0.1),
                        child: const Text('− 0,1 s'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _nudge(0.1),
                        child: const Text('+ 0,1 s'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _undo,
                        child: const Text('Deshacer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _stamp(double seconds) {
    if (!seconds.isFinite || seconds < 0) return '--:--';
    final total = seconds.floor();
    final centis = ((seconds - total) * 100).round().clamp(0, 99);
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}.'
        '${centis.toString().padLeft(2, '0')}';
  }
}

/// Transporte mínimo: play/pausa y saltos de cinco segundos.
class _Transport extends StatelessWidget {
  const _Transport({required this.controller, required this.title, required this.artist});

  final PlayerController controller;
  final String title;
  final String artist;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: chSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: chBorder.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (artist.isNotEmpty)
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: chMuted),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atrás 5 s',
            onPressed: () {
              final target = controller.position.value - 5;
              controller.seek(target < 0 ? 0 : target);
            },
            icon: const Icon(Icons.replay_5_rounded),
          ),
          IconButton(
            tooltip: snapshot.playing ? 'Pausa' : 'Reproducir',
            onPressed: controller.toggle,
            icon: Icon(
              snapshot.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: chAccent,
            ),
          ),
          IconButton(
            tooltip: 'Adelante 5 s',
            onPressed: () => controller.seek(controller.position.value + 5),
            icon: const Icon(Icons.forward_5_rounded),
          ),
        ],
      ),
    );
  }
}
