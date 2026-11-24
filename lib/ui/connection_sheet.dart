import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../platform/connections.dart';
import '../theme.dart';
import 'kit/ch_kit.dart';

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
      await _showResult(title, result);
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

  /// Resultado de una herramienta de notas: tarjeta y tipografía de la casa en
  /// vez del JSON crudo sobre un diálogo genérico.
  Future<void> _showResult(String title, Object? result) {
    final palette = paletteOf(context);
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: palette.surface,
        insetPadding: const EdgeInsets.all(ChSpace.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChRadius.xl),
          side: BorderSide(color: palette.border.withValues(alpha: 0.6)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(ChSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChHexBadge(
                      icon: Icons.sticky_note_2_rounded,
                      palette: palette,
                      size: 34,
                    ),
                    const SizedBox(width: ChSpace.sm + 2),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: chTitle(palette, size: 15.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ChSpace.md),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _formatResult(result),
                      style: chMono(palette, size: 11.5),
                    ),
                  ),
                ),
                const SizedBox(height: ChSpace.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              const SizedBox(height: ChSpace.lg),
              ChSectionHeader('API de CyberHex', palette: palette),
              const SizedBox(height: ChSpace.sm),
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
              const Divider(height: ChSpace.xl),
              ChSectionHeader('Study Platform', palette: palette),
              const SizedBox(height: ChSpace.sm),
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
                const SizedBox(height: ChSpace.xl),
                ChSectionHeader('Notas', palette: palette),
                const SizedBox(height: ChSpace.sm + 2),
                Text(
                  'Busca en tus notas o guarda la pista que suena con un toque.',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: ChSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _noteQuery,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchNotes(),
                        decoration: const InputDecoration(
                          hintText: 'Buscar en tus notas',
                          prefixIcon: Icon(Icons.search_rounded, size: 19),
                        ),
                      ),
                    ),
                    const SizedBox(width: ChSpace.sm),
                    FilledButton(
                      onPressed: _busy ? null : _searchNotes,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: ChSpace.lg,
                        ),
                      ),
                      child: const Text('Buscar'),
                    ),
                  ],
                ),
                const SizedBox(height: ChSpace.md),
                ChSurface(
                  radius: ChRadius.lg,
                  padding: const EdgeInsets.all(ChSpace.md),
                  onTap: _busy || !widget.controller.snapshot.hasTrack
                      ? null
                      : _saveCurrentTrack,
                  child: Row(
                    children: [
                      ChHexBadge(
                        icon: Icons.note_add_outlined,
                        palette: palette,
                        size: 38,
                      ),
                      const SizedBox(width: ChSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Guardar pista actual',
                              style: chTitle(palette, size: 13.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.controller.snapshot.hasTrack
                                  ? (widget.controller.snapshot.title.isEmpty
                                        ? 'Pista que suena'
                                        : widget.controller.snapshot.title)
                                  : 'Pon algo a sonar para guardarlo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: palette.muted),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
