import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/player_api.dart';
import '../core/player_controller.dart';

/// Puente de escritorio (Linux) por el canal `cyberhex/desktop`.
///
/// El runner de GTK publica `org.mpris.MediaPlayer2.cyberhex` en D-Bus; este
/// lado:
///  * **manda** `updateMetadata` / `updateState` para que MPRIS (y con él las
///    teclas multimedia del teclado, `playerctl`, los widgets de KDE/GNOME y el
///    Bluetooth del coche) sepa qué suena y en qué estado;
///  * **recibe** `play`, `pause`, `toggle`, `stop`, `next`, `previous`, `seek`,
///    `seekRelative`, `setVolume`, `setLoop` y `setShuffle`, ya traducidos por
///    C++ a nombres de método;
///  * **recibe** `onDropPaths` cuando sueltas archivos o carpetas sobre la
///    ventana (Flutter no trae DnD de archivos: lo capta GTK);
///  * **ofrece** `setAlwaysOnTop`, `notifyTrack` (GNotification) y `notifySeek`.
///
/// Fuera de Linux (o en tests sin handler) todo lanza `MissingPluginException`,
/// que aquí se ignora: la app sigue funcionando igual.
class DesktopChannel {
  DesktopChannel(this._controller, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handlePlatformCall);
    _controller.addListener(_onControllerChanged);
    _controller.position.addListener(_onPositionChanged);
    // Primer volcado: al arrancar, MPRIS necesita saber qué hay en cola.
    _publishMetadata(force: true);
    _publishState(force: true);
  }

  /// Nombre del canal; `my_application.cc` usa el mismo literal.
  static const String channelName = 'cyberhex/desktop';

  final PlayerController _controller;
  final MethodChannel _channel;

  final StreamController<List<String>> _drops =
      StreamController<List<String>>.broadcast();

  bool _disposed = false;

  // Metadatos ya enviados.
  bool _metadataSent = false;
  String? _lastTitle;
  String? _lastArtist;
  String? _lastAlbum;
  int? _lastDurationUs;

  // Estado ya enviado (posición limitada a 1 Hz, como en Android).
  bool? _lastPlaying;
  int? _lastSecond;
  int? _lastLoop;
  bool? _lastShuffle;
  double? _lastVolume;

  /// Rutas soltadas sobre la ventana (archivos o carpetas).
  Stream<List<String>> get drops => _drops.stream;

  /// ¿Estamos en un escritorio Linux con el runner extendido?
  static bool get isSupported {
    try {
      return Platform.isLinux;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Dart → nativo
  // ---------------------------------------------------------------------------

  /// Ventana siempre encima (`gtk_window_set_keep_above`).
  Future<void> setAlwaysOnTop(bool enabled) =>
      _invoke('setAlwaysOnTop', enabled);

  /// Notificación de escritorio con la pista que empieza.
  Future<void> notifyTrack({required String title, String? body}) =>
      _invoke('notifyTrack', <String, Object?>{
        'title': title,
        'body': body,
      });

  /// Avisa de un salto para que MPRIS emita `Seeked`.
  Future<void> notifySeek(double seconds) =>
      _invoke('notifySeek', <String, Object?>{
        'positionMicros': _micros(seconds),
      });

  void _onControllerChanged() {
    _publishMetadata();
    _publishState();
  }

  void _onPositionChanged() => _publishState();

  void _publishMetadata({bool force = false}) {
    final snapshot = _controller.snapshot;
    final durationUs = _micros(snapshot.duration);
    final changed = force ||
        !_metadataSent ||
        snapshot.title != _lastTitle ||
        snapshot.artist != _lastArtist ||
        snapshot.album != _lastAlbum ||
        durationUs != _lastDurationUs;
    if (!changed) return;

    _metadataSent = true;
    _lastTitle = snapshot.title;
    _lastArtist = snapshot.artist;
    _lastAlbum = snapshot.album;
    _lastDurationUs = durationUs;

    _send('updateMetadata', <String, Object?>{
      'title': snapshot.title,
      'artist': snapshot.artist,
      'album': snapshot.album,
      'durationMicros': durationUs,
      'hasTrack': snapshot.hasTrack,
    });
  }

  void _publishState({bool force = false}) {
    final snapshot = _controller.snapshot;
    final positionUs = _micros(_controller.position.value);
    final second = positionUs ~/ 1000000;
    final loop = _loopName(snapshot.repeatMode);

    final changed = force ||
        snapshot.playing != _lastPlaying ||
        second != _lastSecond ||
        snapshot.repeatMode != _lastLoop ||
        snapshot.shuffle != _lastShuffle ||
        snapshot.volume != _lastVolume;
    if (!changed) return;

    _lastPlaying = snapshot.playing;
    _lastSecond = second;
    _lastLoop = snapshot.repeatMode;
    _lastShuffle = snapshot.shuffle;
    _lastVolume = snapshot.volume;

    _send('updateState', <String, Object?>{
      'playing': snapshot.playing,
      'positionMicros': positionUs,
      'durationMicros': _micros(snapshot.duration),
      'loop': loop,
      'shuffle': snapshot.shuffle,
      'volume': snapshot.volume,
    });
  }

  /// `org.mpris.MediaPlayer2.Player.LoopStatus`.
  static String _loopName(int repeatMode) {
    switch (repeatMode) {
      case 1:
        return 'Playlist';
      case 2:
        return 'Track';
      default:
        return 'None';
    }
  }

  static int _micros(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return 0;
    return (seconds * 1000000).round();
  }

  void _send(String method, Object? arguments) {
    if (_disposed) return;
    unawaited(_invoke(method, arguments));
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      // Windows, macOS, tests o un runner viejo: no es un error.
    } on PlatformException catch (error) {
      debugPrint('DesktopChannel: $method falló (${error.code})');
    }
  }

  // ---------------------------------------------------------------------------
  // Nativo → Dart
  // ---------------------------------------------------------------------------

  Future<Object?> _handlePlatformCall(MethodCall call) async {
    if (_disposed) return false;
    switch (call.method) {
      case 'play':
        _controller.play();
        return true;
      case 'pause':
        _controller.pause();
        return true;
      case 'toggle':
        _controller.toggle();
        return true;
      case 'next':
        _controller.next();
        return true;
      case 'previous':
        _controller.previous();
        return true;
      case 'stop':
        _controller.pause();
        _controller.seek(0);
        return true;
      case 'seek':
        final seconds = (call.arguments as num?)?.toDouble();
        if (seconds != null) _controller.seek(_clampSeek(seconds));
        return true;
      case 'seekRelative':
        final delta = (call.arguments as num?)?.toDouble();
        if (delta != null) {
          _controller.seek(_clampSeek(_controller.position.value + delta));
        }
        return true;
      case 'setVolume':
        final value = (call.arguments as num?)?.toDouble();
        if (value != null) {
          _controller.setVolume(value.clamp(0.0, 1.0).toDouble());
        }
        return true;
      case 'setLoop':
        final name = call.arguments is String ? call.arguments as String : '';
        switch (name.toLowerCase()) {
          case 'playlist':
            _controller.setRepeatMode(1);
          case 'track':
            _controller.setRepeatMode(2);
          case 'none':
            _controller.setRepeatMode(0);
        }
        return true;
      case 'setShuffle':
        _controller.setShuffle(call.arguments == true);
        return true;
      case 'onDropPaths':
        final raw = call.arguments;
        final paths = <String>[
          if (raw is List)
            for (final item in raw)
              if (item is String && item.isNotEmpty) item,
        ];
        if (paths.isNotEmpty && !_drops.isClosed) _drops.add(paths);
        return true;
      default:
        return false;
    }
  }

  double _clampSeek(double seconds) {
    final duration = _controller.snapshot.duration;
    if (seconds <= 0) return 0;
    if (duration <= 0) return seconds;
    return seconds.clamp(0.0, duration).toDouble();
  }

  /// Suelta listeners y cierra el flujo de drop. No toca la reproducción.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_onControllerChanged);
    _controller.position.removeListener(_onPositionChanged);
    _channel.setMethodCallHandler(null);
    unawaited(_drops.close());
  }
}
