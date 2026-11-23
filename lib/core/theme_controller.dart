import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'session_store.dart';

/// Acciones que pueden vivir en la barra rápida del reproductor.
enum PlayerAction {
  lyrics('Letras', Icons.lyrics_rounded),
  tags('Etiquetas', Icons.sell_rounded),
  share('Compartir', Icons.ios_share_rounded),
  lab('Laboratorio', Icons.tune_rounded);

  const PlayerAction(this.label, this.icon);

  final String label;
  final IconData icon;

  static PlayerAction? fromName(String? name) {
    for (final action in PlayerAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }
}

/// Acciones que pueden ir en la notificación de Android.
///
/// `toggle` está siempre: una notificación de reproducción sin play/pausa no
/// sirve, así que [ThemeController.toggleMediaAction] no deja quitarla.
enum MediaAction {
  previous('Anterior'),
  toggle('Reproducir / pausa'),
  next('Siguiente'),
  stop('Cerrar');

  const MediaAction(this.label);

  final String label;

  static MediaAction? fromName(String? name) {
    for (final action in MediaAction.values) {
      if (action.name == name) return action;
    }
    return null;
  }
}

/// Ajustes de la app: tema, color dinámico, estilo de carátula, modo bolsillo,
/// barra rápida y lo que la capa Android hace sin abrir la app (auto-play al
/// conectar auriculares y botones de la notificación).
///
/// Se guardan en `theme.json` (mismo patrón que la sesión: `.tmp` + `rename`) y
/// se avisa a quien escuche con [ChangeNotifier]: `main.dart` reconstruye el
/// `MaterialApp` entero cuando cambia el tema.
class ThemeController extends ChangeNotifier {
  ThemeController({File? file})
      : file = file ?? File('${StorageDirectory.current.path}/theme.json');

  ThemeController.memory() : file = null;

  static const int formatVersion = 1;

  final File? file;

  CyberHexThemeId _themeId = CyberHexThemeId.neon;
  bool _dynamicColor = false;
  bool _pocketMode = false;
  CoverStyle _coverStyle = CoverStyle.spinningDisc;
  final Set<PlayerAction> _actions = <PlayerAction>{...PlayerAction.values};

  bool _autoPlayOnConnect = false;
  final Set<MediaAction> _mediaActions = <MediaAction>{
    MediaAction.previous,
    MediaAction.toggle,
    MediaAction.next,
  };

  /// Acento sacado de la carátula (solo si [dynamicColor]).
  Color? _coverAccent;
  String _coverFingerprint = '';

  bool _loaded = false;
  bool _dirty = false;
  Timer? _saveTimer;

  CyberHexThemeId get themeId => _themeId;

  bool get dynamicColor => _dynamicColor;

  bool get pocketMode => _pocketMode;

  CoverStyle get coverStyle => _coverStyle;

  Set<PlayerAction> get actions => Set<PlayerAction>.unmodifiable(_actions);

  /// ¿Arrancar la reproducción al enchufar auriculares o conectar Bluetooth?
  bool get autoPlayOnConnect => _autoPlayOnConnect;

  /// Botones de la notificación, en el orden canónico del enum.
  List<MediaAction> get mediaActions => <MediaAction>[
        for (final action in MediaAction.values)
          if (_mediaActions.contains(action)) action,
      ];

  Color? get coverAccent => _coverAccent;

  bool get isLoaded => _loaded;

  /// Paleta efectiva: la del tema, con el acento de la carátula si toca.
  CyberHexPalette get palette {
    final base = CyberHexPalette.of(_themeId);
    final accent = _coverAccent;
    if (!_dynamicColor || accent == null) return base;
    return base.withAccent(_readableAccent(accent, base));
  }

  /// `ThemeData` listo para `MaterialApp.theme`.
  ThemeData get themeData => buildCyberHexThemed(palette);

  /// ¿Se pinta esta acción en la barra rápida?
  bool shows(PlayerAction action) => _actions.contains(action);

  void setTheme(CyberHexThemeId id) {
    if (id == _themeId) return;
    _themeId = id;
    _touch();
  }

  void cycleTheme() {
    final values = CyberHexThemeId.values;
    final next = values[(values.indexOf(_themeId) + 1) % values.length];
    setTheme(next);
  }

  void setDynamicColor(bool value) {
    if (value == _dynamicColor) return;
    _dynamicColor = value;
    if (!value) _coverAccent = null;
    _touch();
  }

  void setPocketMode(bool value) {
    if (value == _pocketMode) return;
    _pocketMode = value;
    _touch();
  }

  void setCoverStyle(CoverStyle style) {
    if (style == _coverStyle) return;
    _coverStyle = style;
    _touch();
  }

  void toggleAction(PlayerAction action) {
    if (!_actions.remove(action)) _actions.add(action);
    _touch();
  }

  void setActions(Iterable<PlayerAction> actions) {
    _actions
      ..clear()
      ..addAll(actions);
    _touch();
  }

  void setAutoPlayOnConnect(bool value) {
    if (value == _autoPlayOnConnect) return;
    _autoPlayOnConnect = value;
    _touch();
  }

  /// Enciende o apaga un botón de la notificación. `toggle` no se puede quitar.
  void toggleMediaAction(MediaAction action) {
    if (action == MediaAction.toggle) return;
    if (!_mediaActions.remove(action)) _mediaActions.add(action);
    _touch();
  }

  void setMediaActions(Iterable<MediaAction> actions) {
    _mediaActions
      ..clear()
      ..addAll(actions)
      ..add(MediaAction.toggle);
    _touch();
  }

