import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Carátula de reserva con forma de hexágono.
///
/// El tono sale del propio texto que se pase como [seed] (título, álbum o
/// artista), así que dos pistas distintas no repiten color por casualidad. Es
/// la marca visual de CyberHex cuando el archivo no trae portada: en vez de un
/// cuadrado gris, un hexágono con la inicial, un halo y dos anillos que
/// evocan una señal.
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

  /// Color del precinto: el acento del tema girado según el texto.
  Color _tint() {
    final hash =
        seed.codeUnits.fold<int>(0, (acc, unit) => acc * 31 + unit) &
        0x7fffffff;
    final hsl = HSLColor.fromColor(palette.accent);
    final hue = (hsl.hue + ((hash % 80) - 40) + 360) % 360;
    final lightness = palette.isDark
        ? (hsl.lightness * 0.9).clamp(0.42, 0.62)
        : (hsl.lightness * 0.82).clamp(0.36, 0.52);
    return hsl
        .withHue(hue)
        .withSaturation(hsl.saturation.clamp(0.5, 0.95))
        .withLightness(lightness)
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
      child: ClipPath(
        clipper: const HexClipper(),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(
              painter: _HexArtPainter(
                tone: tint,
                base: palette.surface,
                deep: palette.background,
                seed: seed,
              ),
            ),
            Center(
              child: Text(
                _initial(seed),
                style: TextStyle(
                  fontFamily: 'Righteous',
                  fontSize: size * 0.34,
                  color: Colors.white.withValues(alpha: 0.95),
                  shadows: <Shadow>[
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: size * 0.06,
                      offset: Offset(0, size * 0.01),
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
}

/// Pintura del hexágono: degradado, halo, anillos y viñeta inferior.
class _HexArtPainter extends CustomPainter {
  const _HexArtPainter({
    required this.tone,
    required this.base,
    required this.deep,
    required this.seed,
  });

  final Color tone;
  final Color base;
  final Color deep;

  /// Solo se usa para variar el eje del degradado entre carátulas.
  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    final diagonal =
        seed.codeUnits.fold<int>(0, (acc, unit) => acc + unit) % 2 == 0;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: diagonal ? Alignment.topLeft : Alignment.topRight,
          end: diagonal ? Alignment.bottomRight : Alignment.bottomLeft,
          colors: <Color>[
            Color.lerp(tone, Colors.white, 0.16)!,
            Color.lerp(tone, base, 0.55)!,
            Color.lerp(deep, base, 0.35)!,
          ],
          stops: const <double>[0, 0.55, 1],
        ).createShader(rect),
    );

    // Halo suave desde la esquina superior.
    final glowCenter = Offset(
      diagonal ? size.width * 0.28 : size.width * 0.72,
      size.height * 0.22,
    );
    canvas.drawCircle(
      glowCenter,
      size.width * 0.75,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: glowCenter, radius: size.width * 0.75),
        ),
    );

    // Anillos hexagonales: la idea de "señal" de la marca.
    final center = size.center(Offset.zero);
    for (final scale in <double>[0.9, 0.66]) {
      final ring = _scaledHexPath(size, scale, center);
      canvas.drawPath(
        ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, size.width * 0.008)
          ..color = Colors.white.withValues(alpha: scale > 0.8 ? 0.16 : 0.10),
      );
    }

    // Viñeta inferior: da peso al óvalo de la inicial.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.center,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: 0.28),
          ],
        ).createShader(rect),
    );

    // Contorno interior fino.
    canvas.drawPath(
      hexPath(size, inset: 0.9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  Path _scaledHexPath(Size size, double scale, Offset center) {
    final w = size.width * scale;
    final h = size.height * scale;
    final left = center.dx - w / 2;
    final top = center.dy - h / 2;
    final shoulder = h * 0.25;
    return Path()
      ..moveTo(center.dx, top)
      ..lineTo(left + w, top + shoulder)
      ..lineTo(left + w, top + h - shoulder)
      ..lineTo(center.dx, top + h)
      ..lineTo(left, top + h - shoulder)
      ..lineTo(left, top + shoulder)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _HexArtPainter oldDelegate) =>
      oldDelegate.tone != tone ||
      oldDelegate.base != base ||
      oldDelegate.deep != deep ||
      oldDelegate.seed != seed;
}

/// Recorte hexagonal (punta arriba), compartido con el resto de la UI.
class HexClipper extends CustomClipper<Path> {
  const HexClipper();

  @override
  Path getClip(Size size) => hexPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Traza el hexágono de la marca dentro de [size].
Path hexPath(Size size, {double inset = 0}) {
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
