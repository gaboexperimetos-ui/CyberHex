import 'dart:async';
import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';

import 'core/native_player.dart';
import 'core/player_controller.dart';
import 'platform/connections.dart';
import 'platform/media_session_channel.dart';
import 'platform/playback_session.dart';
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

class _CyberHexAppState extends State<CyberHexApp> with WidgetsBindingObserver {
  PlayerController? _controller;
  MediaSessionChannel? _mediaSession;
  CyberHexConnections? _connections;
  PlaybackSessionPersistence? _session;
  bool _ownsController = false;
  bool _restoringSession = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final injected = widget.controller;
    if (injected != null) {
      _controller = injected..start();
      _attachMediaSession(injected);
      return;
    }
    final player = NativePlayer.open();
    if (player == null) {
      _error = NativePlayer.lastCoreError();
      return;
    }
    _ownsController = true;
    final controller = PlayerController(player);
    _controller = controller;
    final session = PlaybackSessionPersistence(controller);
    _session = session;
    _restoringSession = true;
    unawaited(_startPlayerServices(controller, session));
  }

  Future<void> _startPlayerServices(
    PlayerController controller,
    PlaybackSessionPersistence session,
  ) async {
    await session.initialize();
    if (!mounted) return;
    controller.start();
    _attachMediaSession(controller);
    final connections = CyberHexConnections();
    _connections = connections;
    unawaited(connections.initialize(controller));
    setState(() => _restoringSession = false);
  }

  /// Solo en Android: el servicio de medios pinta la notificación y reenvía
  /// los botones de la pantalla de bloqueo al controlador.
  void _attachMediaSession(PlayerController controller) {
    if (!Platform.isAndroid) return;
    _mediaSession = MediaSessionChannel(controller);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final session = _session;
      if (session != null) unawaited(session.saveNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // El puente primero: suelta listeners antes de que el controlador muera.
    _mediaSession?.dispose();
    _mediaSession = null;
    _connections?.dispose();
    _connections = null;
    _session?.dispose();
    _session = null;
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
          : _restoringSession
          ? const _SessionStartupScreen()
          : PlayerPage(
              controller: controller,
              connections: _connections,
              session: _session,
            ),
    );
  }
}

class _SessionStartupScreen extends StatelessWidget {
  const _SessionStartupScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Restaurando tu sesión…'),
        ],
      ),
    ),
  );
}
