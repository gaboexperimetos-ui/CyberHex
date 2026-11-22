import 'package:material_ui/material_ui.dart';

const Color chBackground = Color(0xFF0F0F23);
const Color chSurface = Color(0xFF1B1B30);
const Color chSurfaceHigh = Color(0xFF27273B);
const Color chPrimary = Color(0xFF1E1B4B);
const Color chSecondary = Color(0xFF4338CA);
const Color chAccent = Color(0xFF22C55E);
const Color chOnAccent = Color(0xFF06210F);
const Color chForeground = Color(0xFFF8FAFC);
const Color chMuted = Color(0xFF94A3B8);
const Color chBorder = Color(0xFF312E81);
const Color chError = Color(0xFFEF4444);

const TextStyle chDisplay = TextStyle(
  fontFamily: 'Righteous',
  color: chForeground,
  letterSpacing: 1.5,
);

ThemeData buildCyberHexTheme() {
  const scheme = ColorScheme.dark(
    primary: chAccent,
    onPrimary: chOnAccent,
    secondary: chSecondary,
    onSecondary: Colors.white,
    surface: chSurface,
    onSurface: chForeground,
    error: chError,
    outline: chBorder,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: chBackground,
    fontFamily: 'Poppins',
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: chForeground,
      displayColor: chForeground,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: chAccent,
      inactiveTrackColor: chSurfaceHigh,
      thumbColor: chAccent,
      overlayColor: chAccent.withValues(alpha: 0.16),
      trackHeight: 3,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: chForeground),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: chSurfaceHigh,
      contentTextStyle: TextStyle(color: chForeground),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: chSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Temas (fase 6): cuatro paletas y estilos de carátula
// ---------------------------------------------------------------------------

/// Los cuatro temas de la app. `neon` es el de siempre.
enum CyberHexThemeId {
  neon('CyberHex Neon'),
  amoled('AMOLED Negro Puro'),
  light('Claro'),
  materialYou('Material You');

  const CyberHexThemeId(this.label);

  final String label;

  static CyberHexThemeId fromName(String? name) {
    for (final id in CyberHexThemeId.values) {
      if (id.name == name) return id;
    }
    return CyberHexThemeId.neon;
  }
}

/// Paleta completa de un tema.
///
/// Las constantes `ch*` de arriba son la paleta **neón**, que sigue siendo la de
/// por defecto: cuando una pantalla no pide la paleta del contexto, se ve igual
/// que antes. Las pantallas que ya la piden (reproductor, mini-reproductor y
/// ajustes) cambian con el tema.
/// Paleta de un tema.
///
/// Extiende [ThemeExtension] para poder viajar dentro del `ThemeData` y
/// recuperarse con `Theme.of(context).extension<CyberHexPalette>()`: sin eso,
/// `paletteOf` no encontraría nada y devolvería siempre la neón.
class CyberHexPalette extends ThemeExtension<CyberHexPalette> {
  const CyberHexPalette({
    required this.id,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.onAccent,
    required this.foreground,
    required this.muted,
    required this.border,
    required this.error,
    required this.brightness,
  });

  final CyberHexThemeId id;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color onAccent;
  final Color foreground;
  final Color muted;
  final Color border;
  final Color error;
  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  String get label => id.label;

  /// Copia con otro acento (color dinámico de la carátula).
  CyberHexPalette withAccent(Color color) => CyberHexPalette(
        id: id,
        background: background,
        surface: surface,
        surfaceHigh: surfaceHigh,
        primary: primary,
        secondary: secondary,
        accent: color,
        onAccent: _onColor(color),
        foreground: foreground,
        muted: muted,
        border: border,
        error: error,
        brightness: brightness,
      );

  static const CyberHexPalette neon = CyberHexPalette(
    id: CyberHexThemeId.neon,
    background: chBackground,
    surface: chSurface,
    surfaceHigh: chSurfaceHigh,
    primary: chPrimary,
    secondary: chSecondary,
    accent: chAccent,
    onAccent: chOnAccent,
    foreground: chForeground,
    muted: chMuted,
    border: chBorder,
    error: chError,
    brightness: Brightness.dark,
  );

  static const CyberHexPalette amoled = CyberHexPalette(
    id: CyberHexThemeId.amoled,
    background: Color(0xFF000000),
    surface: Color(0xFF0A0A0C),
    surfaceHigh: Color(0xFF16161A),
    primary: Color(0xFF101014),
    secondary: Color(0xFF1F2937),
    accent: Color(0xFF22C55E),
    onAccent: Color(0xFF04170C),
    foreground: Color(0xFFF4F6FA),
    muted: Color(0xFF8C93A6),
    border: Color(0xFF232329),
    error: Color(0xFFFF5566),
    brightness: Brightness.dark,
  );

  static const CyberHexPalette light = CyberHexPalette(
    id: CyberHexThemeId.light,
    background: Color(0xFFF7F7FB),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEDEDF4),
    primary: Color(0xFF4338CA),
    secondary: Color(0xFF6D28D9),
    accent: Color(0xFF0E9F6E),
    onAccent: Color(0xFFFFFFFF),
    foreground: Color(0xFF14142B),
    muted: Color(0xFF5A5A75),
    border: Color(0xFFD7D7E5),
    error: Color(0xFFD93025),
    brightness: Brightness.light,
  );

  static const CyberHexPalette materialYou = CyberHexPalette(
    id: CyberHexThemeId.materialYou,
    background: Color(0xFF14121A),
    surface: Color(0xFF1E1A26),
    surfaceHigh: Color(0xFF2A2434),
    primary: Color(0xFF6750A4),
    secondary: Color(0xFF7D5260),
    accent: Color(0xFFD0BCFF),
    onAccent: Color(0xFF1C1B1F),
    foreground: Color(0xFFE7E0EC),
    muted: Color(0xFFA9A2B8),
    border: Color(0xFF3B3450),
    error: Color(0xFFF2B8B5),
    brightness: Brightness.dark,
  );

  /// Paleta de un tema.
  static CyberHexPalette of(CyberHexThemeId id) => switch (id) {
        CyberHexThemeId.neon => neon,
        CyberHexThemeId.amoled => amoled,
        CyberHexThemeId.light => light,
        CyberHexThemeId.materialYou => materialYou,
      };

  /// Negro o blanco según el brillo del acento (contraste legible).
  static Color _onColor(Color color) =>
      color.computeLuminance() > 0.55 ? const Color(0xFF101018) : Colors.white;

  @override
  String toString() => 'CyberHexPalette($label)';

  /// Las paletas no se interpolan: cambiar de tema es instantáneo, así que
  /// `lerp` devuelve una u otra según el lado del ecuador de la animación.
  @override
  CyberHexPalette copyWith() => this;

  @override
  CyberHexPalette lerp(covariant CyberHexPalette? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Cómo se pinta la carátula en el reproductor.
enum CoverStyle {
  square('Cuadrada'),
  rounded('Redondeada'),
  spinningDisc('Disco giratorio'),
  fullBleed('A sangre');

  const CoverStyle(this.label);

  final String label;

  static CoverStyle fromName(String? name) {
    for (final style in CoverStyle.values) {
      if (style.name == name) return style;
    }
    return CoverStyle.spinningDisc;
  }
}

/// Paleta del contexto, con la neón como red de seguridad.
///
/// Se resuelve por `Theme.of(context).extension<CyberHexPalette>()`, así que una
/// pantalla que no la consulte no se rompe: simplemente se ve neón.
CyberHexPalette paletteOf(BuildContext context) =>
    Theme.of(context).extension<CyberHexPalette>() ?? CyberHexPalette.neon;

/// Tema de Material construido a partir de una paleta.
ThemeData buildCyberHexThemed(CyberHexPalette palette) {
  final scheme = ColorScheme(
    brightness: palette.brightness,
    primary: palette.accent,
    onPrimary: palette.onAccent,
    secondary: palette.secondary,
    onSecondary: palette.isDark ? Colors.white : Colors.white,
    surface: palette.surface,
    onSurface: palette.foreground,
    error: palette.error,
    onError: Colors.white,
    outline: palette.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    fontFamily: 'Poppins',
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[palette],
    textTheme: base.textTheme.apply(
      bodyColor: palette.foreground,
      displayColor: palette.foreground,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: palette.foreground,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: palette.accent,
      inactiveTrackColor: palette.surfaceHigh,
      thumbColor: palette.accent,
      overlayColor: palette.accent.withValues(alpha: 0.16),
      trackHeight: 3,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: palette.foreground),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceHigh,
      contentTextStyle: TextStyle(color: palette.foreground),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