  /// Acento de la carátula activa. Si no se puede decodificar, se usa un color
  /// estable derivado de los bytes: nunca se queda sin acento.
  Future<Color?> updateCover(Uint8List? bytes) async {
    if (!_dynamicColor) return null;
    if (bytes == null || bytes.isEmpty) {
      if (_coverAccent != null || _coverFingerprint.isNotEmpty) {
        _coverAccent = null;
        _coverFingerprint = '';
        _touch();
      }
      return null;
    }
    final fingerprint = '${bytes.length}:${bytes.isEmpty ? 0 : bytes.first}'
        ':${bytes.length > 64 ? bytes[bytes.length ~/ 2] : 0}';
    if (fingerprint == _coverFingerprint) return _coverAccent;
    _coverFingerprint = fingerprint;
    Color? accent;
    try {
      accent = await accentFromImage(bytes);
    } catch (_) {
      accent = null;
    }
    _coverAccent = accent ?? fallbackAccent(bytes);
    notifyListeners();
    return _coverAccent;
  }

  /// Decodifica a 32 px de ancho y saca el acento de los píxeles.
  static Future<Color?> accentFromImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return accentFromPixels(data.buffer.asUint8List());
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  /// Media ponderada de los píxeles con color (los grises no aportan).
  ///
  /// Puro y determinista: se prueba con bytes sintéticos sin tocar el decodificador.
  static Color? accentFromPixels(Uint8List rgba) {
    if (rgba.length < 4) return null;
    var weight = 0.0;
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 32) continue; // transparente
      final red = rgba[i] / 255;
      final green = rgba[i + 1] / 255;
      final blue = rgba[i + 2] / 255;
      final max = math.max(red, math.max(green, blue));
      final min = math.min(red, math.min(green, blue));
      final saturation = max == 0 ? 0.0 : (max - min) / max;
      if (saturation < 0.12) continue;
      final w = saturation * saturation;
      r += red * w;
      g += green * w;
      b += blue * w;
      weight += w;
    }
    if (weight <= 0) return null;
    return Color.fromARGB(
      255,
      (r / weight * 255).round().clamp(0, 255),
      (g / weight * 255).round().clamp(0, 255),
      (b / weight * 255).round().clamp(0, 255),
    );
  }

  /// Acento estable cuando no hay imagen decodificable.
  static Color fallbackAccent(Uint8List bytes) {
    var hash = 0x811C9DC5;
    for (var i = 0; i < bytes.length && i < 256; i++) {
      hash = ((hash ^ bytes[i]) * 0x01000193) & 0xFFFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.62, 0.55).toColor();
  }

  /// Ajusta el acento para que se lea sobre la paleta (claro u oscuro).
  static Color _readableAccent(Color accent, CyberHexPalette base) {
    final hsl = HSLColor.fromColor(accent);
    final lightness = base.isDark ? 0.62 : 0.42;
    final saturation = hsl.saturation.clamp(0.35, 0.9);
    return hsl.withSaturation(saturation).withLightness(lightness).toColor();
  }

  // --- persistencia --------------------------------------------------------

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final target = file;
    if (target == null) return;
    try {
      if (!target.existsSync()) return;
      final raw = await target.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _themeId = CyberHexThemeId.fromName(decoded['theme'] as String?);
      _dynamicColor = decoded['dynamicColor'] == true;
      _pocketMode = decoded['pocket'] == true;
      _coverStyle = CoverStyle.fromName(decoded['coverStyle'] as String?);
      _autoPlayOnConnect = decoded['autoPlayOnConnect'] == true;
      // El archivo manda: play/pausa siempre está y lo demás, solo si el JSON
      // lo pide. Un `theme.json` de antes de esta función no trae la clave, así
      // que se queda en play/pausa en vez de heredar los tres botones.
      final parsed = <MediaAction>{MediaAction.toggle};
      final mediaActions = decoded['mediaActions'];
      if (mediaActions is List) {
        for (final raw in mediaActions) {
          final action = MediaAction.fromName(raw is String ? raw : null);
          if (action != null) parsed.add(action);
        }
      }
      _mediaActions
        ..clear()
        ..addAll(parsed);
      final actions = decoded['actions'];
      if (actions is List) {
        final parsed = <PlayerAction>{
          for (final name in actions)
            if (PlayerAction.fromName(name is String ? name : null) != null)
              PlayerAction.fromName(name as String)!,
        };
        if (parsed.isNotEmpty) {
          _actions
            ..clear()
            ..addAll(parsed);
        }
      }
      notifyListeners();
    } catch (_) {
      // Un JSON roto cae en el tema neón por defecto.
    }
  }

  void _touch() {
    _dirty = true;
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (file == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () => unawaited(save()));
  }

  Future<void> save() async {
    final target = file;
    _saveTimer?.cancel();
    _saveTimer = null;
    if (target == null) {
      _dirty = false;
      return;
    }
    try {
      final payload = <String, Object?>{
        'version': formatVersion,
        'theme': _themeId.name,
        'dynamicColor': _dynamicColor,
        'pocket': _pocketMode,
        'coverStyle': _coverStyle.name,
        'actions': <String>[for (final action in _actions) action.name],
        'autoPlayOnConnect': _autoPlayOnConnect,
        'mediaActions': <String>[for (final action in mediaActions) action.name],
      };
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
      _dirty = false;
    } catch (_) {
      // Sin disco, los ajustes duran la sesión.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_dirty) unawaited(save());
    super.dispose();
  }
}
