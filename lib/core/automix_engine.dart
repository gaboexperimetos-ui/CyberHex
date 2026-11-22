import 'dart:async';

import 'player_api.dart';
import 'player_controller.dart';

/// Cómo se emparejan dos pistas por tempo.
///
/// Si los BPM están cerca, se estira la que suena un poco para que el pulso
/// cuadre durante el crossfade; si están lejos, no se toca nada (mezclar 90 con
/// 150 suena a accidente, no a mezcla).
class AutomixPlan {
  const AutomixPlan({
    required this.bpmA,
    required this.bpmB,
    required this.tempo,
    required this.crossfade,
    this.analysed = true,
  });

  /// BPM de la pista que suena.
  final double bpmA;

  /// BPM de la que entra.
  final double bpmB;

  /// Factor de velocidad a aplicar (`1.0` = sin cambios).
  final double tempo;

  /// Segundos de crossfade recomendados.
  final double crossfade;

  /// `false` cuando no hubo BPM y el plan es «no toques nada».
  final bool analysed;

  bool get mixes => analysed && bpmA > 0 && bpmB > 0 && tempo != 1.0;

  String describe() {
    if (!analysed) return 'Sin pulso claro: mezcla normal';
    if (bpmA <= 0 || bpmB <= 0) return 'Sin pulso claro: mezcla normal';
    final percent = ((tempo - 1) * 100).toStringAsFixed(1);
    return '${bpmA.round()} → ${bpmB.round()} BPM · '
        '${tempo == 1.0 ? 'tempo intacto' : '$percent % de ajuste'} · '
        '${crossfade.toStringAsFixed(0)} s';
  }

  @override
  String toString() => 'AutomixPlan(${describe()})';
}

/// Calcula el plan de mezcla. Función pura: toda la lógica difícil está aquí y
/// se puede probar sin motor.
abstract final class AutomixPlanner {
  /// Desvío máximo de tempo (±8 %: por encima se nota el «chipmunk»).
  static const double defaultMaxStretch = 0.08;

  /// Crossfade por defecto si los BPM no se parecen.
  static const double defaultCrossfade = 6;

  static AutomixPlan plan({
    required double bpmA,
    required double bpmB,
    double maxStretch = defaultMaxStretch,
    double crossfade = defaultCrossfade,
  }) {
    final a = bpmA.isFinite && bpmA > 0 ? bpmA : 0.0;
    final b = bpmB.isFinite && bpmB > 0 ? bpmB : 0.0;
    if (a <= 0 || b <= 0) {
      return AutomixPlan(
        bpmA: a,
        bpmB: b,
        tempo: 1,
        crossfade: crossfade,
        analysed: false,
      );
    }
    // El doble o la mitad del pulso cuentan como el mismo patrón (90 vs 180):
    // se baja el cociente a la octava más cercana a 1 antes de limitar el
    // estiramiento. El corte es √2, el punto donde doblar deja de estar más
    // cerca que no doblar.
    var ratio = b / a;
    while (ratio > 1.4142135623730951) {
      ratio /= 2;
    }
    while (ratio < 0.7071067811865475) {
      ratio *= 2;
    }
    final bounded = (ratio - 1).clamp(-maxStretch, maxStretch) + 1;
    return AutomixPlan(
      bpmA: a,
      bpmB: b,
      tempo: (bounded * 1000).round() / 1000,
      crossfade: crossfade,
    );
  }
}

/// De dónde salen los BPM. En producción es `controller.detectBpm` (que corre en
/// un isolate); en las pruebas, una tabla.
typedef BpmProbe = Future<double> Function(String path);

/// En qué punto del ciclo está el automix.
enum AutomixPhase {
  /// Sin pista o lejos del final.
  idle,

  /// Calculando BPM de las dos pistas.
  analysing,

  /// Tempo ajustado; el crossfade del motor está haciendo el resto.
  blending,

  /// Volviendo al tempo normal tras el cambio de pista.
  restoring,
}

/// Automix DJ: empareja el final de una pista con el principio de la siguiente.
///
/// No inventa audio: usa lo que el núcleo ya tiene (crossfade por motor y
/// `speed`) y lo orquesta. Cuando faltan menos de [preRoll] segundos para el
/// final, calcula el BPM de la pista actual y de la siguiente, ajusta el tempo
/// como mucho ±8 % y deja el crossfade puesto; al entrar la siguiente pista,
/// devuelve el tempo a `1.0`.
///
/// El temporizador es opcional (`autoTick: false` en pruebas): [tick] se puede
/// llamar a mano.
class AutomixEngine {
  AutomixEngine({
    required this.controller,
    BpmProbe? probe,
    this.enabled = false,
    this.autoTick = true,
    this.interval = const Duration(milliseconds: 500),
    this.preRoll = 8,
    this.crossfade = AutomixPlanner.defaultCrossfade,
  }) : probe = probe ?? controller.detectBpm;

