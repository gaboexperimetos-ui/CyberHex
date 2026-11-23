import 'dart:async';
import 'dart:io' show Platform;

import 'package:material_ui/material_ui.dart';

import 'core/native_player.dart';
import 'core/player_controller.dart';
import 'core/scrobbler.dart';
import 'core/session_store.dart';
import 'core/theme_controller.dart';
import 'platform/connections.dart';
import 'platform/external_file_channel.dart';
import 'platform/desktop_channel.dart';
import 'platform/media_session_channel.dart';
import 'theme.dart';
import 'ui/core_error_screen.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  // El canal `cyberhex/storage` (filesDir) es asíncrono y el resto de la app
  // construye sus almacenes con constructores síncronos: se resuelve aquí, una
  // sola vez, antes de montar la UI (R14).
  WidgetsFlutterBinding.ensureInitialized();
  await StorageDirectory.prepare();
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
  DesktopChannel? _desktop;
  Scrobbler? _scrobbler;
  CyberHexConnections? _connections;
  SessionKeeper? _session;
  late final ThemeController _theme = ThemeController();
  bool _ownsController = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Los ajustes visuales mandan sobre el `MaterialApp` entero: se cargan sin
    // bloquear (arranca con el tema neón y se repinta al leer el JSON).
    unawaited(_theme.load());
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
    _attachSession(controller);
    _attachConnections(controller);
  }

  /// API local (HTTP/MCP autenticada) y conexión con Study Platform. Se arranca
  /// sola; si el almacenamiento seguro o el puerto fallan queda inerte y la
  /// sección de Ajustes explica el motivo.
  void _attachConnections(PlayerController controller) {
    if (!_ownsController) return;
    final connections = CyberHexConnections();
    _connections = connections;
    unawaited(
      connections.initialize(controller).catchError((Object error) {
        // Sin plugin de llavero o sin red: no rompe el arranque.
      }),
    );
  }

  /// Restaura la sesión anterior en segundo plano. Solo en producción: en las
  /// pruebas de widget el controlador llega inyectado y no se toca el disco.
  ///
  /// [SessionKeeper] usa el [SessionStore] por defecto, que ya apunta al
  /// directorio de datos resuelto en `main()` (filesDir en Android,
  /// `~/.local/share/cyberhex` en Linux).
  void _attachSession(PlayerController controller) {
    if (!_ownsController) return;
    final keeper = SessionKeeper(controller: controller);
    _session = keeper;
    // Sin await: la app arranca con la pantalla ya montada y la cola aparece
    // cuando termina de leer el archivo.
    unawaited(keeper.restore());
  }

  void _attachPlatformChannels(PlayerController controller) {
    _attachMediaSession(controller);
    _attachExternalFiles(controller);
    _attachDesktop(controller);
    _attachScrobbler(controller);
  }

  /// Scrobbling de toda la app (ListenBrainz y Last.fm). Se crea una vez y se
  /// expone por [ScrobblerHost] para que Ajustes lo configure sin recibirlo por
  /// constructor. Sin token no manda nada, así que no molesta.
  void _attachScrobbler(PlayerController controller) {
    final scrobbler = Scrobbler(controller);
    _scrobbler = scrobbler;
    ScrobblerHost.attach(scrobbler);
    // Al cargar los ajustes se reintenta lo que quedara pendiente.
    unawaited(scrobbler.load().then((_) => scrobbler.flush()));
  }

  /// Solo en Linux: MPRIS2, siempre encima, notificaciones de escritorio y el
  /// drag & drop que captura GTK. En Windows/macOS el canal no existe y el
  /// puente se queda mudo (todo `MissingPluginException`, ignorado).
  void _attachDesktop(PlayerController controller) {
    if (!DesktopChannel.isSupported) return;
    _desktop = DesktopChannel(controller);
  }

  /// Solo en Android: el servicio de medios pinta la notificación y reenvía
  /// los botones de la pantalla de bloqueo al controlador.
  void _attachMediaSession(PlayerController controller) {
    if (!Platform.isAndroid) return;
    final channel = MediaSessionChannel(controller);
    _mediaSession = channel;
    // Los ajustes que Android lee sin la app abierta (auto-play al conectar y
    // botones de la notificación) se empujan al arrancar y en cada cambio.
    _theme.addListener(_pushMediaSettings);
    _pushMediaSettings();
  }

  void _pushMediaSettings() {
    final channel = _mediaSession;
    if (channel == null) return;
    channel.updateMediaSettings(
      autoPlayOnConnect: _theme.autoPlayOnConnect,
      notificationActions: <String>[
        for (final action in _theme.mediaActions) action.name,
      ],
    );
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
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.dispose());
    _externalFiles?.dispose();
    _externalFiles = null;
    _theme.removeListener(_pushMediaSettings);
    _mediaSession?.dispose();
    _mediaSession = null;
    _desktop?.dispose();
    _desktop = null;
    ScrobblerHost.attach(null);
    _scrobbler?.dispose();
    _scrobbler = null;
    _connections?.dispose();
    _connections = null;
    if (_ownsController) {
      _controller?.dispose();
    }
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AnimatedBuilder(
      animation: _theme,
      builder: (context, _) => MaterialApp(
        title: 'CyberHex',
        debugShowCheckedModeBanner: false,
        theme: _theme.themeData,
        home: controller == null
            ? CoreErrorScreen(message: _error ?? 'no se pudo iniciar el motor')
            : HomeShell(
                controller: controller,
                theme: _theme,
                desktop: _desktop,
                connections: _connections,
              ),
      ),
    );
  }
}
