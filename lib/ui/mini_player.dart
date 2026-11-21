import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../theme.dart';

/// Mini-reproductor flotante: una barra con carátula, título y transporte que
/// se queda abajo en la biblioteca y en las listas.
///
/// No duplica estado: escucha al controlador y dibuja lo que hay. Tocar el
/// cuerpo abre el reproductor; los botones hacen play/pausa y siguiente sin
/// salir de la pantalla.
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
    final palette = paletteOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        if (!snapshot.hasTrack) return const SizedBox.shrink();
        final progress = snapshot.duration > 0
            ? (controller.position.value / snapshot.duration).clamp(0.0, 1.0).toDouble()
            : 0.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 8 + bottomPadding),
          child: Material(
            color: palette.surface,
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.border.withValues(alpha: 0.7)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        backgroundColor: palette.surfaceHigh,
                        color: palette.accent,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                      child: Row(
                        children: [
                          _thumb(snapshot.cover, palette),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  snapshot.title.isEmpty ? 'Sin título' : snapshot.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: palette.foreground,
                                  ),
                                ),
                                if (snapshot.artist.isNotEmpty)
                                  Text(
                                    snapshot.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: palette.muted),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Anterior',
                            onPressed: controller.previous,
                            icon: Icon(Icons.skip_previous_rounded, color: palette.foreground),
                          ),
                          IconButton(
                            tooltip: snapshot.playing ? 'Pausa' : 'Reproducir',
                            onPressed: snapshot.busy ? null : controller.toggle,
                            icon: Icon(
                              snapshot.playing
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              size: 32,
                              color: palette.accent,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Siguiente',
                            onPressed: controller.next,
                            icon: Icon(Icons.skip_next_rounded, color: palette.foreground),
                          ),
                        ],
                      ),
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

  Widget _thumb(Uint8List? cover, CyberHexPalette palette) {
    final image = cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 42,
        height: 42,
        child: image == null
            ? ColoredBox(
                color: palette.surfaceHigh,
                child: Icon(Icons.graphic_eq_rounded, color: palette.accent, size: 20),
              )
            : Image.memory(
                image,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: 96,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: palette.surfaceHigh,
                  child: Icon(Icons.graphic_eq_rounded, color: palette.accent, size: 20),
                ),
              ),
      ),
    );
  }
}
