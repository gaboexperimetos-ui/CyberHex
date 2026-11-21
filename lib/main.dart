import 'package:material_ui/material_ui.dart';

import 'core/native_player.dart';
import 'core/player_controller.dart';
import 'theme.dart';
import 'ui/core_error_screen.dart';
import 'ui/player_page.dart';

void main() {
  runApp(const CyberHexApp());
}

class CyberHexApp extends StatefulWidget {
  const CyberHexApp({super.key, this.controller});

  /// Controlador ya construido. Solo lo usan las pruebas de widget: en
  /// producción se crea aquí a partir del motor nativo.
  final PlayerController? controller;

  @override
  State<CyberHexApp> createState() => _CyberHexAppState();
}

class _CyberHexAppState extends State<CyberHexApp> {
  PlayerController? _controller;
  bool _ownsController = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final injected = widget.controller;
    if (injected != null) {
      _controller = injected..start();
      return;
    }
    final player = NativePlayer.open();
    if (player == null) {
      _error = NativePlayer.lastCoreError();
      return;
    }
    _ownsController = true;
    _controller = PlayerController(player)..start();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return MaterialApp(
      title: 'CyberHex',
      debugShowCheckedModeBanner: false,
      theme: buildCyberHexTheme(),
      home: controller == null
          ? CoreErrorScreen(message: _error ?? 'no se pudo iniciar el motor')
          : PlayerPage(controller: controller),
    );
  }
}
