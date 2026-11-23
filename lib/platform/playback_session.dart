import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/player_controller.dart';

class PlaybackSessionPersistence extends ChangeNotifier {
  PlaybackSessionPersistence(
    this._controller, {
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const _fileName = 'playback-session.chstate';
  static const _saveInterval = Duration(seconds: 10);
  static const _changeDebounce = Duration(milliseconds: 500);

  final PlayerController _controller;
  final Future<Directory> Function() _supportDirectoryProvider;

  File? _stateFile;
  Timer? _timer;
  Timer? _debounce;
  bool _ready = false;
  bool _saving = false;
  bool _disposed = false;
  bool _restored = false;
  String _status = 'Preparando el guardado automático…';

  bool get restored => _restored;
  String get status => _status;

  Future<void> initialize() async {
    try {
      final directory = await _supportDirectoryProvider();
      if (_disposed) return;
      await directory.create(recursive: true);
      if (_disposed) return;
      _stateFile = File('${directory.path}${Platform.pathSeparator}$_fileName');
      if (await _stateFile!.exists()) {
        if (_disposed) return;
        final position = _controller.loadState(_stateFile!.path);
        if (position == null) {
          _status = 'No se pudo restaurar la sesión anterior.';
        } else {
          _restored = true;
          _status =
              'Sesión anterior restaurada; la reproducción queda pausada.';
        }
      } else {
        _status = 'La sesión se guardará automáticamente en este dispositivo.';
      }

      _ready = true;
      _controller.addListener(_scheduleSave);
      _timer = Timer.periodic(_saveInterval, (_) => unawaited(saveNow()));
    } on FileSystemException catch (error) {
      _status = 'No se pudo acceder al archivo de sesión: ${error.message}';
    } on Exception catch (error) {
      _status = 'No se pudo preparar la sesión: $error';
    }
    if (!_disposed) notifyListeners();
  }

  void _scheduleSave() {
    if (!_ready || _disposed) return;
    _debounce?.cancel();
    _debounce = Timer(_changeDebounce, () => unawaited(saveNow()));
  }

  Future<void> saveNow() async {
    final file = _stateFile;
    if (!_ready || file == null || _saving || _disposed) return;
    if (_controller.snapshot.busy) return;
    _saving = true;
    try {
      if (_controller.queueCount == 0) {
        if (await file.exists()) await file.delete();
        _status = 'No hay una cola para restaurar.';
      } else if (!_controller.saveState(file.path)) {
        throw FileSystemException('El motor rechazó el guardado.', file.path);
      } else {
        _status = 'Sesión guardada automáticamente.';
      }
    } on FileSystemException catch (error) {
      _status = 'No se pudo guardar la sesión: ${error.message}';
    } on Exception catch (error) {
      _status = 'No se pudo guardar la sesión: $error';
    } finally {
      _saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    if (!_saving) unawaited(saveNow());
    _disposed = true;
    _timer?.cancel();
    _debounce?.cancel();
    _controller.removeListener(_scheduleSave);
    super.dispose();
  }
}
