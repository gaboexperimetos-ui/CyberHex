import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../core/theme_controller.dart';
import '../platform/connections.dart';
import '../platform/desktop_channel.dart';
import 'player_page.dart';

/// Abre el reproductor a pantalla completa deslizando desde abajo.
///
/// La base de la app mantiene un mini-reproductor en cada pestaña; al tocarlo
/// (o al deslizarlo hacia arriba) esta es la transición que lo expande. Se
/// centraliza aquí para que todas las pestañas abran exactamente lo mismo y con
/// el tema compartido.
Future<void> openNowPlaying(
  BuildContext context, {
  required PlayerController controller,
  required ThemeController theme,
  DesktopChannel? desktop,
  CyberHexConnections? connections,
}) {
  // Sin animaciones si el sistema las desactiva: la ruta sigue siendo la
  // misma, pero aparece de golpe en vez de deslizarse.
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final enter = reduceMotion
      ? Duration.zero
      : const Duration(milliseconds: 320);
  final exit = reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: enter,
      reverseTransitionDuration: exit,
      pageBuilder: (_, __, ___) => PlayerPage(
        controller: controller,
        theme: theme,
        desktop: desktop,
        connections: connections,
      ),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    ),
  );
}
