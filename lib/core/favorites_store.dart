import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// Favoritos de la biblioteca: un conjunto de rutas guardado en JSON.
///
/// Igual que la sesión, escribe con `.tmp` + rename para no dejar el archivo a
/// medias si se corta la luz, y nunca lanza: si no se puede guardar, los
/// favoritos siguen vivos en memoria hasta cerrar la app.
///
/// Extiende [ChangeNotifier] porque la pantalla de biblioteca y el corazón de
/// la lista tienen que repintarse en cuanto se marca o desmarca una pista.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore({File? file})
      : file = file ??
            File('${SessionStore.defaultDirectory().path}/favorites.json');

  /// Sin disco: para pruebas y vistas previas.
  FavoritesStore.memory() : file = null;

  static const int formatVersion = 1;

  final File? file;

  final Set<String> _paths = <String>{};
  bool _loaded = false;
  bool _warned = false;

  /// Copia inmutable; ordenar no es necesario, solo consultar.
  Set<String> get paths => Set<String>.unmodifiable(_paths);

  int get length => _paths.length;

  bool get isEmpty => _paths.isEmpty;

  bool get isLoaded => _loaded;

  bool contains(String path) => _paths.contains(path);

  /// Lee el archivo. `load()` dos veces no hace nada la segunda.
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
      if (decoded is! Map<String, Object?>) return;
      final list = decoded['paths'];
      if (list is! List) return;
      var changed = false;
      for (final entry in list) {
        if (entry is String && entry.isNotEmpty && _paths.add(entry)) {
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (error) {
      // JSON roto: se empieza con la lista vacía, sin molestar al usuario.
      debugPrint('FavoritesStore: favoritos ilegibles, se ignoran ($error)');
    }
  }

  /// Marca o desmarca una pista. Devuelve `true` si ahora es favorita.
  Future<bool> toggle(String path) async {
    if (path.isEmpty) return false;
    final nowFavorite = !_paths.remove(path);
    if (nowFavorite) _paths.add(path);
    // La UI se entera ya; el disco va por detrás.
    notifyListeners();
    await save();
    return nowFavorite;
  }

  Future<bool> add(String path) async {
    if (path.isEmpty || !_paths.add(path)) return contains(path);
    notifyListeners();
    await save();
    return true;
  }

  Future<bool> remove(String path) async {
    if (!_paths.remove(path)) return false;
    notifyListeners();
    await save();
    return true;
  }

  /// Escritura atómica: `<archivo>.tmp` y luego rename.
  Future<bool> save() async {
    final target = file;
    if (target == null) return false;
    File? temp;
    try {
      final directory = target.parent;
      if (!directory.existsSync()) directory.createSync(recursive: true);
      temp = File('${target.path}.tmp');
      final payload = jsonEncode(<String, Object?>{
        'version': formatVersion,
        'paths': _paths.toList()..sort(),
      });
      await temp.writeAsString(payload, flush: true);
      await temp.rename(target.path);
      return true;
    } catch (error) {
      if (!_warned) {
        _warned = true;
        debugPrint('FavoritesStore: no se pudieron guardar ($error)');
      }
      try {
        if (temp != null && temp.existsSync()) temp.deleteSync();
      } catch (_) {
        // Nada más que hacer.
      }
      return false;
    }
  }
}
