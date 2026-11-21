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
