import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../theme.dart';
import 'kit/ch_kit.dart';

/// Mini-reproductor flotante: una barra con carátula, título y transporte que
/// se queda abajo en la biblioteca y en las listas.
///
/// No duplica estado: escucha al controlador y dibuja lo que hay. Tocar el
/// cuerpo abre el reproductor; el botón hace play/pausa, y deslizar a los lados
/// cambia de pista sin salir de la pantalla.
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
        return Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 6 + bottomPadding),
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
              // Como en Namida: se sube para abrir el reproductor.
              if ((details.primaryVelocity ?? 0) < -320) onOpen();
            },
            child: Material(
              color: palette.surface,
              elevation: 6,
              borderRadius: BorderRadius.circular(ChRadius.lg),
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(ChRadius.lg),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ChRadius.lg),
                    border: Border.all(
                      color: palette.border.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
                        child: Row(
                          children: <Widget>[
                            ChCoverThumb(
                              seed: title,
                              palette: palette,
                              cover: snapshot.cover,
                              size: 42,
                              radius: ChRadius.sm,
                              hex: snapshot.cover == null,
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
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                      color: palette.foreground,
                                    ),
                                  ),
                                  if (artist.isNotEmpty)
                                    Text(
                                      artist,
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
                              size: 38,
                            ),
                            IconButton(
                              tooltip: 'Siguiente',
                              onPressed: () {
                                chHaptic();
                                controller.next();
                              },
                              iconSize: 22,
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
        backgroundColor: palette.surfaceHigh,
        color: palette.accent,
      ),
    );
  }
}
