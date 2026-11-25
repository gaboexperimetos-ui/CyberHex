import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../theme.dart';
import '../hex_grid.dart';
import '../kit/ch_kit.dart';

/// Fondo atmosférico de la app.
///
/// Namida construye cada pantalla sobre un papel pintado que cambia con la
/// carátula; aquí se hace lo mismo con el acento del tema: un degradado base,
/// dos halos de color y una viñeta que hunde los bordes. La rejilla hexagonal
/// queda muy por debajo del contenido para dar textura sin competir.
///
/// Es estático a propósito: un fondo que respira obliga a repintar la pantalla
/// entera y no aporta información. El movimiento se reserva para el contenido.
class ChAmbient extends StatelessWidget {
  const ChAmbient({
    super.key,
    required this.palette,
    required this.child,
    this.grid = true,
    this.intensity = 1,
  });

  final CyberHexPalette palette;
  final Widget child;
  final bool grid;

  /// 0 = fondo plano, 1 = halos a plena potencia.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final dark = palette.isDark;
    final glow = (dark ? 0.30 : 0.16) * intensity;
    final secondaryGlow = (dark ? 0.18 : 0.10) * intensity;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: palette.background),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.lerp(palette.background, palette.primary, 0.42)!,
                palette.background,
                Color.lerp(palette.background, palette.secondary, 0.10)!,
              ],
              stops: const <double>[0, 0.46, 1],
            ),
          ),
        ),
        // Halo del acento arriba a la izquierda: el foco de luz de la portada.
        Positioned(
          left: -220,
          top: -260,
          width: 720,
          height: 720,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: <Color>[
                    palette.accent.withValues(alpha: glow),
                    palette.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Segundo halo, del color secundario, abajo a la derecha.
        Positioned(
          right: -260,
          bottom: -320,
          width: 780,
          height: 780,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: <Color>[
                    palette.secondary.withValues(alpha: secondaryGlow),
                    palette.secondary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (grid) HexGridBackground(palette: palette),
        // Viñeta: oscurece los bordes para que el contenido flote.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.15,
                colors: <Color>[
                  Colors.transparent,
                  palette.background.withValues(alpha: dark ? 0.55 : 0.18),
                ],
                stops: const <double>[0.55, 1],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Panel de cristal: desenfoca lo que hay detrás y lo tiñe con la superficie.
///
/// Se usa para el mini-reproductor y para las piezas que deben leerse como
/// «encima» del fondo (hero, rail). El borde superior claro simula el canto de
/// una lámina de vidrio; el resto es sombra, no una caja gris.
class ChGlass extends StatelessWidget {
  const ChGlass({
    super.key,
    required this.child,
    this.radius = ChRadius.lg,
    this.padding = EdgeInsets.zero,
    this.blur = 18,
    this.tint,
    this.onTap,
    this.borderOpacity = 0.5,
    this.elevated = true,
    this.clip = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final Color? tint;
  final VoidCallback? onTap;
  final double borderOpacity;
  final bool elevated;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final base = tint ?? palette.surface;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color.lerp(base, palette.surfaceHigh, 0.55)!.withValues(alpha: 0.88),
          base.withValues(alpha: 0.78),
          Color.lerp(base, palette.primary, 0.25)!.withValues(alpha: 0.82),
        ],
      ),
      border: Border.all(
        color: palette.foreground.withValues(alpha: 0.07 * borderOpacity * 2),
      ),
      boxShadow: elevated
          ? <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: palette.isDark ? 0.34 : 0.08,
                ),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ]
          : null,
    );
    final content = Padding(padding: padding, child: child);
    final glass = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(decoration: decoration, child: content),
      ),
    );
    if (onTap == null) return glass;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: glass,
      ),
    );
  }
}

/// Cabecera editorial: ceja, titular grande y línea de contexto.
///
/// Es el patrón de Namida para abrir una pantalla: una etiqueta pequeña en
/// mayúsculas, un titular que ocupa el ancho y una línea de datos en
/// monoespaciada. Nada de barras de aplicación con el título centrado.
class ChEditorialHeader extends StatelessWidget {
  const ChEditorialHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.palette,
    this.subtitle,
    this.trailing,
    this.titleSize = 34,
    this.gradientTitle = true,
  });

  final String eyebrow;
  final String title;
  final CyberHexPalette palette;
  final String? subtitle;
  final Widget? trailing;
  final double titleSize;
  final bool gradientTitle;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Righteous',
      fontSize: titleSize,
      letterSpacing: 0.2,
      height: 1.02,
      color: palette.foreground,
    );
    Widget heading = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (gradientTitle) {
      heading = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (Rect bounds) => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            palette.foreground,
            Color.lerp(palette.foreground, palette.accent, 0.55)!,
            palette.accent,
          ],
          stops: const <double>[0, 0.62, 1],
        ).createShader(bounds),
        child: heading,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(width: 18, height: 2, color: palette.accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      eyebrow.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: chEyebrow(
                        palette,
                        size: 9.5,
                        color: palette.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              heading,
              if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: chMono(palette, size: 10.5),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: ChSpace.md),
          trailing!,
        ],
      ],
    );
  }
}
