import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../theme.dart';

/// Estilo del analizador de espectro.
enum VisualizerStyle {
  /// Barras verticales clásicas.
  bars,

  /// Hexágonos apilados: la columna más alta se convierte en panal.
  hexagon;

  String get label => this == VisualizerStyle.bars ? 'Barras' : 'Hexágonos';

  VisualizerStyle get next => this == VisualizerStyle.bars
      ? VisualizerStyle.hexagon
      : VisualizerStyle.bars;
}

/// Vúmetro (RMS y pico por canal) + espectro, leyendo del motor.
///
/// Sondea a ~30 Hz con un temporizador propio: no toca el snapshot ni provoca
/// repintados de la pantalla entera, y `levels()`/`spectrum()` no bloquean (lo
/// dice el contrato del núcleo). Con la animación desactivada se queda en un
/// solo fotograma para no gastar batería.
class VisualizerWidget extends StatefulWidget {
  const VisualizerWidget({
    super.key,
    required this.controller,
    this.style = VisualizerStyle.bars,
    this.bands = 28,
    this.height = 168,
    this.showMeters = true,
    this.color,
  });

  final PlayerController controller;
  final VisualizerStyle style;
  final int bands;
  final double height;
  final bool showMeters;
  final Color? color;

  @override
  State<VisualizerWidget> createState() => _VisualizerWidgetState();
}

class _VisualizerWidgetState extends State<VisualizerWidget> {
  static const Duration _interval = Duration(milliseconds: 33);

  Timer? _timer;
  List<double> _spectrum = const <double>[];
  PlayerLevels _levels = PlayerLevels.silent;

  /// Suavizado por banda: sube rápido, baja lento (como un vúmetro de verdad).
  late List<double> _smooth = List<double>.filled(widget.bands, 0);

  @override
  void initState() {
    super.initState();
    _smooth = List<double>.filled(widget.bands, 0);
    _timer = Timer.periodic(_interval, (_) => _poll());
    _poll();
  }

  @override
  void didUpdateWidget(VisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bands != widget.bands) {
      _smooth = List<double>.filled(widget.bands, 0);
      _spectrum = const <double>[];
      _poll();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _poll() {
    if (!mounted) return;
    final raw = widget.controller.spectrum(widget.bands);
    final levels = widget.controller.levels();
    var changed = false;
    if (raw.length == widget.bands) {
      for (var i = 0; i < raw.length; i++) {
        final target = raw[i].clamp(0.0, 1.0).toDouble();
        final next = target > _smooth[i]
            ? _smooth[i] + (target - _smooth[i]) * 0.6
            : _smooth[i] * 0.82;
        if ((next - _smooth[i]).abs() > 0.001) changed = true;
        _smooth[i] = next;
      }
      if (_spectrum.length != raw.length) changed = true;
      _spectrum = List<double>.of(raw);
    }
    if (levels != _levels) changed = true;
    _levels = levels;
    if (changed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
    final palette = paletteOf(context);
    final color = widget.color ?? palette.accent;
    return Semantics(
      label: 'Visualizador: ${widget.style.label}',
      value: _levels.isSilent ? 'silencio' : _levels.toString(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _SpectrumPainter(
                values: _smooth,
                style: widget.style,
                color: color,
                surface: palette.surface,
                border: palette.border,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          if (widget.showMeters) ...[
            const SizedBox(height: 8),
            _MeterRow(levels: _levels, color: color),
          ],
        ],
      ),
    );
  }
}

/// Dos barras horizontales por canal: RMS de fondo, pico encima y la marca de
/// pico retenida un momento (clip = rojo).
class _MeterRow extends StatelessWidget {
  const _MeterRow({required this.levels, required this.color});

  final PlayerLevels levels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MeterBar(
          label: 'L',
          rms: levels.rmsLeft,
          peak: levels.peakLeft,
          color: color,
        ),
        const SizedBox(height: 6),
        _MeterBar(
          label: 'R',
          rms: levels.rmsRight,
          peak: levels.peakRight,
          color: color,
        ),
      ],
    );
  }
}

class _MeterBar extends StatelessWidget {
  const _MeterBar({
    required this.label,
    required this.rms,
    required this.peak,
    required this.color,
  });

  final String label;
  final double rms;
  final double peak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final clipped = peak >= 0.999;
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            label,
            style: TextStyle(fontSize: 10, color: palette.muted),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: palette.surfaceHigh),
                  FractionallySizedBox(
                    widthFactor: rms.clamp(0.0, 1.0).toDouble(),
                    child: Container(color: color.withValues(alpha: 0.55)),
                  ),
                  FractionallySizedBox(
                    widthFactor: peak.clamp(0.0, 1.0).toDouble(),
                    child: Container(
                      color: clipped ? palette.error : color,
                      // El pico se ve como una línea fina: es el nivel real.
                      alignment: Alignment.centerRight,
                      child: const SizedBox(width: 2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            clipped ? 'CLIP' : _db(peak),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10,
              color: clipped ? palette.error : palette.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  static String _db(double value) {
    if (value <= 0) return '-∞';
    final db = 20 * (math.log(value) / math.ln10);
    return '${db.toStringAsFixed(db <= -10 ? 0 : 1)}';
  }
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter({
    required this.values,
    required this.style,
    required this.color,
    required this.surface,
    required this.border,
  });

  final List<double> values;
  final VisualizerStyle style;
  final Color color;
  final Color surface;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    final background = Paint()..color = surface.withValues(alpha: 0.45);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      background,
    );

    final gap = style == VisualizerStyle.bars ? 3.0 : 4.0;
    final slot = (size.width - gap * (values.length - 1)) / values.length;
    if (slot <= 0) return;

    for (var i = 0; i < values.length; i++) {
      final level = values[i].clamp(0.0, 1.0).toDouble();
      final left = i * (slot + gap);
      // Escala visual: el oído es logarítmico, la barra también.
      final scaled = math.pow(level, 0.65).toDouble();
      final height = math.max(scaled * (size.height - 12), 2.0);
      final paint = Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: <Color>[color.withValues(alpha: 0.35), color],
            ).createShader(
              Rect.fromLTWH(left, size.height - height - 6, slot, height),
            );

      if (style == VisualizerStyle.bars) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, size.height - height - 6, slot, height),
            Radius.circular(math.min(slot / 2, 4)),
          ),
          paint,
        );
      } else {
        _paintHexColumn(canvas, left, slot, height, size.height, paint);
      }
    }
  }

  /// Columna de hexágonos: cada celda ocupa 1/8 de la altura.
  void _paintHexColumn(
    Canvas canvas,
    double left,
    double width,
    double height,
    double totalHeight,
    Paint paint,
  ) {
    const cells = 8;
    final cellHeight = (totalHeight - 12) / cells;
    final lit = (height / (totalHeight - 12) * cells).ceil();
    final radius = math.min(width, cellHeight) / 2 - 1;
    if (radius <= 0.5) return;
    for (var c = 0; c < cells; c++) {
      final centerY = totalHeight - 6 - cellHeight * (c + 0.5);
      final center = Offset(left + width / 2, centerY);
      final cellPaint = c < lit
          ? paint
          : (Paint()..color = border.withValues(alpha: 0.35));
      canvas.drawPath(_hexagon(center, radius), cellPaint);
    }
  }

  static Path _hexagon(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 2;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.surface != surface ||
      oldDelegate.border != border ||
      oldDelegate.style != style ||
      oldDelegate.values.length != values.length ||
      _changed(oldDelegate.values, values);

  static bool _changed(List<double> a, List<double> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.002) return true;
    }
    return false;
  }
}
