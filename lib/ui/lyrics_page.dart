import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../core/lyrics_parser.dart';
import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../theme.dart';
import 'lyrics_creator_page.dart';

/// Visor de letras sincronizadas a pantalla completa.
///
/// * Fondo: la carátula actual **difuminada** (y oscurecida), o el degradado del
///   tema si la pista no trae arte.
/// * La línea que suena se resalta y la lista se desplaza sola.
/// * Tocar un verso salta a su segundo exacto (y deja sonando).
/// * Si la letra trae traducción, se muestra debajo en gris; el botón de la
///   barra la oculta para quien solo quiera la original.
///
/// La letra se carga al abrir: primero el `.lrc` de al lado del archivo y, si no
/// hay, la incrustada (`USLT`/`LYRICS`). Con [initial] se puede inyectar una ya
/// cargada (lo usan las pruebas y el estudio de letras al guardar).
class LyricsPage extends StatefulWidget {
  const LyricsPage({
    super.key,
    required this.controller,
    this.initial,
    this.autoLoad = true,
  });

  final PlayerController controller;
  final Lyrics? initial;

  /// Si es `false` no toca el disco: solo muestra [initial].
  final bool autoLoad;

  static Future<void> show(
    BuildContext context,
    PlayerController controller, {
    Lyrics? initial,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LyricsPage(controller: controller, initial: initial),
      ),
    );
  }

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = <int, GlobalKey>{};

  Lyrics _lyrics = Lyrics.empty;
  bool _loading = true;
  bool _bilingual = true;
  String _source = '';
  int _current = -1;

  PlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _lyrics = initial;
      _source = initial.origin;
      _loading = false;
    }
    if (widget.autoLoad) {
      _load();
    } else {
      _loading = false;
    }
    _controller.position.addListener(_onPosition);
  }

  @override
  void dispose() {
    _controller.position.removeListener(_onPosition);
    _scroll.dispose();
    super.dispose();
  }

  String get _path {
    final snapshot = _controller.snapshot;
    final index = snapshot.queueIndex;
    if (index < 0 || index >= snapshot.queue.length) return '';
    return snapshot.queue[index].path;
  }

  Future<void> _load() async {
    final path = _path;
    if (path.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final loaded = await LyricsParser.loadForAudio(path);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!loaded.isEmpty) {
        _lyrics = loaded;
        _source = loaded.origin;
        _keys.clear();
      }
      _current = _lyrics.indexAt(_controller.position.value);
    });
    _onPosition();
  }

  void _onPosition() {
    if (!mounted || _lyrics.isEmpty) return;
    final index = _lyrics.indexAt(_controller.position.value);
    if (index == _current) return;
    setState(() => _current = index);
    _scrollTo(index);
  }

  void _scrollTo(int index) {
    if (index < 0) return;
    final key = _keys[index];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.42,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openCreator() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LyricsCreatorPage(controller: _controller, lyrics: _lyrics),
         fullscreenDialog: true,
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _controller.snapshot;
    final cover = snapshot.cover;
    final hasTranslation = _lyrics.lines.any((line) => line.hasTranslation);
    return Scaffold(
      backgroundColor: chBackground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: chForeground,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              snapshot.title.isEmpty ? 'Letras' : snapshot.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              _subtitle(snapshot),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: chMuted),
            ),
          ],
        ),
        actions: [
          if (hasTranslation)
            IconButton(
              tooltip: _bilingual ? 'Ocultar la traducción' : 'Mostrar la traducción',
              onPressed: () => setState(() => _bilingual = !_bilingual),
              icon: Icon(
                _bilingual ? Icons.translate_rounded : Icons.translate_outlined,
              ),
            ),
          IconButton(
            tooltip: 'Estudio de letras',
            onPressed: _openCreator,
            icon: const Icon(Icons.mic_external_on_rounded),
          ),
          IconButton(
            tooltip: 'Recargar la letra',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          _Backdrop(cover: cover),
          SafeArea(
            child: _body(context, snapshot),
          ),
        ],
      ),
    );
  }

  String _subtitle(PlayerSnapshot snapshot) {
    final parts = <String>[
      if (snapshot.artist.isNotEmpty) snapshot.artist,
      if (_loading)
        'cargando…'
      else if (_lyrics.isEmpty)
        'sin letra'
      else
        '${_lyrics.lines.length} líneas · ${_originLabel()}',
      if (_lyrics.offsetMs != 0) 'offset ${_lyrics.offsetMs > 0 ? '+' : ''}${_lyrics.offsetMs} ms',
    ];
    return parts.join(' · ');
  }

  String _originLabel() => switch (_source) {
        'embedded' => 'incrustada',
        'plain' => 'sin tiempo',
        'lrc' => '.lrc',
        _ => 'letra',
      };

  Widget _body(BuildContext context, PlayerSnapshot snapshot) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_lyrics.isEmpty) {
      return _EmptyLyrics(
        onCreator: _openCreator,
        onReload: _load,
        hasTrack: snapshot.hasTrack,
      );
    }
    final height = MediaQuery.sizeOf(context).height;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(24, height * 0.22, 24, height * 0.45),
      itemCount: _lyrics.lines.length,
      itemBuilder: (context, index) {
        final line = _lyrics.lines[index];
        final key = _keys.putIfAbsent(index, GlobalKey.new);
        final active = index == _current;
        return _LyricRow(
          key: key,
          line: line,
          active: active,
          showTranslation: _bilingual,
          onTap: line.isTimed
              ? () {
                  _controller.seek(_lyrics.displayTime(line));
                  if (!snapshot.playing) _controller.play();
                }
              : null,
        );
      },
    );
  }
}

