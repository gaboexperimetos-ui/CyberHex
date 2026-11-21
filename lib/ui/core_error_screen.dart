import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Pantalla que se enseña cuando el motor nativo no se pudo cargar
/// (por ejemplo, si falta `libcyberhex_core.so` o no hay dispositivo de audio).
class CoreErrorScreen extends StatelessWidget {
  const CoreErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: chError, size: 40),
              const SizedBox(height: 16),
              const Text(
                'No se pudo iniciar el motor de audio',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: chMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
