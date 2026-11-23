import 'dart:convert';
import 'dart:io';

import 'package:cyberhex/core/home_tab_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late File file;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cyberhex-tab');
    file = File('${temp.path}/home_tab.json');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('guarda la pestaña y la recupera en otra instancia', () async {
    final store = HomeTabStore(file: file);
    store.setTab(3);
    await store.save();

    final copy = HomeTabStore(file: file);
    await copy.load();

    expect(copy.tab, 3);
  });

  test('un índice fuera de rango se recorta a la última pestaña', () async {
    await file.writeAsString(jsonEncode(<String, Object?>{'tab': 99}));

    final store = HomeTabStore(file: file);
    await store.load();

    expect(store.tab, HomeTabStore.tabCount - 1);
  });

  test('un JSON roto cae en Inicio sin lanzar', () async {
    await file.writeAsString('{no es json');

    final store = HomeTabStore(file: file);
    await store.load();

    expect(store.tab, 0);
  });
}