/// Carátula difuminada a pantalla completa con un velo oscuro.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.cover});

  final Uint8List? cover;

  @override
  Widget build(BuildContext context) {
    final image = cover;
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
              child: Image.memory(
                image,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: 360,
                errorBuilder: (_, __, ___) => const ColoredBox(color: chBackground),
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xFF141433), chBackground, Color(0xFF090912)],
                  stops: <double>[0, 0.45, 1],
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  chBackground.withValues(alpha: 0.72),
                  chBackground.withValues(alpha: 0.86),
                  chBackground.withValues(alpha: 0.96),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({
    super.key,
    required this.line,
    required this.active,
    required this.showTranslation,
    required this.onTap,
  });

  final LyricLine line;
  final bool active;
  final bool showTranslation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: active ? chAccent.withValues(alpha: 0.10) : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line.text,
              style: TextStyle(
                fontSize: active ? 21 : 17,
                height: 1.32,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? chForeground
                    : chForeground.withValues(alpha: line.isTimed ? 0.62 : 0.42),
              ),
            ),
            if (showTranslation && line.hasTranslation)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  line.translation,
                  style: TextStyle(
                    fontSize: active ? 15 : 13,
                    height: 1.3,
                    color: active ? chAccent : chMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLyrics extends StatelessWidget {
  const _EmptyLyrics({
    required this.onCreator,
    required this.onReload,
    required this.hasTrack,
  });

  final VoidCallback onCreator;
  final VoidCallback onReload;
  final bool hasTrack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lyrics_outlined, size: 52, color: chMuted),
            const SizedBox(height: 14),
            Text(
              hasTrack
                  ? 'Esta pista no trae letra.'
                  : 'Abre una pista para ver su letra.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: chForeground),
            ),
            const SizedBox(height: 8),
            const Text(
              'CyberHex busca un archivo .lrc junto al audio y, si no hay, '
              'las letras incrustadas en el MP3 (USLT) o en el FLAC (LYRICS).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.45, color: chMuted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: hasTrack ? onCreator : null,
              icon: const Icon(Icons.mic_external_on_rounded, size: 18),
              label: const Text('Crear la letra'),
              style: FilledButton.styleFrom(
                backgroundColor: chAccent,
                foregroundColor: chOnAccent,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: onReload, child: const Text('Buscar de nuevo')),
          ],
        ),
      ),
    );
  }
}
