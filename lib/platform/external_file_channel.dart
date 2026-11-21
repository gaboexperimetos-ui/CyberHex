import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/player_controller.dart';

/// Puente del canal `cyberhex/intent`: abre audios que llegan desde fuera de la
/// app (tocar un archivo en el explorador, "Compartir con…" de WhatsApp, un
/// enlace `content://` o `file://`).
///
/// El lado Kotlin hace el trabajo sucio —un `content://` no es una ruta POSIX,
/// así que copia el flujo a `cacheDir/shared_audio/`— y aquí solo se carga y se
/// reproduce.
///
/// Dos caminos, porque hay una carrera real entre el `Intent` y el arranque de
/// Dart:
///  * [start] pregunta una vez con `getInitialFile` (el archivo con el que se
///    abrió la app, si lo hubo);
///  * el manejador recibe `onOpenFile` si la app ya estaba abierta.
///
/// En escritorio y en tests no hay nadie al otro lado: `MissingPluginException`
/// se ignora y todo queda en silencio.
class ExternalFileChannel {
  ExternalFileChannel(this._controller, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  /// Nombre del canal; el lado Kotlin usa la misma constante.
  static const String channelName = 'cyberhex/intent';

  final PlayerController _controller;
  final MethodChannel _channel;

  bool _disposed = false;

  /// ¿Se pidió ya el archivo inicial? Evita repetir la llamada al recrear.
  bool _started = false;

  /// Pregunta por el archivo con el que se abrió la app y, si lo hay, lo pone a
  /// sonar. Es idempotente y nunca lanza.
  Future<void> start() async {
    if (_disposed || _started) return;
    _started = true;
    final initial = await _getInitialFile();
    if (initial != null && initial.isNotEmpty) {
      await _open(initial);
    }
  }

  Future<String?> _getInitialFile() async {
    try {
      return await _channel.invokeMethod<String>('getInitialFile');
    } on MissingPluginException {
      // Escritorio o tests: no hay actividad al otro lado.
      return null;
    } on PlatformException catch (error) {
      debugPrint('ExternalFileChannel: getInitialFile falló (${error.code})');
      return null;
    }
  }

  Future<Object?> _handlePlatformCall(MethodCall call) async {
    if (_disposed) return false;
    if (call.method != 'onOpenFile') return false;

    final path = call.arguments;
    if (path is String && path.isNotEmpty) {
      await _open(path);
    }
    return true;
  }

  /// Carga la pista y la reproduce. Si el motor no pudo abrirla, no se toca el
  /// transporte (no tiene sentido darle a play a un archivo que falló).
  Future<void> _open(String path) async {
    final error = await _controller.openFile(path);
    if (_disposed || error != null) {
      if (error != null) {
        debugPrint('ExternalFileChannel: no pude abrir $path ($error)');
      }
      return;
    }
    _controller.play();
  }

  /// Suelta el manejador del canal. No cierra la pista que esté sonando.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}
