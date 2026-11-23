import 'package:cyberhex/core/favorites_store.dart';
import 'package:cyberhex/core/player_api.dart';
import 'package:cyberhex/core/player_controller.dart';
import 'package:cyberhex/theme.dart';
import 'package:cyberhex/ui/hex_cover.dart';
import 'package:cyberhex/ui/library_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player.dart';

/// Títulos cortos a propósito: `titleFromPath` es lo que usa la biblioteca.
final List<LibraryTrack> _songs = [
  LibraryTrack.fromPath('/m/Rock/Clásicos/Dos.mp3'),
  LibraryTrack.fromPath('/m/Rock/Clásicos/Uno.flac'),
  LibraryTrack.fromPath('/m/Jazz/Lento/Tres.ogg'),
  LibraryTrack.fromPath('/m/suelta.wav'),
];

FakePlayer _fakeWithLibrary() => FakePlayer()..library = _songs;

/// Monta la página con una biblioteca ya escaneada y un almacén de favoritos
/// sin disco.
Future<FavoritesStore> _pumpLibrary(
  WidgetTester tester, {
  PlayerController? controller,
  FavoritesStore? favorites,
  String? focusAlbum,
  int focusRequest = 0,
}) async {
  final fake = controller == null ? _fakeWithLibrary() : null;
  final player = controller ?? PlayerController(fake!);
  final store = favorites ?? FavoritesStore.memory();
  addTearDown(player.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildCyberHexTheme(),
      home: LibraryPage(
        controller: player,
        favorites: store,
        initialRoot: '/m',
        focusAlbum: focusAlbum,
        focusRequest: focusRequest,
      ),
    ),
  );
  // El escaneo es asíncrono aunque el doble responda al instante.
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('sin carpeta enseña la bienvenida y el botón de elegir', (
    tester,
  ) async {
    final controller = PlayerController(FakePlayer());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCyberHexTheme(),
        home: LibraryPage(
          controller: controller,
          favorites: FavoritesStore.memory(),
        ),
      ),
    );

    expect(find.text('Tu biblioteca'), findsOneWidget);
    expect(find.text('Elegir carpeta'), findsOneWidget);
    expect(find.text('Canciones'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lista las pistas escaneadas con su nombre y formato', (
    tester,
  ) async {
    await _pumpLibrary(tester);

    expect(find.text('Uno'), findsOneWidget);
    expect(find.text('Tres'), findsOneWidget);
    expect(find.text('suelta'), findsOneWidget);
    // Orden por título, sin distinguir mayúsculas: dos, suelta, tres, uno.
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(titles, ['Dos', 'suelta', 'Tres', 'Uno']);
    // El subtítulo lleva el formato en mayúsculas.
    expect(find.textContaining('FLAC'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la búsqueda filtra al escribir, sin tildes ni mayúsculas', (
    tester,
  ) async {
    await _pumpLibrary(tester);

    await tester.enterText(find.byType(TextField), 'CLASICOS');
    await tester.pumpAndSettle();

    expect(find.text('Uno'), findsOneWidget);
    expect(find.text('Dos'), findsOneWidget);
    expect(find.text('Tres'), findsNothing);
    expect(find.textContaining('2 de 4'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'jazz');
    await tester.pumpAndSettle();
    expect(find.text('Tres'), findsOneWidget);
    expect(find.text('Uno'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la pestaña de álbumes agrupa por carpeta', (tester) async {
    await _pumpLibrary(tester);

    await tester.tap(find.text('Álbumes'));
    await tester.pumpAndSettle();

    expect(find.text('Clásicos'), findsOneWidget);
    expect(find.text('Lento'), findsOneWidget);
    // Clásicos lleva dos pistas; Lento y la suelta, una cada uno.
    expect(find.text('2 pistas'), findsOneWidget);
    expect(find.text('1 pista'), findsNWidgets(2));
    expect(find.text('Sin álbum'), findsOneWidget);
    // Cada grupo lleva su carátula-emblema hexagonal.
    expect(find.byType(HexCover), findsNWidgets(3));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el foco de Inicio abre Álbumes filtrado por ese álbum', (
    tester,
  ) async {
    await _pumpLibrary(tester, focusAlbum: 'Clásicos', focusRequest: 1);

    expect(find.text('Clásicos'), findsWidgets);
    expect(find.text('Lento'), findsNothing);
    expect(find.text('Sin álbum'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('las carpetas y artistas salen de la jerarquía', (tester) async {
    await _pumpLibrary(tester);

    await tester.tap(find.text('Artistas'));
    await tester.pumpAndSettle();
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Jazz'), findsOneWidget);
    expect(find.text('Sin clasificar'), findsOneWidget);

    await tester.tap(find.text('Carpetas'));
    await tester.pumpAndSettle();
    expect(find.text('Rock/Clásicos'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('los favoritos se listan y se pueden marcar desde el menú', (
    tester,
  ) async {
    final store = await _pumpLibrary(tester);

    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Nada que mostrar con estos filtros'), findsOneWidget);

    // Vuelve a canciones y marca la primera desde su menú.
    await tester.tap(find.text('Canciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcar favorito'));
    await tester.pumpAndSettle();

    expect(store.contains('/m/Rock/Clásicos/Dos.mp3'), isTrue);

    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Dos'), findsOneWidget);
    expect(find.text('Uno'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('el menú añade a la cola y a reproducir siguiente', (
    tester,
  ) async {
    final fake = _fakeWithLibrary();
    final controller = PlayerController(fake);
    await _pumpLibrary(tester, controller: controller);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir a la cola'));
    await tester.pumpAndSettle();
    expect(fake.enqueueCalls, 1);
    expect(fake.queuePaths, ['/m/Rock/Clásicos/Dos.mp3']);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reproducir siguiente'));
    await tester.pumpAndSettle();
    expect(fake.playNextCalls, 1);
    expect(fake.queuePaths, [
      '/m/Rock/Clásicos/Dos.mp3',
      '/m/Rock/Clásicos/Dos.mp3',
    ]);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reproducir ahora abre la pista en el controlador', (
    tester,
  ) async {
    final fake = _fakeWithLibrary();
    final controller = PlayerController(fake);
    await _pumpLibrary(tester, controller: controller);

    await tester.tap(find.text('Tres'));
    await tester.pumpAndSettle();

    expect(fake.loadedPaths, ['/m/Jazz/Lento/Tres.ogg']);
    expect(controller.snapshot.hasTrack, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la ficha técnica enseña ruta, formato y duración', (
    tester,
  ) async {
    await _pumpLibrary(tester);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ficha técnica'));
    await tester.pumpAndSettle();

    expect(find.text('Formato'), findsOneWidget);
    expect(find.text('MP3'), findsOneWidget);
    expect(find.text('Ruta'), findsOneWidget);
    final path = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(path.data, '/m/Rock/Clásicos/Dos.mp3');
    expect(find.text('desconocida'), findsOneWidget);

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ocultar las pistas cortas solo descarta las que se sabe cortas', (
    tester,
  ) async {
    final fake = _fakeWithLibrary();
    final controller = PlayerController(fake);
    await _pumpLibrary(tester, controller: controller);

    // Aún no se sabe la duración de nada: el filtro no puede borrar la lista.
    await tester.tap(find.text('Ocultar < 30 s'));
    await tester.pumpAndSettle();
    expect(find.text('Uno'), findsOneWidget);
    expect(find.textContaining('4 de 4'), findsOneWidget);

    // Al sonar una pista corta, su duración se conoce y el filtro la esconde.
    fake
      ..hasTrack = true
      ..title = 'Dos'
      ..duration = 12;
    controller.enqueue('/m/Rock/Clásicos/Dos.mp3');
    controller.playAt(0);
    controller.pump();
    await tester.pumpAndSettle();

    // El título también lo pinta el mini reproductor, así que se mira la lista.
    expect(find.widgetWithText(ListTile, 'Dos'), findsNothing);
    expect(find.textContaining('3 de 4'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ordenar por duración no descarta pistas desconocidas', (
    tester,
  ) async {
    await _pumpLibrary(tester);

    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duración'));
    await tester.pumpAndSettle();

    // Sin duraciones conocidas el orden cae a título: la lista sigue entera.
    expect(find.byType(ListTile), findsNWidgets(4));

    await tester.pumpWidget(const SizedBox());
  });
}
