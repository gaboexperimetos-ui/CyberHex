import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../core/lyrics_parser.dart';
import '../core/player_controller.dart';
import '../theme.dart';

/// Tarjeta compartible: carátula, pista, un verso elegido y una forma de onda.
///
/// Se pinta como un widget normal dentro de un [RepaintBoundary], así que la
/// exportación es literalmente *lo que se ve*: `toImage(pixelRatio: 3)` y a PNG.
/// No hay paquetes de captura ni de imagen: `dart:ui` basta.
///
/// La forma de onda es **decorativa y determinista** ([shareWaveform]): el
/// núcleo no expone todavía los picos de la pista (está en el backlog, P0.5), así
/// que se dibuja una silueta estable a partir del título y el artista —la misma
/// canción da siempre la misma tarjeta— en vez de inventar un nivel falso.
class ShareCardSheet extends StatefulWidget {
  const ShareCardSheet({
    super.key,
    required this.controller,
    this.lyrics,
    this.initialVerse,
  });

  final PlayerController controller;

  /// Letra de la que salen los versos propuestos.
  final Lyrics? lyrics;

  /// Verso con el que se abre (si no, el que suena).
  final String? initialVerse;

  static Future<void> show(
    BuildContext context,
    PlayerController controller, {
    Lyrics? lyrics,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ShareCardSheet(controller: controller, lyrics: lyrics),
    );
  }

