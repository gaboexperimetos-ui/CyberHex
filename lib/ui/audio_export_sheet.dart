import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../theme.dart';
import 'kit/ch_kit.dart';

/// Qué se está exportando.
enum ExportKind {
  master('Pista masterizada', 'trozo completo, con tu DSP'),
  ringtone('Tono de llamada', 'máximo 30 s, con tu DSP');

  const ExportKind(this.label, this.hint);

  final String label;
  final String hint;
}

/// Exportador de audio: elige **rango**, **formato** (WAV 16/24, WAV float 32
/// o AIFF) y renderiza con el DSP que tenga puesto el motor: EQ, 9D y ancho
/// estéreo incluidos.
class AudioExportSheet extends StatefulWidget {
  const AudioExportSheet({super.key, required this.controller});

  final PlayerController controller;

  /// Abre la hoja como `modalBottomSheet` desplazable.
  static Future<void> show(BuildContext context, PlayerController controller) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AudioExportSheet(controller: controller),
    );
  }

  @override
  State<AudioExportSheet> createState() => _AudioExportSheetState();
}

class _AudioExportSheetState extends State<AudioExportSheet> {
  static const double maxRingtoneSeconds = 30;

  ExportKind _kind = ExportKind.master;
  ExportFormat _format = ExportFormat.wav16;
  bool _withDsp = true;
  double _start = 0;
  double _end = 0;
  bool _initialized = false;
  bool _working = false;
  String? _status;

  PlayerController get _controller => widget.controller;

  String get _title {
    final snapshot = _controller.snapshot;
    return snapshot.hasTrack ? snapshot.title : 'Sin pista';
  }

  String get _sourcePath {
    final snapshot = _controller.snapshot;
    final index = snapshot.queueIndex;
    if (index < 0 || index >= snapshot.queue.length) return '';
    return snapshot.queue[index].path;
  }

  double get _length {
    final value = _end - _start;
    return value > 0 ? value : 0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final snapshot = _controller.snapshot;
    final duration = snapshot.duration > 0 ? snapshot.duration : 0.0;
    if (!_initialized && duration > 0) {
      _initialized = true;
      _start = 0;
      _end = duration;
    }

    final hasTrack = _sourcePath.isNotEmpty && duration > 0;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChSheetHeader(
              icon: Icons.save_alt_rounded,
              title: 'Exportar audio',
              palette: palette,
              subtitle: hasTrack
                  ? _title
                  : 'Abre una pista para exportar un trozo.',
            ),
            const SizedBox(height: ChSpace.lg),
            if (hasTrack) ...[
              RangeSlider(
                values: RangeValues(
                  _start.clamp(0.0, duration).toDouble(),
                  _end.clamp(0.0, duration).toDouble(),
                ),
                max: duration,
                divisions: duration >= 2 ? duration.floor() : null,
                labels: RangeLabels(_clock(_start), _clock(_end)),
                onChanged: (values) => setState(() {
                  _start = values.start;
                  _end = _clampEnd(values.end);
                }),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Inicio ${_clock(_start)}',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                  Text(
                    'Duración ${_clock(_length)}',
                    style: TextStyle(fontSize: 11, color: palette.accent),
                  ),
                  Text(
                    'Fin ${_clock(_end)}',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final kind in ExportKind.values)
                    ChoiceChip(
                      label: Text(
                        kind.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _kind == kind
                              ? palette.onAccent
                              : palette.foreground,
                        ),
                      ),
                      selected: _kind == kind,
                      selectedColor: palette.accent,
                      backgroundColor: palette.surfaceHigh,
                      side: BorderSide(
                        color: _kind == kind ? palette.accent : palette.border,
                      ),
                      onSelected: (_) {
                        chHaptic();
                        setState(() {
                          _kind = kind;
                          _end = _clampEnd(_end);
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: ChSpace.md),
              Text('Formato', style: chTitle(palette, size: 13.5)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final format in ExportFormat.values)
                    ChoiceChip(
                      label: Text(
                        format.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _format == format
                              ? palette.onAccent
                              : palette.foreground,
                        ),
                      ),
                      selected: _format == format,
                      selectedColor: palette.accent,
                      backgroundColor: palette.surfaceHigh,
                      side: BorderSide(
                        color: _format == format
                            ? palette.accent
                            : palette.border,
                      ),
                      onSelected: (_) {
                        chHaptic();
                        setState(() => _format = format);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${_kind.hint}. ${_format.label} · 48 kHz estéreo.',
                style: TextStyle(fontSize: 11, color: palette.muted),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _withDsp,
                onChanged: (value) => setState(() => _withDsp = value),
                title: Text(
                  'Aplicar EQ, 9D y ancho estéreo',
                  style: chTitle(palette, size: 13.5),
                ),
                subtitle: Text(
                  _withDsp
                      ? 'Se renderiza con el DSP del motor, tal como suena.'
                      : 'Se renderiza plano (solo ReplayGain y limitador).',
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                style: TextStyle(fontSize: 12, color: palette.accent),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: hasTrack && !_working ? _export : null,
              icon: _working
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt_rounded, size: 18),
              label: Text(_working ? 'Exportando…' : 'Exportar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Un tono de llamada nunca pasa de 30 s.
  double _clampEnd(double value) {
    if (_kind == ExportKind.ringtone) {
      final maxEnd = (_start + maxRingtoneSeconds).toDouble();
      return value > maxEnd ? maxEnd : value;
    }
    return value;
  }

  Future<void> _export() async {
    final source = _sourcePath;
    if (source.isEmpty) {
      setState(() => _status = 'No hay ninguna pista abierta.');
      return;
    }
    final start = _start.clamp(0.0, double.infinity).toDouble();
    var end = _end;
    if (_kind == ExportKind.ringtone && end - start > maxRingtoneSeconds) {
      end = start + maxRingtoneSeconds;
    }

    final suggested = _suggestedName(source);
    final group = XTypeGroup(
      label: _format.label,
      extensions: <String>[_format.extension],
    );
    final location = await getSaveLocation(
      suggestedName: suggested,
      acceptedTypeGroups: <XTypeGroup>[group],
    );
    if (location == null || !mounted) return;

    setState(() {
      _working = true;
      _status =
          'Renderizando ${_clock(end - start)} en ${_format.label} con '
          '${_withDsp ? 'DSP' : 'sin DSP'}…';
    });

    final ok = await _controller.renderWav(
      source,
      location.path,
      start: start,
      end: end,
      withDsp: _withDsp,
      format: _format,
    );
    if (!mounted) return;
    setState(() {
      _working = false;
      _status = ok
          ? 'Listo: ${location.path}'
          : (_controller.snapshot.error ?? 'No se pudo exportar.');
    });
    if (ok) {
      // El archivo existe: se confirma también con un aviso del sistema.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exportado a ${location.path}')));
    }
  }

  String _suggestedName(String source) {
    final base = File(source).uri.pathSegments.isEmpty
        ? 'pista'
        : File(source).uri.pathSegments.last
              .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '');
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final ext = _format.extension;
    if (_kind == ExportKind.ringtone) {
      return 'tono-${safe.isEmpty ? 'cyberhex' : safe}.$ext';
    }
    return '${safe.isEmpty ? 'cyberhex' : safe}-master.$ext';
  }

  static String _clock(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.floor() : 0;
    final tenths = (((seconds.isFinite ? seconds : 0) - total) * 10).round();
    final minutes = total ~/ 60;
    final rest = (total % 60).toString().padLeft(2, '0');
    return '${minutes.toString().padLeft(2, '0')}:$rest.${tenths.abs()}';
  }
}
