import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../platform/connections.dart';
import '../theme.dart';

class ConnectionSheet extends StatefulWidget {
  const ConnectionSheet({
    super.key,
    required this.connections,
    required this.controller,
  });

  final CyberHexConnections connections;
  final PlayerController controller;

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  final TextEditingController _noteQuery = TextEditingController();
  bool _busy = false;
  bool _showLocalKey = false;
  bool _edited = false;
  String? _message;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.connections.studyMcpUrl);
    _key = TextEditingController(text: widget.connections.studyMcpKey);
    widget.connections.addListener(_syncConfig);
    _syncConfig();
  }

  @override
  void dispose() {
    widget.connections.removeListener(_syncConfig);
    _url.dispose();
    _key.dispose();
    _noteQuery.dispose();
    super.dispose();
  }

  void _syncConfig() {
    final connections = widget.connections;
    if (_edited || !connections.initialized) return;
    _url.text = connections.studyMcpUrl;
    _key.text = connections.studyMcpKey;
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.connections.saveStudyPlatform(
        url: _url.text,
        apiKey: _key.text,
      );
      if (!mounted) return;
      setState(() {
        _success = true;
        _message = 'Conexión guardada de forma segura.';
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = error.message;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = 'No se pudieron guardar los datos: $error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    await _save();
    if (!mounted || !_success) return;
    setState(() {
      _busy = true;
      _message = 'Probando el servidor MCP...';
    });
    try {
      await widget.connections.testStudyPlatform();
      if (!mounted) return;
      setState(() {
        _success = true;
        _message = 'Conectado: Study Platform respondió correctamente.';
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = 'No se pudo conectar: $error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLocalKey(String? key) async {
    if (key == null || key.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: key));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Clave local copiada.')));
  }

  Future<void> _searchNotes() async {
    final query = _noteQuery.text.trim();
    if (query.isEmpty) return;
    await _runNoteTool(
      name: 'search_notes',
      arguments: {'query': query},
      title: 'Resultados de notas',
    );
  }

  Future<void> _saveCurrentTrack() async {
    final snapshot = widget.controller.snapshot;
    if (!snapshot.hasTrack) return;
    final details = [
      if (snapshot.artist.isNotEmpty) 'Artista: ${snapshot.artist}',
      if (snapshot.album.isNotEmpty) 'Álbum: ${snapshot.album}',
      'Guardado desde CyberHex.',
    ].join('\n');
    await _runNoteTool(
      name: 'create_note',
      arguments: {
        'title': snapshot.title.isEmpty ? 'Pista reproducida' : snapshot.title,
        'content': details,
        'tags': const ['CyberHex', 'música'],
      },
      title: 'Nota creada',
    );
  }

  Future<void> _runNoteTool({
    required String name,
    required Map<String, Object?> arguments,
    required String title,
  }) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.connections.callStudyTool(
        name,
        arguments: arguments,
      );
      if (!mounted) return;
      setState(() {
        _success = true;
        _message = '$title en Study Platform.';
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(_formatResult(result)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _success = false;
        _message = 'Error de Study Platform: $error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatResult(Object? value) {
    if (value is String) return value;
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: ListenableBuilder(
        listenable: widget.connections,
        builder: (context, _) {
          final connections = widget.connections;
          final palette = paletteOf(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Text(
                'Conexiones',
                style: chDisplay.copyWith(
                  fontSize: 20,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enlace local y autenticado entre el reproductor y Study Platform.',
                style: TextStyle(color: palette.muted, height: 1.5),
              ),
              const SizedBox(height: 20),
              Text(
                'API de CyberHex',
                style: chDisplay.copyWith(
                  fontSize: 16,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                connections.localApiError ??
                    'Solo escucha en este equipo: ${connections.localApiUrl ?? 'iniciando…'}',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextFormField(
                readOnly: true,
                obscureText: !_showLocalKey,
                initialValue: connections.localApiKey ?? '',
                decoration: InputDecoration(
                  labelText: 'Clave para Study Platform',
                  suffixIcon: IconButton(
                    tooltip: _showLocalKey ? 'Ocultar clave' : 'Mostrar clave',
                    onPressed: () =>
                        setState(() => _showLocalKey = !_showLocalKey),
                    icon: Icon(
                      _showLocalKey
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _copyLocalKey(connections.localApiKey),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copiar clave'),
                ),
              ),
              const Divider(height: 28),
              Text(
                'Study Platform',
                style: chDisplay.copyWith(
                  fontSize: 16,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Introduce su endpoint MCP y la CUSTOM_MCP_API_KEY configurada en el servidor.',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                onChanged: (_) => _edited = true,
                decoration: const InputDecoration(
                  labelText: 'Endpoint MCP',
                  hintText: 'http://127.0.0.1:8090/mcp',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _key,
                obscureText: true,
                onChanged: (_) => _edited = true,
                decoration: const InputDecoration(
                  labelText: 'API key de Study Platform',
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _success ? palette.accent : palette.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('Guardar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _test,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Probar conexión'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'La clave se guarda en el almacenamiento seguro del dispositivo. '
                'No compartas la clave de CyberHex: da acceso local a la reproducción y la cola.',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
              if (connections.studyConfigured) ...[
                const Divider(height: 32),
                Text(
                  'Notas',
                  style: chDisplay.copyWith(
                    fontSize: 16,
                    color: palette.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteQuery,
                  decoration: const InputDecoration(
                    labelText: 'Buscar en tus notas',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (_) => _searchNotes(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _searchNotes,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Buscar notas'),
                ),
                FilledButton.icon(
                  onPressed: _busy || !widget.controller.snapshot.hasTrack
                      ? null
                      : _saveCurrentTrack,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Guardar pista actual como nota'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