  @override
  State<ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<ShareCardSheet> {
  final GlobalKey _cardKey = GlobalKey();
  late final TextEditingController _verse =
      TextEditingController(text: widget.initialVerse ?? '');
  int _verseIndex = -1;
  bool _busy = false;
  String? _message;

  PlayerController get _controller => widget.controller;

  List<String> get _candidates => <String>[
        for (final line in widget.lyrics?.lines ?? const <LyricLine>[])
          if (line.text.trim().isNotEmpty) line.text.trim(),
      ];

  @override
  void initState() {
    super.initState();
    if (_verse.text.trim().isEmpty) {
      final lines = _candidates;
      if (lines.isNotEmpty) {
        final live = widget.lyrics?.indexAt(_controller.position.value) ?? -1;
        _verseIndex = live >= 0 && live < lines.length ? live : 0;
        _verse.text = lines[_verseIndex];
      } else {
        _verse.text = 'Dale al play. Esto suena a CyberHex.';
      }
    }
  }

  @override
  void dispose() {
    _verse.dispose();
    super.dispose();
  }

  void _nextVerse() {
    final lines = _candidates;
    if (lines.isEmpty) {
      setState(() => _message = 'Esta pista no tiene letra: escribe el verso que quieras.');
      return;
    }
    _verseIndex = (_verseIndex + 1) % lines.length;
    setState(() {
      _verse.text = lines[_verseIndex];
      _message = null;
    });
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final boundary = _cardKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        setState(() {
          _busy = false;
          _message = 'La tarjeta aún no está pintada.';
        });
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = data?.buffer.asUint8List();
      if (bytes == null) {
        setState(() {
          _busy = false;
          _message = 'No se pudo convertir la tarjeta a PNG.';
        });
        return;
      }
      const group = XTypeGroup(label: 'PNG', extensions: <String>['png']);
      final location = await getSaveLocation(
        suggestedName: 'cyberhex_tarjeta.png',
        acceptedTypeGroups: const <XTypeGroup>[group],
      );
      if (location == null) {
        setState(() {
          _busy = false;
          _message = 'Exportación cancelada.';
        });
        return;
      }
      await File(location.path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Guardado en ${location.path}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'No se pudo exportar: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _controller.snapshot;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tarjeta compartible',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Se exporta tal cual se ve, a 3× (unas 1020 × 1320 px).',
                style: TextStyle(fontSize: 12, color: chMuted),
              ),
              const SizedBox(height: 14),
              Center(
                child: RepaintBoundary(
                  key: _cardKey,
                  child: ShareCard(
                    title: snapshot.title.isEmpty ? 'CyberHex' : snapshot.title,
                    artist: snapshot.artist,
                    album: snapshot.album,
                    cover: snapshot.cover,
                    verse: _verse.text,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _verse,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(fontSize: 14, height: 1.35),
                decoration: InputDecoration(
                  labelText: 'Verso de la tarjeta',
                  labelStyle: const TextStyle(fontSize: 12, color: chMuted),
                  filled: true,
                  fillColor: chSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: chBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: chBorder),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _nextVerse,
                      icon: const Icon(Icons.shuffle_rounded, size: 18),
                      label: const Text('Otro verso'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Guardar PNG'),
                      style: FilledButton.styleFrom(
                        backgroundColor: chAccent,
                        foregroundColor: chOnAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  style: const TextStyle(fontSize: 12, color: chAccent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// La tarjeta en sí. Pública para poder pintarla en pruebas y en vistas previas.
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    required this.cover,
    required this.verse,
  });

  final String title;
  final String artist;
  final String album;
  final Uint8List? cover;
  final String verse;

  @override
  Widget build(BuildContext context) {
    final image = cover;
    final bars = shareWaveform('$title|$artist', bars: 46);
    return Container(
      width: 340,
      height: 440,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF17173A), Color(0xFF0B0B1A), Color(0xFF101033)],
        ),
        border: Border.all(color: chAccent.withValues(alpha: 0.35)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: chAccent.withValues(alpha: 0.18),
            blurRadius: 40,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 168,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image != null)
                    Image.memory(
                      image,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: 680,
                      errorBuilder: (_, __, ___) => _coverFallback(),
                    )
                  else
                    _coverFallback(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.transparent,
                          const Color(0xFF0B0B1A).withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verse.trim().isEmpty ? '—' : verse.trim(),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: chForeground,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 34,
                      child: CustomPaint(
                        painter: _WavePainter(values: bars),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: chForeground,
                      ),
                    ),
                    Text(
                      <String>[artist, album].where((part) => part.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: chMuted),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: chAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'CYBERHEX',
                          style: TextStyle(
                            fontFamily: 'Righteous',
                            fontSize: 11,
                            letterSpacing: 2.4,
                            color: chAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[chSecondary, Color(0xFF141433)],
        ),
      ),
      child: Center(
        child: Icon(Icons.graphic_eq_rounded, size: 44, color: chOnAccent),
      ),
    );
  }
}

/// Silueta determinista de 0..1 a partir de una semilla de texto.
///
/// No es la forma de onda real (el núcleo aún no la expone): es un dibujo
/// estable, suave y distinto por pista, para que la tarjeta no salga idéntica
/// siempre. Se documenta aquí para no confundirla con datos medidos.
List<double> shareWaveform(String seed, {int bars = 46}) {
  if (bars <= 0) return const <double>[];
  var state = 0x811C9DC5;
  for (final unit in seed.codeUnits) {
    state = (state ^ unit) * 0x01000193 & 0xFFFFFFFF;
  }
  final random = math.Random(state);
  final out = <double>[];
  var level = 0.55;
  for (var i = 0; i < bars; i++) {
    // Paseo aleatorio suave: se parece a una onda, no a ruido.
    level = (level + (random.nextDouble() - 0.5) * 0.35).clamp(0.08, 1.0);
    final envelope = math.sin(math.pi * (i + 0.5) / bars);
    out.add((level * (0.35 + 0.65 * envelope)).clamp(0.05, 1.0).toDouble());
  }
  return List<double>.unmodifiable(out);
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    final slot = size.width / values.length;
    final paint = Paint()..color = chAccent.withValues(alpha: 0.85);
    for (var i = 0; i < values.length; i++) {
      final height = (values[i] * size.height).clamp(2.0, size.height);
      final left = i * slot + slot * 0.22;
      final width = math.max(slot * 0.56, 1.6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, (size.height - height) / 2, width, height),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.values != values;
}
