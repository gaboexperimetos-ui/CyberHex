import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'ui/player_page.dart';

void main() {
  runApp(const CyberHexApp());
}

class CyberHexApp extends StatelessWidget {
  const CyberHexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CyberHex',
      debugShowCheckedModeBanner: false,
      theme: buildCyberHexTheme(),
      home: const PlayerPage(),
    );
  }
}
