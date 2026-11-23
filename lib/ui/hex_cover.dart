import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Carátula de reserva con forma de hexágono.
///
/// El tono sale del propio texto que se pase como [seed] (título, álbum o
/// artista), así que dos pistas distintas no repiten color por casualidad. Es
/// la marca visual de CyberHex cuando el archivo no trae portada: en vez de un
/// cuadrado gris, un hexágono con la inicial y un contorno del acento.
class HexCover extends StatelessWidget {
  const HexCover({
    super.key,
    required this.seed,
    required this.palette,
    this.size = 112,
  });

  final String seed;
  final CyberHexPalette palette;
  final double size;

  Color _tint() {
    final hash =
        seed.codeUnits.fold<int>(0, (acc, unit) => acc * 31 + unit) &
        0x7fffffff;
    final hsl = HSLColor.fromColor(palette.accent);
    final hue = (hsl.hue + ((hash % 90) - 45) + 360) % 360;
    return hsl
        .withHue(hue)
        .withSaturation(hsl.saturation.clamp(0.45, 1.0))
        .toColor();
  }

  static String _initial(String text) {
    for (final rune in text.trim().runes) {
      final char = String.fromCharCode(rune).trim();
      if (char.isNotEmpty) return char.toUpperCase();
    }
    return '#';
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipPath(
            clipper: const _HexClipper(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color.lerp(tint, palette.surfaceHigh, 0.25)!,
                    Color.lerp(palette.surface, palette.background, 0.35)!,
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  _initial(seed),
                  style: TextStyle(
                    fontFamily: 'Righteous',
                    fontSize: size * 0.38,
                    color: Colors.white.withValues(alpha: 0.92),
                    shadows: <Shadow>[
                      Shadow(
                        color: tint.withValues(alpha: 0.85),
                        blurRadius: size * 0.14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          CustomPaint(
            painter: _HexPainter(color: tint.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}

class _HexClipper extends CustomClipper<Path> {
  const _HexClipper();

  @override
  Path getClip(Size size) => _hexPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _HexPainter extends CustomPainter {
  const _HexPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    canvas.drawPath(_hexPath(size, inset: 1.2), paint);
  }

  @override
  bool shouldRepaint(covariant _HexPainter oldDelegate) =>
      oldDelegate.color != color;
}

Path _hexPath(Size size, {double inset = 0}) {
  final w = size.width;
  final h = size.height;
  final shoulder = h * 0.25;
  return Path()
    ..moveTo(w / 2, inset)
    ..lineTo(w - inset, shoulder)
    ..lineTo(w - inset, h - shoulder)
    ..lineTo(w / 2, h - inset)
    ..lineTo(inset, h - shoulder)
    ..lineTo(inset, shoulder)
    ..close();
}
