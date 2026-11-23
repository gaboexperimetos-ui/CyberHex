import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// Recuerda en qué pestaña del armazón se quedó la última sesión.
///
/// Guarda solo un entero en `home_tab.json` (mismo patrón `.tmp` + `rename`
/// que el resto de almacenes) para que al reabrir la app se vuelva a Inicio,
/// Biblioteca, Listas o Ajustes tal como se dejó. Un archivo roto o de otra
/// versión cae en Inicio sin romper el arranque.
class HomeTabStore extends ChangeNotifier {
  HomeTabStore({File? file})
    : file = file ?? File('${StorageDirectory.current.path}/home_tab.json');

  HomeTabStore.memory() : file = null;

  static const int formatVersion = 1;

  /// Pestañas del armazón: Inicio, Biblioteca, Listas y Ajustes.
  static const int tabCount = 4;

  final File? file;

  int _tab = 0;
  bool _loaded = false;
  bool _dirty = false;
  Timer? _saveTimer;

  int get tab => _tab;

  bool get isLoaded => _loaded;

  /// Cambia de pestaña y la persiste. Un índice fuera de rango se recorta.
  void setTab(int value) {
    final next = value.clamp(0, tabCount - 1);
    if (next == _tab) return;
    _tab = next;
    _dirty = true;
    notifyListeners();
    _scheduleSave();
  }

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
      final value = decoded['tab'];
      if (value is! num) return;
      _tab = value.toInt().clamp(0, tabCount - 1);
      notifyListeners();
    } catch (_) {
      // Un JSON roto se queda en Inicio.
    }
  }

  void _scheduleSave() {
    if (file == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(save()),
    );
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
      final payload = <String, Object?>{'version': formatVersion, 'tab': _tab};
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
      _dirty = false;
    } catch (_) {
      // Sin disco, la pestaña dura la sesión.
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
