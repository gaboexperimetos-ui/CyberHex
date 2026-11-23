import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/player_api.dart';
import '../core/player_controller.dart';

/// Puente entre [PlayerController] y el servicio de medios de Android
/// (`MediaSessionService`, Kotlin) a través del canal `cyberhex/media`.
///
/// Dos direcciones:
///  * **Dart → Kotlin**: `updateMetadata` cuando cambia la pista o sus
///    etiquetas/carátula, `updateState` cuando cambia play/pausa/buffering o
///    cambia el **segundo entero** de la posición (throttle de 1 s: la posición
///    va a 12,5 Hz y no tiene sentido cruzar el canal a ese ritmo) y
///    `configure` cuando el usuario cambia el auto-play al conectar o los
///    botones de la notificación (el lado Kotlin los guarda en
///    `SharedPreferences` porque también los leen el widget y el azulejo).
///  * **Kotlin → Dart**: `play`, `pause`, `toggle`, `next`, `previous`, `seek`
///    (segundos), `setVolume` (0..1) y `duck` (bool).
///
/// El ducking es *relativo*: al entrar se guarda el volumen del usuario y se
/// baja a [duckFactor] de ese valor; al salir se restaura **exactamente** el
/// guardado, no un 1.0 a ciegas.
///
/// En escritorio (o en tests sin handler) cualquier llamada lanza
/// `MissingPluginException`; aquí se ignora en silencio.
class MediaSessionChannel {
  MediaSessionChannel(this._controller, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handlePlatformCall);
    _controller.addListener(_onControllerChanged);
    _controller.position.addListener(_onPositionChanged);
    // Primer volcado: al abrir la app el servicio necesita saber qué suena.
    _publishMetadata(force: true);
    _publishState(force: true);
  }

  /// Nombre del canal; el lado Kotlin usa la misma constante.
  static const String channelName = 'cyberhex/media';

  /// Fracción del volumen del usuario que se aplica al hacer ducking (~25 %).
  static const double duckFactor = 0.25;

  final PlayerController _controller;
  final MethodChannel _channel;

  bool _disposed = false;

  // Metadatos ya enviados (para no repetir el mapa ni la carátula).
  bool _metadataSent = false;
  String? _lastTitle;
  String? _lastArtist;
  String? _lastAlbum;
  int? _lastDurationMs;
  Uint8List? _lastArt;

  // Estado ya enviado (throttle por segundo entero).
  bool? _lastPlaying;
  int? _lastSecond;
  int? _lastStateDurationMs;
  bool? _lastBuffering;

  // Volumen: el del usuario y el que había antes de duckear.
  double _userVolume = 1;
  double? _volumeBeforeDuck;

  /// ¿Hay ducking aplicado ahora mismo?
  bool get ducked => _volumeBeforeDuck != null;

  /// Último volumen pedido por el usuario (el que se restaura al salir del duck).
  double get userVolume => _userVolume;

  // ---------------------------------------------------------------------------
  // Dart → Kotlin
  // ---------------------------------------------------------------------------

  void _onControllerChanged() {
    _publishMetadata();
    _publishState();
  }

  void _onPositionChanged() => _publishState();

  void _publishMetadata({bool force = false}) {
    final snapshot = _controller.snapshot;
    final durationMs = _milliseconds(snapshot.duration);
    final changed = force ||
        !_metadataSent ||
        snapshot.title != _lastTitle ||
        snapshot.artist != _lastArtist ||
        snapshot.album != _lastAlbum ||
        durationMs != _lastDurationMs ||
        !identical(snapshot.cover, _lastArt);
    if (!changed) return;

    _metadataSent = true;
    _lastTitle = snapshot.title;
    _lastArtist = snapshot.artist;
    _lastAlbum = snapshot.album;
    _lastDurationMs = durationMs;
    _lastArt = snapshot.cover;

    _send('updateMetadata', <String, Object?>{
      'title': snapshot.title,
      'artist': snapshot.artist,
      'album': snapshot.album,
      'durationMs': durationMs,
      'art': snapshot.cover,
    });
  }

  void _publishState({bool force = false}) {
    final snapshot = _controller.snapshot;
    final positionMs = _milliseconds(_controller.position.value);
    final second = positionMs ~/ 1000;
    final durationMs = _milliseconds(snapshot.duration);
    final playing = snapshot.playing;
    final buffering = snapshot.busy;

    final changed = force ||
        playing != _lastPlaying ||
        second != _lastSecond ||
        durationMs != _lastStateDurationMs ||
        buffering != _lastBuffering;
    if (!changed) return;

    _lastPlaying = playing;
    _lastSecond = second;
    _lastStateDurationMs = durationMs;
    _lastBuffering = buffering;

    _send('updateState', <String, Object?>{
      'playing': playing,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'buffering': buffering,
    });
  }

  /// Manda los ajustes que la capa Android usa sin la app abierta.
  ///
  /// Idempotente: repetirlo con los mismos valores no molesta (Kotlin solo
  /// repinta si cambió algo).
  void updateMediaSettings({
    required bool autoPlayOnConnect,
    required Iterable<String> notificationActions,
  }) {
    _send('configure', <String, Object?>{
      'autoPlayOnConnect': autoPlayOnConnect,
      'notificationActions': notificationActions.toList(growable: false),
    });
  }

  /// Dispara sin esperar: el servicio nunca debe bloquear la UI.
  void _send(String method, [Object? arguments]) {
    if (_disposed) return;
    unawaited(_invoke(method, arguments));
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      // Escritorio, tests o servicio aún no arrancado: no es un error.
    } on PlatformException catch (error) {
      debugPrint('MediaSessionChannel: $method falló (${error.code})');
    }
  }

  // ---------------------------------------------------------------------------
  // Kotlin → Dart
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
      case 'seek':
        final seconds = (call.arguments as num?)?.toDouble();
        if (seconds != null) _controller.seek(_clampSeek(seconds));
        return true;
      case 'setVolume':
        final value = (call.arguments as num?)?.toDouble();
        if (value != null) _setUserVolume(value);
        return true;
      case 'duck':
        _setDucked(call.arguments == true);
        return true;
      default:
        // El servicio puede preguntar por métodos de versiones futuras.
        return false;
    }
  }

  /// No deja pedir un seek fuera de la pista actual.
  double _clampSeek(double seconds) {
    final duration = _controller.snapshot.duration;
    final max = duration > 0 ? duration : seconds;
    return seconds.clamp(0.0, max).toDouble();
  }

  void _setUserVolume(double value) {
    _userVolume = value.clamp(0.0, 1.0).toDouble();
    if (_volumeBeforeDuck != null) {
      // Sigue duckeado: se mueve el volumen de usuario, no el efectivo.
      _volumeBeforeDuck = _userVolume;
      _controller.setVolume(_userVolume * duckFactor);
    } else {
      _controller.setVolume(_userVolume);
    }
  }

  void _setDucked(bool duck) {
    if (duck) {
      if (_volumeBeforeDuck != null) return; // ya está duckeado
      final current = _controller.snapshot.volume;
      _userVolume = current;
      _volumeBeforeDuck = current;
      _controller.setVolume(current * duckFactor);
    } else {
      final saved = _volumeBeforeDuck;
      if (saved == null) return;
      _volumeBeforeDuck = null;
      _controller.setVolume(saved);
    }
  }

  static int _milliseconds(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return 0;
    return (seconds * 1000).round();
  }

  /// Suelta listeners y, si había ducking, devuelve el volumen del usuario.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_onControllerChanged);
    _controller.position.removeListener(_onPositionChanged);
    _channel.setMethodCallHandler(null);

    final saved = _volumeBeforeDuck;
    _volumeBeforeDuck = null;
    if (saved != null) {
      _controller.setVolume(saved);
    }
  }
}
