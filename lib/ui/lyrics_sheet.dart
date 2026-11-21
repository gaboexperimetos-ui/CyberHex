import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../theme.dart';

/// Letra sincronizada (.lrc) con la línea que corresponde a la posición.
///
/// Se refresca con la posición, no con cada cambio del motor: la línea cambia
/// mientras suena la pista. El núcleo busca un `.lrc` con el mismo nombre que
/// el audio.
class LyricsSheet extends StatelessWidget {
  const LyricsSheet({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.5;
    return SizedBox(
      height: height,
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, controller.position]),
        builder: (context, _) {
          final hasLyrics = controller.lyricsCount > 0;
          final line = controller.activeLyricLine;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Letra', style: chDisplay.copyWith(fontSize: 20)),
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: hasLyrics
                        ? Text(
                            line.isEmpty ? '♪' : line,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : const Text(
                            'No hay letra para esta pista.\n'
                            'Guarda un .lrc junto al audio con el mismo nombre.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: chMuted, height: 1.6),
                          ),
                  ),
                ),
                if (hasLyrics)
                  Text(
                    '${controller.lyricsCount} líneas · LRC',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: chMuted, fontSize: 11),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
