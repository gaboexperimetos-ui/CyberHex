import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';

import '../../theme.dart';
import '../hex_cover.dart';

/// Sistema visual de CyberHex.
///
/// Las pantallas no inventan estilos: todo sale de aquí. La regla de la casa
/// es una sola: **el acento marca lo vivo** (lo que suena, lo que se toca, lo
/// que está activo); el resto se resuelve con tono, no con bordes.
abstract final class ChSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 18;
  static const double xl = 26;
  static const double xxl = 38;
}

abstract final class ChRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 26;
  static const double pill = 999;
}

/// Degradados de la casa.
///
/// El acento entra por una esquina y se disuelve en la superficie. Es lo que
/// separa una tarjeta con carácter de un panel gris.
abstract final class ChGradient {
  static LinearGradient accentCard(
    CyberHexPalette palette, {
    double strength = 0.26,
  }) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color.lerp(palette.surfaceHigh, palette.accent, strength)!,
      palette.surface,
      Color.lerp(palette.surface, palette.secondary, 0.16)!,
    ],
    stops: const <double>[0, 0.52, 1],
  );
}

/// Etiqueta pequeña de sección o de estado.
TextStyle chEyebrow(
  CyberHexPalette palette, {
  Color? color,
  double size = 10.5,
}) => TextStyle(
  fontFamily: 'Poppins',
  fontSize: size,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.5,
  height: 1.2,
  color: color ?? palette.muted,
);

/// Dato técnico: tiempos, conteos, formatos y rutas.
///
/// La monoespaciada es parte de la personalidad: la app presume de motor
/// propio y de leer bytes, así que los números se leen como instrumentación.
TextStyle chMono(
  CyberHexPalette palette, {
  Color? color,
  double size = 11,
  FontWeight weight = FontWeight.w500,
  double letterSpacing = 0.3,
}) => TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: const <String>['Roboto Mono', 'DejaVu Sans Mono'],
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: 1.25,
  color: color ?? palette.muted,
  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
);

/// Título de contenido (pista, álbum, pantalla).
TextStyle chTitle(
  CyberHexPalette palette, {
  double size = 22,
  FontWeight weight = FontWeight.w600,
  Color? color,
  double letterSpacing = -0.3,
}) => TextStyle(
  fontFamily: 'Poppins',
  fontSize: size,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: 1.16,
  color: color ?? palette.foreground,
);

/// Superficie base: un solo tono con una luz superior y un borde apenas
/// insinuado. Evita el patrón «tarjeta con tarjeta dentro».
class ChSurface extends StatelessWidget {
  const ChSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ChSpace.lg),
    this.radius = ChRadius.lg,
    this.color,
    this.gradient,
    this.onTap,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final base = color ?? palette.surface;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: gradient == null ? base : null,
      gradient:
          gradient ??
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color.lerp(base, palette.surfaceHigh, elevated ? 0.55 : 0.32)!,
              base,
            ],
          ),
      border: Border.all(color: palette.border.withValues(alpha: 0.42)),
      boxShadow: elevated
          ? <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: palette.isDark ? 0.38 : 0.10,
                ),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ]
          : null,
    );
    final content = Padding(padding: padding, child: child);
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: content,
        ),
      ),
    );
  }
}

/// Zona tocable que se encoge un 3 % al pulsarla.
///
/// Es el único «efecto» de la app además del resaltado de Material: suficiente
/// para que el dedo sienta la pieza, corto para no estorbar.
class ChPressable extends StatefulWidget {
  const ChPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.radius = ChRadius.md,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final String? semanticLabel;

  @override
  State<ChPressable> createState() => _ChPressableState();
}

class _ChPressableState extends State<ChPressable> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scale = _pressed ? 0.97 : (_hovered && enabled ? 1.012 : 1.0);
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) {
          if (enabled && !reduceMotion && mounted) {
            setState(() => _hovered = true);
          }
        },
        onExit: (_) {
          if (_hovered && mounted) setState(() => _hovered = false);
        },
        child: AnimatedScale(
          scale: scale,
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onHighlightChanged: enabled
                  ? (value) {
                      if (mounted) setState(() => _pressed = value);
                    }
                  : null,
              borderRadius: BorderRadius.circular(widget.radius),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Encabezado de sección: pestaña de acento, título y acción opcional.
class ChSectionHeader extends StatelessWidget {
  const ChSectionHeader(
    this.label, {
    super.key,
    required this.palette,
    this.onAction,
    this.actionLabel = 'Ver todo',
    this.count,
  });

  final String label;
  final CyberHexPalette palette;
  final VoidCallback? onAction;
  final String actionLabel;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: ChSpace.sm + 1),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: chTitle(palette, size: 14.5, letterSpacing: -0.1),
          ),
        ),
        if (count != null) ...<Widget>[
          const SizedBox(width: ChSpace.sm),
          Text(
            count.toString().padLeft(2, '0'),
            style: chMono(palette, size: 10.5, color: palette.border),
          ),
        ],
        const Spacer(),
        if (onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: palette.muted,
              padding: const EdgeInsets.symmetric(horizontal: ChSpace.sm),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel.toUpperCase(),
              style: chMono(
                palette,
                size: 9.5,
                weight: FontWeight.w600,
                color: palette.muted,
                letterSpacing: 1.2,
              ),
            ),
          ),
      ],
    );
  }
}

/// Línea de 1 px para separar sin dibujar cajas.
class ChHairline extends StatelessWidget {
  const ChHairline({
    super.key,
    required this.palette,
    this.indent = 0,
    this.opacity = 0.35,
  });

