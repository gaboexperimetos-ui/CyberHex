import 'package:material_ui/material_ui.dart';

import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../core/theme_controller.dart';
import '../platform/desktop_channel.dart';
import '../theme.dart';

/// Ajustes de aspecto, gestos y capa Android.
///
/// Todo lo que hay aquí lo aplica [ThemeController] en caliente: no hay botón de
/// guardar porque no hay nada que confirmar (se guarda solo, con antirrebote).
/// La sección «Notificación y auriculares» viaja además a Kotlin con el método
/// `configure` del canal `cyberhex/media`, porque la leen el servicio, el widget
/// y el azulejo rápido sin la app abierta.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.theme, this.player, this.desktop});

  final ThemeController theme;

  /// Motor, si está disponible: hace falta para elegir la salida de audio.
  final PlayerController? player;

  /// Puente de escritorio (Linux); en el móvil llega `null`.
  final DesktopChannel? desktop;

  @override
  Widget build(BuildContext context) {
    final player = this.player;
    final listenable = player == null
        ? theme
        : Listenable.merge(<Listenable>[theme, player]);
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final palette = paletteOf(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Ajustes')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              const _Section('Tema'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in CyberHexThemeId.values)
                    ChoiceChip(
                      label: Text(id.label, style: const TextStyle(fontSize: 12)),
                      selected: theme.themeId == id,
                      selectedColor: palette.accent.withValues(alpha: 0.24),
                      backgroundColor: palette.surfaceHigh,
                      side: BorderSide(
                        color: theme.themeId == id ? palette.accent : palette.border,
                      ),
                      onSelected: (_) => theme.setTheme(id),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: theme.dynamicColor,
                onChanged: theme.setDynamicColor,
                title: const Text(
                  'Color dinámico de carátula',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  theme.coverAccent == null
                      ? 'Saca el acento de la carátula de la pista que suena.'
                      : 'Acento sacado de la carátula (${_hex(theme.coverAccent!)}).',
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ),
              const _Section('Carátula'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final style in CoverStyle.values)
                    ChoiceChip(
                      label: Text(style.label, style: const TextStyle(fontSize: 12)),
                      selected: theme.coverStyle == style,
                      selectedColor: palette.accent.withValues(alpha: 0.24),
                      backgroundColor: palette.surfaceHigh,
                      side: BorderSide(
                        color: theme.coverStyle == style ? palette.accent : palette.border,
                      ),
                      onSelected: (_) => theme.setCoverStyle(style),
                    ),
                ],
              ),
              const _Section('Gestos y pantalla'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: theme.pocketMode,
                onChanged: theme.setPocketMode,
                title: const Text('Modo bolsillo', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  'Bloquea los toques del reproductor; se sale manteniendo pulsado.',
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ),
              const _Section('Barra de acciones'),
              for (final action in PlayerAction.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: theme.shows(action),
                  onChanged: (_) => theme.toggleAction(action),
                  title: Text(action.label, style: const TextStyle(fontSize: 14)),
                  secondary: Icon(action.icon, size: 20, color: palette.muted),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
              const SizedBox(height: 6),
              Text(
                theme.actions.isEmpty
                    ? 'Con todo desmarcado, la barra rápida desaparece.'
                    : 'La barra rápida del reproductor muestra ${theme.actions.length} '
                        'de ${PlayerAction.values.length} botones.',
                style: TextStyle(fontSize: 11, color: palette.muted),
              ),
              const _Section('Salida de audio y escritorio'),
              if (player == null)
                Text(
                  'Sin motor: no hay dispositivos que listar.',
                  style: TextStyle(fontSize: 12, color: palette.muted),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Dispositivo de salida',
                    style: TextStyle(fontSize: 12, color: palette.foreground),
                  ),
                ),
                if (player.outputDevices.isEmpty)
                  Text(
                    'El motor no reporta dispositivos (usa el del sistema).',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final device in player.outputDevices)
                        ChoiceChip(
                          label: Text(
                            device.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: device.index == player.outputDevice,
                          selectedColor: palette.accent.withValues(alpha: 0.24),
                          backgroundColor: palette.surfaceHigh,
                          side: BorderSide(
                            color: device.index == player.outputDevice
                                ? palette.accent
                                : palette.border,
                          ),
                          onSelected: (_) => player.setOutputDevice(device.index),
                        ),
                    ],
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: player.snapshot.s16Output,
                  onChanged: player.setS16Output,
                  title: const Text(
                    'Salida S16 con dither TPDF',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    'Entrega 16 bits con dither en vez de f32: para DACs y '
                    'equipos que no aceptan flotante.',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                ),
              ],
              if (desktop != null) ...[
                ValueListenableBuilder<bool>(
                  valueListenable: _alwaysOnTop,
                  builder: (context, onTop, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: onTop,
                    onChanged: (value) {
                      _alwaysOnTop.value = value;
                      desktop!.setAlwaysOnTop(value);
                    },
                    title: const Text(
                      'Ventana siempre encima',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      'Solo Linux: la ventana queda por delante del resto.',
                      style: TextStyle(fontSize: 11, color: palette.muted),
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.notifications_active_outlined,
                      size: 20, color: palette.muted),
                  title: const Text(
                    'Notificar la pista nueva',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    'Manda una notificación de escritorio ahora mismo '
                    '(GNotification).',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                  onTap: () => desktop!.notifyTrack(
                    title: player?.snapshot.title ?? 'CyberHex',
                    body: player?.snapshot.artist,
                  ),
                ),
              ],
              const _Section('Notificación y auriculares'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: theme.autoPlayOnConnect,
                onChanged: theme.setAutoPlayOnConnect,
                title: const Text(
                  'Auto-play al conectar',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  'Si había una pista en pausa, arranca al enchufar auriculares '
                  'o conectar Bluetooth (Android).',
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ),
              for (final action in MediaAction.values)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: action == MediaAction.toggle ||
                      theme.mediaActions.contains(action),
                  onChanged: action == MediaAction.toggle
                      ? null
                      : (_) => theme.toggleMediaAction(action),
                  title: Text(action.label, style: const TextStyle(fontSize: 14)),
                  subtitle: action == MediaAction.toggle
                      ? Text(
                          'Siempre presente.',
                          style: TextStyle(fontSize: 11, color: palette.muted),
                        )
                      : null,
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
              const _Section('Acerca de'),
              Text(
                'CyberHex · motor propio (Zig + C23) · Flutter\n'
                'Sin dependencias externas de audio, imagen ni red.',
                style: TextStyle(fontSize: 12, color: palette.muted, height: 1.5),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Estado del interruptor «siempre encima». Vive en la página porque el
  /// runner no lo reporta de vuelta; al reabrir Ajustes vuelve a apagado.
  static final ValueNotifier<bool> _alwaysOnTop = ValueNotifier<bool>(false);

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w600,
          color: paletteOf(context).muted,
        ),
      ),
    );
  }
}
