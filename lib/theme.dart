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

/// Tema neón de siempre. Se conserva el nombre para no romper llamadas
/// existentes; ahora comparte tipografía y controles con el resto de temas.
ThemeData buildCyberHexTheme() => buildCyberHexThemed(CyberHexPalette.neon);

// ---------------------------------------------------------------------------
// Temas (fase 6): cuatro paletas y estilos de carátula
// ---------------------------------------------------------------------------

/// Los cinco temas de la app. `neon` es el de siempre.
enum CyberHexThemeId {
  neon('CyberHex Neon'),
  amoled('AMOLED Negro Puro'),
  light('Claro'),
  materialYou('Material You'),
  cyberpunk('Cyberpunk');

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

  /// Copia con otro acento (el color que saca el modo dinámico de la carátula).
  ///
  /// Un color puede ser precioso y no leerse (un morado casi negro sobre fondo
  /// negro), así que se aclara —o se oscurece, en temas claros— hasta que
  /// contraste con el fondo.
  CyberHexPalette withAccent(Color color) {
    final readable = _readableAccent(color);
    return _withAccentColor(readable);
  }

  CyberHexPalette _withAccentColor(Color color) => CyberHexPalette(
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

  /// Sube o baja la luminosidad del acento hasta que se lea sobre el fondo.
  Color _readableAccent(Color color) {
    final dark = brightness == Brightness.dark;
    var hsl = HSLColor.fromColor(color);
    for (var i = 0; i < 24; i++) {
      final candidate = hsl.toColor();
      final luminance = candidate.computeLuminance();
      final ratio = _contrastRatio(candidate, background);
      // Se pide contraste suficiente *y* un brillo claro/oscurio de verdad: un
      // gris medio sobre negro cumple la ratio pero cansa la vista.
      final readable =
          ratio >= 3.0 && (dark ? luminance >= 0.25 : luminance <= 0.45);
      if (readable) return candidate;
      hsl = hsl.withLightness(
        (hsl.lightness + (dark ? 0.05 : -0.05)).clamp(0.0, 1.0),
      );
    }
    return dark ? const Color(0xFFF2F2F2) : const Color(0xFF101010);
  }

  /// Ratio de contraste WCAG entre dos colores (1 = iguales, 21 = blanco/negro).
  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

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

  /// Neón rosa sobre azul noche: la veta más «cyberpunk» de la marca, con el
  /// acento cálido para que las carátulas y la barra no se confundan con el neón
  /// verde de siempre.
  static const CyberHexPalette cyberpunk = CyberHexPalette(
    id: CyberHexThemeId.cyberpunk,
    background: Color(0xFF0B0713),
    surface: Color(0xFF171024),
    surfaceHigh: Color(0xFF241735),
    primary: Color(0xFF2B1050),
    secondary: Color(0xFF0EA5E9),
    accent: Color(0xFFF472B6),
    onAccent: Color(0xFF2A0717),
    foreground: Color(0xFFF5F0FA),
    muted: Color(0xFFA99BBE),
    border: Color(0xFF3B2456),
    error: Color(0xFFFF6B81),
    brightness: Brightness.dark,
  );

  /// Paleta de un tema.
  static CyberHexPalette of(CyberHexThemeId id) => switch (id) {
    CyberHexThemeId.neon => neon,
    CyberHexThemeId.amoled => amoled,
    CyberHexThemeId.light => light,
    CyberHexThemeId.materialYou => materialYou,
    CyberHexThemeId.cyberpunk => cyberpunk,
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
///
/// Aquí vive la tipografía y el acabado común de los controles; el color de
/// cada pantalla sale de `paletteOf(context)`. Una pantalla nueva que use
/// `Text`/`FilledButton`/`TextField` ya se ve de la casa sin estilos propios.
ThemeData buildCyberHexThemed(CyberHexPalette palette) {
  final scheme = ColorScheme(
    brightness: palette.brightness,
    primary: palette.accent,
    onPrimary: palette.onAccent,
    secondary: palette.secondary,
    onSecondary: Colors.white,
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

  final radius = BorderRadius.circular(12);
  final text = base.textTheme
      .copyWith(
        displayLarge: const TextStyle(
          fontFamily: 'Righteous',
          fontSize: 40,
          letterSpacing: 1.2,
          height: 1.05,
        ),
        displayMedium: const TextStyle(
          fontFamily: 'Righteous',
          fontSize: 30,
          letterSpacing: 0.8,
          height: 1.1,
        ),
        displaySmall: const TextStyle(
          fontFamily: 'Righteous',
          fontSize: 24,
          letterSpacing: 0.4,
          height: 1.15,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          height: 1.15,
        ),
        headlineSmall: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          height: 1.18,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        titleSmall: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(fontSize: 14, height: 1.45),
        bodyMedium: const TextStyle(fontSize: 13, height: 1.45),
        bodySmall: const TextStyle(fontSize: 11.5, height: 1.45),
        labelLarge: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelMedium: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
        ),
        labelSmall: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      )
      .apply(bodyColor: palette.foreground, displayColor: palette.foreground);

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[palette],
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: palette.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Righteous',
        fontSize: 17,
        letterSpacing: 2,
        color: palette.foreground,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: palette.accent,
      unselectedLabelColor: palette.muted,
      indicatorColor: palette.accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: palette.border.withValues(alpha: 0.35),
      labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: palette.surfaceHigh.withValues(alpha: 0.55),
      hintStyle: TextStyle(fontSize: 12, color: palette.muted),
      prefixIconColor: palette.muted,
      suffixIconColor: palette.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: palette.border.withValues(alpha: 0.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(
          color: palette.accent.withValues(alpha: 0.7),
          width: 1.2,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surfaceHigh.withValues(alpha: 0.6),
      selectedColor: palette.accent.withValues(alpha: 0.16),
      checkmarkColor: palette.accent,
      side: BorderSide(color: palette.border.withValues(alpha: 0.5)),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(fontSize: 11.5, color: palette.foreground),
      secondaryLabelStyle: TextStyle(fontSize: 11.5, color: palette.accent),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    dividerTheme: DividerThemeData(
      color: palette.border.withValues(alpha: 0.35),
      thickness: 1,
      space: 1,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: palette.accent,
      inactiveTrackColor: palette.surfaceHigh,
      thumbColor: palette.accent,
      overlayColor: palette.accent.withValues(alpha: 0.14),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      valueIndicatorColor: palette.surfaceHigh,
      valueIndicatorTextStyle: TextStyle(
        color: palette.foreground,
        fontSize: 11,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.accent,
      linearTrackColor: palette.surfaceHigh,
      circularTrackColor: palette.surfaceHigh,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        disabledBackgroundColor: palette.surfaceHigh,
        disabledForegroundColor: palette.muted,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.foreground,
        side: BorderSide(color: palette.border.withValues(alpha: 0.7)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.foreground,
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: palette.foreground,
      iconColor: palette.muted,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: palette.foreground),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border.withValues(alpha: 0.7)),
      ),
      textStyle: TextStyle(fontSize: 11, color: palette.foreground),
      waitDuration: const Duration(milliseconds: 450),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceHigh,
      contentTextStyle: TextStyle(fontSize: 12.5, color: palette.foreground),
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: palette.border,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: palette.border.withValues(alpha: 0.6)),
      ),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: palette.foreground,
      ),
      contentTextStyle: TextStyle(
        fontSize: 13,
        height: 1.45,
        color: palette.muted,
      ),
    ),
  );
}
