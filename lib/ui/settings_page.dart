import 'package:material_ui/material_ui.dart';

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../core/backup_service.dart';
import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../core/scrobbler.dart';
import '../core/theme_controller.dart';
import '../platform/connections.dart';
import '../platform/desktop_channel.dart';
import '../theme.dart';
import 'kit/ch_kit.dart';
import 'audio_export_sheet.dart';
import 'connection_sheet.dart';

/// Ajustes de aspecto, gestos y capa Android.
///
/// Todo lo que hay aquí lo aplica [ThemeController] en caliente: no hay botón de
/// guardar porque no hay nada que confirmar (se guarda solo, con antirrebote).
/// La sección «Notificación y auriculares» viaja además a Kotlin con el método
/// `configure` del canal `cyberhex/media`, porque la leen el servicio, el widget
/// y el azulejo rápido sin la app abierta.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.theme,
    this.player,
    this.desktop,
    this.scrobbler,
    this.backup,
    this.connections,
  });

  final ThemeController theme;

  /// Motor, si está disponible: hace falta para elegir la salida de audio.
  final PlayerController? player;

  /// Puente de escritorio (Linux); en el móvil llega `null`.
  final DesktopChannel? desktop;

  /// Scrobbling; si no se inyecta se usa el de la app ([ScrobblerHost]).
  final Scrobbler? scrobbler;

  /// Copia de seguridad; se crea uno si no se inyecta.
  final BackupService? backup;

  /// Conexiones (API local + Study Platform). Si es `null`, Ajustes no muestra
  /// la sección de conexiones.
  final CyberHexConnections? connections;

  /// Estado del interruptor «siempre encima» (el runner no lo reporta).
  static final ValueNotifier<bool> alwaysOnTop = ValueNotifier<bool>(false);

  static String hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final Scrobbler? _scrobbler = widget.scrobbler ?? ScrobblerHost.current;
  // La página nunca crea el Scrobbler: o lo inyecta quien la usa o es el de la
  // app ([ScrobblerHost]), que se destruye con la app. Por eso no lo libera
  // aquí; hacerlo dejaba al resto de la interfaz con un notifier muerto.
  late final BackupService _backup = widget.backup ?? BackupService();
  String? _backupStatus;

  final TextEditingController _listenBrainz = TextEditingController();
  final TextEditingController _lastFmKey = TextEditingController();
  final TextEditingController _lastFmSecret = TextEditingController();
  final TextEditingController _lastFmSession = TextEditingController();
  final TextEditingController _lastFmUser = TextEditingController();

  @override
  void initState() {
    super.initState();
    final scrobbler = _scrobbler;
    if (scrobbler == null) return;
    unawaited(
      scrobbler.load().then((_) {
        if (!mounted) return;
        setState(() => _fillScrobbleFields(scrobbler.settings));
      }),
    );
  }

  void _fillScrobbleFields(ScrobbleSettings settings) {
    _listenBrainz.text = settings.listenBrainzToken;
    _lastFmKey.text = settings.lastFmApiKey;
    _lastFmSecret.text = settings.lastFmApiSecret;
    _lastFmSession.text = settings.lastFmSessionKey;
    _lastFmUser.text = settings.lastFmUsername;
  }

  /// Vuelca los campos al [Scrobbler] (sin tocar `enabled`, que va aparte).
  void _applyScrobbleFields() {
    final scrobbler = _scrobbler;
    if (scrobbler == null) return;
    scrobbler.updateSettings(
      scrobbler.settings.copyWith(
        listenBrainzToken: _listenBrainz.text.trim(),
        lastFmApiKey: _lastFmKey.text.trim(),
        lastFmApiSecret: _lastFmSecret.text.trim(),
        lastFmSessionKey: _lastFmSession.text.trim(),
        lastFmUsername: _lastFmUser.text.trim(),
      ),
    );
  }

  Future<void> _flushScrobbles() async {
    final scrobbler = _scrobbler;
    if (scrobbler == null) return;
    await scrobbler.flush();
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Copia de seguridad
  // ---------------------------------------------------------------------------

  Future<void> _exportBackup() async {
    const group = XTypeGroup(label: 'JSON', extensions: <String>['json']);
    final location = await getSaveLocation(
      suggestedName: _backup.suggestedName(),
      acceptedTypeGroups: const <XTypeGroup>[group],
    );
    if (location == null || !mounted) return;
    try {
      final file = await _backup.exportTo(File(location.path));
      if (!mounted) return;
      setState(() => _backupStatus = 'Copia guardada en ${file.path}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _backupStatus = 'No se pudo guardar: $error');
    }
  }

  Future<void> _importBackup() async {
    const group = XTypeGroup(label: 'JSON', extensions: <String>['json']);
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[group]);
    if (file == null || !mounted) return;
    try {
      final report = await _backup.importFrom(File(file.path));
      if (!mounted) return;
      setState(() => _backupStatus = report.summary);
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _backupStatus = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _backupStatus = 'No se pudo importar: $error');
    }
  }

  @override
  void dispose() {
    _listenBrainz.dispose();
    _lastFmKey.dispose();
    _lastFmSecret.dispose();
    _lastFmSession.dispose();
    _lastFmUser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final listenables = <Listenable>[
      widget.theme,
      if (player != null) player,
      if (_scrobbler != null) _scrobbler!,
    ];
    final listenable = listenables.length == 1
        ? listenables.first
        : Listenable.merge(listenables);
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
                      label: Text(
                        id.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: widget.theme.themeId == id,
                      selectedColor: palette.accent.withValues(alpha: 0.24),
                      backgroundColor: palette.surfaceHigh,
                      side: BorderSide(
                        color: widget.theme.themeId == id
                            ? palette.accent
                            : palette.border,
                      ),
                      onSelected: (_) => widget.theme.setTheme(id),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: widget.theme.dynamicColor,
                onChanged: widget.theme.setDynamicColor,
                title: const Text(
                  'Color dinámico de carátula',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  widget.theme.coverAccent == null
                      ? 'Saca el acento de la carátula de la pista que suena.'
                      : 'Acento sacado de la carátula (${SettingsPage.hex(widget.theme.coverAccent!)}).',
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
                      label: Text(
                        style.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: widget.theme.coverStyle == style,
                      selectedColor: palette.accent.withValues(alpha: 0.24),
                      backgroundColor: palette.surfaceHigh,
                      side: BorderSide(
                        color: widget.theme.coverStyle == style
                            ? palette.accent
                            : palette.border,
                      ),
                      onSelected: (_) => widget.theme.setCoverStyle(style),
                    ),
                ],
              ),
              const _Section('Gestos y pantalla'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: widget.theme.pocketMode,
                onChanged: widget.theme.setPocketMode,
                title: const Text(
                  'Modo bolsillo',
                  style: TextStyle(fontSize: 14),
                ),
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
                  value: widget.theme.shows(action),
                  onChanged: (_) => widget.theme.toggleAction(action),
                  title: Text(
                    action.label,
                    style: const TextStyle(fontSize: 14),
                  ),
                  secondary: Icon(action.icon, size: 20, color: palette.muted),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
              const SizedBox(height: 6),
              Text(
                widget.theme.actions.isEmpty
                    ? 'Con todo desmarcado, la barra rápida desaparece.'
                    : 'La barra rápida del reproductor muestra ${widget.theme.actions.length} '
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
                          onSelected: (_) =>
                              player.setOutputDevice(device.index),
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
              if (widget.desktop != null) ...[
                ValueListenableBuilder<bool>(
                  valueListenable: SettingsPage.alwaysOnTop,
                  builder: (context, onTop, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: onTop,
                    onChanged: (value) {
                      SettingsPage.alwaysOnTop.value = value;
                      widget.desktop!.setAlwaysOnTop(value);
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
                  leading: Icon(
                    Icons.notifications_active_outlined,
                    size: 20,
                    color: palette.muted,
                  ),
                  title: const Text(
                    'Notificar la pista nueva',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    'Manda una notificación de escritorio ahora mismo '
                    '(GNotification).',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                  onTap: () => widget.desktop!.notifyTrack(
                    title: player?.snapshot.title ?? 'CyberHex',
                    body: player?.snapshot.artist,
                  ),
                ),
              ],
              const _Section('Notificación y auriculares'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: widget.theme.autoPlayOnConnect,
                onChanged: widget.theme.setAutoPlayOnConnect,
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
                  value:
                      action == MediaAction.toggle ||
                      widget.theme.mediaActions.contains(action),
                  onChanged: action == MediaAction.toggle
                      ? null
                      : (_) => widget.theme.toggleMediaAction(action),
                  title: Text(
                    action.label,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: action == MediaAction.toggle
                      ? Text(
                          'Siempre presente.',
                          style: TextStyle(fontSize: 11, color: palette.muted),
                        )
                      : null,
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
              if (player != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: palette.muted,
                  ),
                  title: const Text(
                    'Exportar la pista actual',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    'Elige un rango y renderiza WAV con el DSP puesto.',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                  onTap: () =>
                      unawaited(AudioExportSheet.show(context, player)),
                ),
              const _Section('Copia de seguridad'),
              Text(
                'Un solo .json con favoritos, listas, colas, estadísticas, '
                'emisoras, tema, scrobbling y presets de EQ.',
                style: TextStyle(
                  fontSize: 11,
                  color: palette.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _exportBackup,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Exportar copia'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importBackup,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Restaurar copia'),
                  ),
                ],
              ),
              if (_backupStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _backupStatus!,
                    style: TextStyle(fontSize: 11, color: palette.accent),
                  ),
                ),
              const _Section('Scrobbling'),
              if (_scrobbler == null)
                Text(
                  'Scrobbling no disponible (el motor no está montado).',
                  style: TextStyle(fontSize: 12, color: palette.muted),
                )
              else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _scrobbler!.settings.enabled,
                  onChanged: (value) => _scrobbler!.updateSettings(
                    _scrobbler!.settings.copyWith(enabled: value),
                  ),
                  title: const Text(
                    'Enviar escuchas',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    'Cuenta si suena más de la mitad o más de cuatro minutos. '
                    'Se guardan y se reintentan si no hay red.',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                ),
                TextField(
                  controller: _listenBrainz,
                  obscureText: true,
                  onChanged: (_) => _applyScrobbleFields(),
                  decoration: const InputDecoration(
                    labelText: 'ListenBrainz: token de usuario',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastFmKey,
                  onChanged: (_) => _applyScrobbleFields(),
                  decoration: const InputDecoration(
                    labelText: 'Last.fm: API key',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastFmSecret,
                  obscureText: true,
                  onChanged: (_) => _applyScrobbleFields(),
                  decoration: const InputDecoration(
                    labelText: 'Last.fm: shared secret',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastFmSession,
                  obscureText: true,
                  onChanged: (_) => _applyScrobbleFields(),
                  decoration: const InputDecoration(
                    labelText: 'Last.fm: session key',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastFmUser,
                  onChanged: (_) => _applyScrobbleFields(),
                  decoration: const InputDecoration(
                    labelText: 'Last.fm: usuario (opcional)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_scrobbler!.pending.length} pendiente(s) · '
                        '${_scrobbler!.submitted} enviada(s)'
                        '${_scrobbler!.lastError == null ? '' : ' · ${_scrobbler!.lastError}'}',
                        style: TextStyle(fontSize: 11, color: palette.muted),
                      ),
                    ),
                    TextButton(
                      onPressed: _scrobbler!.isSending
                          ? null
                          : () => unawaited(_flushScrobbles()),
                      child: const Text('Enviar ahora'),
                    ),
                  ],
                ),
              ],
              if (widget.connections != null && player != null) ...[
                const _Section('Conexiones'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    Icons.hub_outlined,
                    size: 20,
                    color: palette.muted,
                  ),
                  title: const Text(
                    'API local y Study Platform',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    widget.connections!.localApiUrl == null
                        ? (widget.connections!.localApiError ??
                              'Iniciando API local…')
                        : 'API local en ${widget.connections!.localApiUrl}',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConnectionSheet(
                        connections: widget.connections!,
                        controller: player!,
                      ),
                    ),
                  ),
                ),
              ],
              const _Section('Acerca de'),
              Text(
                'CyberHex · motor propio (Zig + C23) · Flutter\n'
                'Sin dependencias externas de audio, imagen ni red.',
                style: TextStyle(
                  fontSize: 12,
                  color: palette.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
      child: ChSectionHeader(text.toUpperCase(), palette: paletteOf(context)),
    );
  }
}
