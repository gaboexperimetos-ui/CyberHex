import 'dart:async';
import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';

import 'core/native_player.dart';
import 'core/player_controller.dart';
import 'platform/external_file_channel.dart';
import 'platform/media_session_channel.dart';
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
  MediaSessionChannel? _mediaSession;
  ExternalFileChannel? _externalFiles;
  bool _ownsController = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final injected = widget.controller;
    if (injected != null) {
      _controller = injected..start();
      _attachPlatformChannels(injected);
      return;
    }
    final player = NativePlayer.open();
    if (player == null) {
      _error = NativePlayer.lastCoreError();
      return;
    }
    _ownsController = true;
    final controller = PlayerController(player)..start();
    _controller = controller;
    _attachPlatformChannels(controller);
  }

  void _attachPlatformChannels(PlayerController controller) {
    _attachMediaSession(controller);
    _attachExternalFiles(controller);
  }

  /// Solo en Android: el servicio de medios pinta la notificación y reenvía
  /// los botones de la pantalla de bloqueo al controlador.
  void _attachMediaSession(PlayerController controller) {
    if (!Platform.isAndroid) return;
    _mediaSession = MediaSessionChannel(controller);
  }

  /// Archivos abiertos desde el sistema (explorador, WhatsApp...). En Android
  /// llegan por `ACTION_VIEW`; en escritorio el canal no existe y `start()`
  /// solo recibe `MissingPluginException`, que se ignora.
  void _attachExternalFiles(PlayerController controller) {
    final channel = ExternalFileChannel(controller);
    _externalFiles = channel;
    // Sin await: la UI no espera a que llegue un archivo.
    unawaited(channel.start());
  }

  @override
  void dispose() {
    // Los puentes primero: sueltan listeners antes de que el controlador muera.
    _externalFiles?.dispose();
    _externalFiles = null;
    _mediaSession?.dispose();
    _mediaSession = null;
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
