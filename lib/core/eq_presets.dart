/// Presets del ecualizador de 36 bandas.
///
/// Un preset es una **curva**: unos pocos puntos (frecuencia en Hz → ganancia en
/// dB) que se interpolan en escala logarítmica hasta las 36 bandas reales que
/// reporta el núcleo (`ch_engine_eq_band_freq`). Así los presets no dependen de
/// que las bandas estén repartidas exactamente igual: si mañana el motor cambia
/// el reparto, siguen sonando como se pensaron.
library;

import 'dart:math' as math;

/// Un punto de la curva: frecuencia central y ganancia en dB.
class EqAnchor {
  const EqAnchor(this.hz, this.db);

  final double hz;
  final double db;
}

/// Preset del ecualizador.
class EqPreset {
  const EqPreset({
    required this.name,
    required this.description,
    required this.anchors,
  });

  final String name;
  final String description;

  /// Puntos de la curva, **ordenados por frecuencia**.
  final List<EqAnchor> anchors;

  /// Curva plana: sin cambios.
  static const EqPreset flat = EqPreset(
    name: 'Plano',
    description: 'Sin tocar nada (identidad, coste cero)',
    anchors: <EqAnchor>[EqAnchor(20, 0), EqAnchor(20000, 0)],
  );

  /// Nombre e inicial para los botones compactos.
  String get shortName => name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

  /// Ganancia (dB) para cada frecuencia, interpolando en log-frecuencia.
  ///
  /// Fuera del rango de los anclajes se mantiene el valor del extremo y todo se
  /// recorta a ±18 dB, que es el recorrido del motor.
  List<double> gainsFor(List<double> frequencies) {
    if (frequencies.isEmpty) return const <double>[];
    if (anchors.isEmpty) return List<double>.filled(frequencies.length, 0);
    final sorted = List<EqAnchor>.of(anchors)
      ..sort((a, b) => a.hz.compareTo(b.hz));
    return List<double>.unmodifiable(<double>[
      for (final hz in frequencies)
        _interpolate(sorted, hz.isFinite && hz > 0 ? hz : 20),
    ]);
  }

  static double _interpolate(List<EqAnchor> sorted, double hz) {
    final first = sorted.first;
    if (hz <= first.hz) return _clamp(first.db);
    final last = sorted.last;
    if (hz >= last.hz) return _clamp(last.db);
    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      if (hz >= a.hz && hz <= b.hz) {
        final span = math.log(b.hz / a.hz);
        if (span <= 0) return _clamp(b.db);
        final t = math.log(hz / a.hz) / span;
        return _clamp(a.db + (b.db - a.db) * t);
      }
    }
    return _clamp(last.db);
  }

  static double _clamp(double db) => db.clamp(-18.0, 18.0).toDouble();

  /// Curva de compensación a partir de lo que el usuario **no** oye.
  ///
  /// `heard[i]` dice si la banda `i` se oyó en la prueba de audición. Las que no
  /// se oyeron se refuerzan (hasta +12 dB, más no ayuda y come margen) y las que
  /// sí se oyeron quedan planas: es un ajuste suave, no un audífono.
  static EqPreset compensationFrom({
    required List<double> frequencies,
    required List<bool> heard,
    String name = 'Mi oído',
  }) {
    final anchors = <EqAnchor>[];
    for (var i = 0; i < frequencies.length; i++) {
      final hz = frequencies[i];
      if (!hz.isFinite || hz <= 0) continue;
      final ok = i < heard.length && heard[i];
      anchors.add(EqAnchor(hz, ok ? 0 : 12));
    }
    if (anchors.isEmpty) return flat;
    return EqPreset(
      name: name,
      description: 'Compensación suave de las bandas que no se oyeron',
      anchors: List<EqAnchor>.unmodifiable(anchors),
    );
  }

  @override
  String toString() => 'EqPreset($name, ${anchors.length} puntos)';
}

/// Presets incluidos. Todos de ±6 dB o menos salvo los de carácter marcado,
/// porque un preset que recorta el margen obliga al limitador a trabajar.
const List<EqPreset> eqPresets = <EqPreset>[
  EqPreset.flat,
  EqPreset(
    name: 'Rock',
    description: 'Graves y agudos arriba, medios atrás',
    anchors: <EqAnchor>[
      EqAnchor(30, 4),
      EqAnchor(80, 3),
      EqAnchor(300, -2),
      EqAnchor(1000, -1),
      EqAnchor(3000, 2),
      EqAnchor(8000, 4),
      EqAnchor(16000, 3),
    ],
  ),
  EqPreset(
    name: 'Pop',
    description: 'Voz al frente y brillo suave',
    anchors: <EqAnchor>[
      EqAnchor(40, 1),
      EqAnchor(200, -1),
      EqAnchor(1000, 2),
      EqAnchor(3000, 3),
      EqAnchor(10000, 2),
    ],
  ),
  EqPreset(
    name: 'Jazz',
    description: 'Medios cálidos, extremos tranquilos',
    anchors: <EqAnchor>[
      EqAnchor(40, 3),
      EqAnchor(400, 1),
      EqAnchor(2000, 2),
      EqAnchor(6000, -1),
      EqAnchor(14000, -2),
    ],
  ),
  EqPreset(
    name: 'Clásica',
    description: 'Curva suave de sala de concierto',
    anchors: <EqAnchor>[
      EqAnchor(30, 2),
      EqAnchor(250, -2),
      EqAnchor(1500, 0),
      EqAnchor(5000, 1),
      EqAnchor(12000, 2),
    ],
  ),
  EqPreset(
    name: 'Vocal',
    description: 'Karaoke y podcast: voz clara y sin retumbe',
    anchors: <EqAnchor>[
      EqAnchor(60, -6),
      EqAnchor(120, -3),
      EqAnchor(400, 1),
      EqAnchor(2000, 3),
      EqAnchor(5000, 2),
      EqAnchor(12000, 0),
    ],
  ),
  EqPreset(
    name: 'Graves',
    description: 'Más cuerpo abajo, resto plano',
    anchors: <EqAnchor>[
      EqAnchor(30, 6),
      EqAnchor(70, 5),
      EqAnchor(150, 2),
      EqAnchor(500, 0),
      EqAnchor(20000, 0),
    ],
  ),
  EqPreset(
    name: 'Agudos',
    description: 'Más aire y detalle arriba',
    anchors: <EqAnchor>[
      EqAnchor(20, 0),
      EqAnchor(1000, 0),
      EqAnchor(4000, 2),
      EqAnchor(8000, 4),
      EqAnchor(14000, 5),
    ],
  ),
  EqPreset(
    name: 'Electrónica',
    description: 'Subgraves y brillo, medios fuera del camino',
    anchors: <EqAnchor>[
      EqAnchor(25, 5),
      EqAnchor(60, 4),
      EqAnchor(250, -3),
      EqAnchor(1000, -1),
      EqAnchor(6000, 2),
      EqAnchor(15000, 3),
    ],
  ),
  EqPreset(
    name: 'Noche',
    description: 'Loudness suave para escuchar bajo',
    anchors: <EqAnchor>[
      EqAnchor(40, 4),
      EqAnchor(200, 0),
      EqAnchor(1000, -3),
      EqAnchor(3000, -2),
      EqAnchor(10000, 1),
    ],
  ),
];
