import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../theme.dart';
import 'design/ch_ambient.dart';
import 'kit/ch_kit.dart';

/// Mini-reproductor flotante de cristal.
///
/// Se apoya encima de la navegación y no ocupa una fila entera: carátula,
/// título y transporte, con el progreso pegado al canto inferior. Tocar el
/// cuerpo abre el reproductor; deslizar a los lados cambia de pista y subir
/// abre el reproductor completo.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.controller,
    required this.onOpen,
    this.bottomPadding = 0,
  });

  final PlayerController controller;

  /// Abre el reproductor completo (el llamador decide la ruta).
  final VoidCallback onOpen;

  /// Espacio inferior extra (área segura de gestos).
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        if (!snapshot.hasTrack) return const SizedBox.shrink();
        final palette = paletteOf(context);
        final title = snapshot.title.isEmpty ? 'Sin título' : snapshot.title;
        final artist = snapshot.artist.trim();
        final cover = snapshot.cover;
        return Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 8 + bottomPadding),
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 220) return;
              if (velocity < 0) {
                controller.next();
              } else {
                controller.previous();
              }
            },
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -320) onOpen();
            },
            child: ChGlass(
              radius: ChRadius.lg,
              padding: EdgeInsets.zero,
              blur: 24,
              onTap: onOpen,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ChRadius.lg),
                child: Stack(
                  children: <Widget>[
                    if (cover != null)
                      Positioned.fill(
                        child: ChBlurredCover(
                          cover: cover,
                          sigma: 30,
                          opacity: 0.42,
                        ),
                      ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              palette.surface.withValues(alpha: 0.42),
                              Color.lerp(
                                palette.surface,
                                palette.accent,
                                0.10,
                              )!.withValues(alpha: 0.55),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                          child: Row(
                            children: <Widget>[
                              ChCoverThumb(
                                seed: title,
                                palette: palette,
                                cover: cover,
                                size: 46,
                                radius: ChRadius.md,
                                hex: cover == null,
                                glow: snapshot.playing,
                              ),
                              const SizedBox(width: ChSpace.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.1,
                                        color: palette.foreground,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      artist.isEmpty ? 'Desconocido' : artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: palette.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ChPlayButton(
                                playing: snapshot.playing,
                                busy: snapshot.busy,
                                onPressed: snapshot.busy
                                    ? null
                                    : () {
                                        chHaptic();
                                        controller.toggle();
                                      },
                                size: 40,
                              ),
                              IconButton(
                                tooltip: 'Siguiente',
                                onPressed: () {
                                  chHaptic();
                                  controller.next();
                                },
                                iconSize: 23,
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.skip_next_rounded,
                                  color: palette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _Progress(
                          value: snapshot.duration > 0
                              ? (controller.position.value / snapshot.duration)
                                    .clamp(0.0, 1.0)
                                    .toDouble()
                              : 0.0,
                          palette: palette,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Línea de progreso pegada al borde inferior: informa sin ocupar una fila.
class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.palette});

  final double value;
  final CyberHexPalette palette;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(ChRadius.lg),
      ),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 2,
        backgroundColor: palette.background.withValues(alpha: 0.35),
        color: palette.accent,
      ),
    );
  }
}
