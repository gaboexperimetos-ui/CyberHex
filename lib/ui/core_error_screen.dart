import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'kit/ch_kit.dart';

/// Pantalla que se enseña cuando el motor nativo no se pudo cargar
/// (por ejemplo, si falta `libcyberhex_core.so` o no hay dispositivo de audio).
class CoreErrorScreen extends StatelessWidget {
  const CoreErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ChSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChHexBadge(
                icon: Icons.error_outline_rounded,
                palette: palette,
                size: 84,
                color: palette.error,
              ),
              const SizedBox(height: ChSpace.lg),
              Text(
                'No se pudo iniciar el motor de audio',
                textAlign: TextAlign.center,
                style: chTitle(palette, size: 18),
              ),
              const SizedBox(height: ChSpace.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
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
            ],
          ),
        ),
      ),
    );
  }
}
