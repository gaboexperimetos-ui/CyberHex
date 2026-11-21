import 'package:cyberhex/theme.dart';
import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el tema usa el fondo oscuro y el acento verde de CyberHex', () {
    final theme = buildCyberHexTheme();
    expect(theme.scaffoldBackgroundColor, chBackground);
    expect(theme.colorScheme.primary, chAccent);
    expect(theme.colorScheme.brightness, Brightness.dark);
  });
}