  final CyberHexPalette palette;
  final double indent;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: EdgeInsets.only(left: indent),
      color: palette.border.withValues(alpha: opacity),
    );
  }
}

/// Icono dentro de un hexágono: el sello de la marca.
class ChHexBadge extends StatelessWidget {
  const ChHexBadge({
    super.key,
    required this.icon,
    required this.palette,
    this.size = 44,
    this.color,
  });

  final IconData icon;
  final CyberHexPalette palette;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? palette.accent;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipPath(
            clipper: const HexClipper(),
            child: ColoredBox(color: tint.withValues(alpha: 0.12)),
          ),
          CustomPaint(
            painter: _HexOutlinePainter(
              color: tint.withValues(alpha: 0.42),
              width: 1.1,
            ),
          ),
          Center(
            child: Icon(icon, size: size * 0.44, color: tint),
          ),
        ],
      ),
    );
  }
}

class _HexOutlinePainter extends CustomPainter {
  const _HexOutlinePainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      hexPath(size, inset: width / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _HexOutlinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.width != width;
}

/// Botón de icono con estado: el acento sólo aparece cuando está encendido.
class ChToggleIcon extends StatelessWidget {
  const ChToggleIcon({
    super.key,
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
    this.size = 21,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 24,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: size,
                color: active ? palette.accent : palette.muted,
              ),
              if (active)
                Positioned(
                  bottom: 6,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón principal de reproducción, con halo del acento.
class ChPlayButton extends StatelessWidget {
  const ChPlayButton({
    super.key,
    required this.playing,
    required this.busy,
    required this.onPressed,
    this.size = 72,
  });

  final bool playing;
  final bool busy;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final enabled = onPressed != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: playing ? 'Pausa' : 'Reproducir',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (enabled)
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: palette.accent.withValues(alpha: 0.26),
                      blurRadius: size * 0.55,
                      spreadRadius: size * 0.04,
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: size,
              height: size,
              child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: palette.accent,
                  foregroundColor: palette.onAccent,
                  disabledBackgroundColor: palette.surfaceHigh,
                  disabledForegroundColor: palette.muted,
                  padding: EdgeInsets.zero,
                ),
                child: busy
                    ? SizedBox(
                        width: size * 0.32,
                        height: size * 0.32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: palette.onAccent,
                        ),
                      )
                    : AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: Tween<double>(begin: 0.72, end: 1).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                ),
                              ),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(playing),
                          size: size * 0.52,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carátula de una pista: bytes reales, o el hexágono generado de la marca.
class ChCoverThumb extends StatelessWidget {
  const ChCoverThumb({
    super.key,
    required this.seed,
    required this.palette,
    this.cover,
    this.size = 48,
    this.radius = ChRadius.sm,
    this.hex = false,
    this.glow = false,
  });

  final String seed;
  final CyberHexPalette palette;
  final Uint8List? cover;
  final double size;
  final double radius;
  final bool hex;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final image = cover;
    Widget art;
    if (image != null && image.isNotEmpty) {
      art = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(
          image,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: (size * 2.4).round(),
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    } else {
      art = hex
          ? HexCover(seed: seed, palette: palette, size: size)
          : _fallback();
    }
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: hex ? null : BorderRadius.circular(radius),
          boxShadow: glow
              ? <BoxShadow>[
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.22),
                    blurRadius: size * 0.35,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: art,
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.lerp(palette.surfaceHigh, palette.accent, 0.16)!,
            palette.surface,
          ],
        ),
      ),
      child: Icon(
        Icons.album_rounded,
        size: size * 0.42,
        color: palette.accent.withValues(alpha: 0.8),
      ),
    );
  }
}

/// Tres barras que respiran mientras suena la pista.
class ChPlayingBars extends StatefulWidget {
  const ChPlayingBars({super.key, required this.color, this.size = 14});

  final Color color;
  final double size;

  @override
  State<ChPlayingBars> createState() => _ChPlayingBarsState();
}

class _ChPlayingBarsState extends State<ChPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (_reduce) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _BarsPainter(
            t: _reduce ? 0.25 : _controller.value,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 3;
    final width = size.width * 0.16;
    final gap = size.width * 0.14;
    final total = bars * width + (bars - 1) * gap;
    final paint = Paint()..color = color;
    for (var i = 0; i < bars; i++) {
      final phase = 2 * math.pi * (t + i * 0.22);
      final level = 0.30 + 0.62 * (0.5 + 0.5 * math.sin(phase));
      final height = size.height * level;
      final left = (size.width - total) / 2 + i * (width + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, size.height - height, width, height),
        Radius.circular(width / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}

/// Estado vacío con el sello hexagonal y una salida clara.
class ChEmptyState extends StatelessWidget {
  const ChEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.palette,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final CyberHexPalette palette;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ChSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ChHexBadge(icon: icon, palette: palette, size: 78),
            const SizedBox(height: ChSpace.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: chTitle(palette, size: 18),
            ),
            const SizedBox(height: ChSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: palette.muted,
                ),
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: ChSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Difumina una imagen de fondo (carátula ambiente del reproductor).
class ChBlurredCover extends StatelessWidget {
  const ChBlurredCover({
    super.key,
    required this.cover,
    this.sigma = 28,
    this.opacity = 0.5,
  });

  final Uint8List cover;
  final double sigma;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: Opacity(
        opacity: opacity,
        child: Image.memory(
          cover,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: 420,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Arrastrar con el ratón también desplaza: en PC las filas horizontales
/// serían inalcanzables con la rueda vertical.
class ChScrollBehavior extends MaterialScrollBehavior {
  const ChScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };
}
