import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Fondo con rejilla hexagonal sutil: dibuja una malla de hexágonos muy tenues
/// sobre el color de fondo. No afecta al rendimiento (se pinta una vez y se
/// cachea como `Picture`). El tono sale del `palette.border` con opacidad muy baja.
class HexGridBackground extends StatelessWidget {
  const HexGridBackground({super.key, required this.palette});

  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _HexGridPainter(palette: palette),
      size: Size.infinite,
    );
  }
}

class _HexGridPainter extends CustomPainter {
  _HexGridPainter({required this.palette});

  final CyberHexPalette palette;

  late final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6
    ..color = palette.border.withValues(alpha: 0.06);

  // Tamaño del hexágono (radio del circuncírculo)
  static const double _radius = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Altura del hexágono (flat-top): 2 * r * cos(30°) = sqrt(3) * r
    final double hexHeight = _radius * math.sqrt(3);
    // Ancho del hexágono (flat-top): 2 * r
    final double hexWidth = 2 * _radius;

    // Espaciado horizontal: 3/4 del ancho (hexágonos se solapan 1/4)
    final double colStep = hexWidth * 0.75;
    // Espaciado vertical: altura del hexágono
    final double rowStep = hexHeight;

    final int cols = (size.width / colStep).ceil() + 2;
    final int rows = (size.height / rowStep).ceil() + 2;

    for (int col = -1; col <= cols; col++) {
      for (int row = -1; row <= rows; row++) {
        final double cx = col * colStep;
        // Filas impares se desplazan media altura
        final double cy = row * rowStep + (col.isOdd ? hexHeight / 2 : 0);

        // Solo pintamos si el centro está cerca del viewport (margen de 1 hex)
        if (cx + _radius < 0 ||
            cx - _radius > size.width ||
            cy + hexHeight / 2 < 0 ||
            cy - hexHeight / 2 > size.height) {
          continue;
        }

        _drawHex(canvas, cx, cy);
      }
    }
  }

  void _drawHex(Canvas canvas, double cx, double cy) {
    final Path path = Path();
    // Hexágono flat-top: vértice en el ángulo 0 (derecha), paso de 60°.
    for (int i = 0; i < 6; i++) {
      final double angle = i * math.pi / 3;
      final double x = cx + _radius * math.cos(angle);
      final double y = cy + _radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, _paint);
  }

  @override
  bool shouldRepaint(covariant _HexGridPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
