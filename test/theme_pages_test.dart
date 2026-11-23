import 'package:cyberhex/core/stats_store.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/stats_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('las estadísticas pintan con la paleta del tema', (tester) async {
    final stats = StatsStore.memory();
    addTearDown(stats.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexThemed(CyberHexPalette.light),
        home: StatsPage(stats: stats),
      ),
    );
    await tester.pumpAndSettle();

    final empty = tester.widget<Text>(
      find.text(
        'Todavía no hay nada que contar.\nDale al play y vuelve por aquí.',
      ),
    );
    expect(empty.style?.color, CyberHexPalette.light.muted);

    await tester.pumpWidget(const SizedBox());
  });
}
