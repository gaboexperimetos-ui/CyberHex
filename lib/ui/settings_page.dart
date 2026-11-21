import 'package:material_ui/material_ui.dart';

import '../core/theme_controller.dart';
import '../theme.dart';

/// Ajustes de aspecto y gestos.
///
/// Todo lo que hay aquí lo aplica [ThemeController] en caliente: no hay botón de
/// guardar porque no hay nada que confirmar (se guarda solo, con antirrebote).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: theme,
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