  final PlayerController controller;
  final BpmProbe probe;
  final Duration interval;

  /// Segundos antes del final en los que se prepara la mezcla.
  final double preRoll;

  /// Crossfade que se pide al motor (segundos).
  final double crossfade;

  bool enabled;

  bool autoTick;

  final Map<String, double> _bpmCache = <String, double>{};

  AutomixPhase _phase = AutomixPhase.idle;
  AutomixPlan? _plan;
  String _status = 'Automix apagado';
  Timer? _timer;
  bool _busy = false;
  bool _blending = false;
  int _lastQueueIndex = -1;

  AutomixPhase get phase => _phase;

  AutomixPlan? get plan => _plan;

  /// Texto para la UI («120 → 128 BPM · 6 s»).
  String get status => _status;

  double bpmOf(String path) => _bpmCache[path] ?? 0;

  void start() {
    if (!autoTick) return;
    _timer ??= Timer.periodic(interval, (_) => tick());
  }

  void setEnabled(bool value) {
    enabled = value;
    if (!value) {
      _status = 'Automix apagado';
      _restore();
      _phase = AutomixPhase.idle;
    } else {
      _status = 'Automix listo';
      start();
    }
  }

  /// Analiza dos pistas (con caché: el BPM de una pista no cambia).
  Future<AutomixPlan> analyse(String a, String b) async {
    final bpmA = await _bpm(a);
    final bpmB = await _bpm(b);
    final result = AutomixPlanner.plan(bpmA: bpmA, bpmB: bpmB, crossfade: crossfade);
    _plan = result;
    _status = result.describe();
    return result;
  }

  Future<double> _bpm(String path) async {
    final cached = _bpmCache[path];
    if (cached != null) return cached;
    try {
      final value = await probe(path);
      final safe = value.isFinite && value > 0 ? value : 0.0;
      _bpmCache[path] = safe;
      return safe;
    } catch (_) {
      _bpmCache[path] = 0;
      return 0;
    }
  }

  /// Un paso del bucle. Barato: solo mira el snapshot.
  void tick() {
    if (!enabled || _busy) return;
    final snapshot = controller.snapshot;
    if (!snapshot.hasTrack || snapshot.duration <= 0) return;

    // Cambio de pista: se acabó la mezcla.
    if (_blending && snapshot.queueIndex != _lastQueueIndex) {
      _blending = false;
      _restore();
      _phase = AutomixPhase.idle;
      _status = 'Mezcla completada';
      _lastQueueIndex = snapshot.queueIndex;
      return;
    }

    final position = controller.position.value;
    final remaining = snapshot.duration - position;
    if (remaining > preRoll || remaining < 0) return;

    final index = snapshot.queueIndex;
    if (index < 0 || index + 1 >= snapshot.queue.length) return;
    final current = snapshot.queue[index];
    final next = snapshot.queue[index + 1];
    if (!current.isPlayable || !next.isPlayable) return;

    _busy = true;
    _phase = AutomixPhase.analysing;
    _status = 'Analizando BPM…';
    unawaited(_blend(current.path, next.path));
  }

  Future<void> _blend(String current, String next) async {
    try {
      final result = await analyse(current, next);
      if (!enabled) return;
      final snapshot = controller.snapshot;
      _lastQueueIndex = snapshot.queueIndex;
      controller.setCrossfade(result.crossfade);
      if (result.tempo != 1.0) controller.setSpeed(result.tempo);
      _blending = true;
      _phase = AutomixPhase.blending;
      _status = result.describe();
    } finally {
      _busy = false;
    }
  }

  void _restore() {
    if (!_blending && _phase == AutomixPhase.idle) return;
    _phase = AutomixPhase.restoring;
    controller.setSpeed(1);
    _blending = false;
  }

  /// Devuelve el tempo a la normalidad y suelta el temporizador.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_blending) {
      controller.setSpeed(1);
      _blending = false;
    }
  }
}

/// Utilidad para la UI: describe el estado con palabras.
String automixLabel(AutomixPhase phase) => switch (phase) {
      AutomixPhase.idle => 'En espera',
      AutomixPhase.analysing => 'Analizando',
      AutomixPhase.blending => 'Mezclando',
      AutomixPhase.restoring => 'Restaurando tempo',
    };

/// Aviso de compatibilidad del plan (lo usa la hoja de la cola).
String automixHint(PlayerSnapshot snapshot) {
  if (!snapshot.hasTrack) return 'Abre una pista para mezclar.';
  if (snapshot.queueIndex + 1 >= snapshot.queue.length) {
    return 'No hay siguiente en la cola.';
  }
  return 'Mezcla automática al final de la pista.';
}
