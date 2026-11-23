import 'player_api.dart';

/// Álbum deducido de la jerarquía de carpetas de la biblioteca.
///
/// El núcleo entrega rutas sin etiquetas, así que se usa la misma heurística
/// que la pestaña Álbumes de la biblioteca:
/// `<raíz>/Artista/Álbum/pista.flac` → artista es la carpeta de encima y álbum
/// la de la pista. La raíz se calcula como prefijo común de todas las rutas.
class LibraryAlbum {
  const LibraryAlbum({
    required this.name,
    required this.artist,
    required this.tracks,
  });

  final String name;
  final String artist;
  final List<LibraryTrack> tracks;

  int get count => tracks.length;

  /// Texto estable para la carátula hexagonal.
  String get seed => artist.isEmpty ? name : '$artist · $name';
}

/// Agrupa las pistas por carpeta de álbum. No toca disco ni el motor.
List<LibraryAlbum> albumsFromTracks(Iterable<LibraryTrack> tracks) {
  final list = tracks.toList();
  if (list.isEmpty) return const <LibraryAlbum>[];

  final segments = <List<String>>[
    for (final track in list) _segments(track.directory),
  ];
  var common = segments.first;
  for (final other in segments.skip(1)) {
    var shared = 0;
    while (shared < common.length &&
        shared < other.length &&
        common[shared] == other[shared]) {
      shared++;
    }
    common = common.sublist(0, shared);
  }
  // Si todo vive en la misma carpeta, esa carpeta es el álbum: se retrocede
  // un nivel para no dejarlo todo como «Sin álbum».
  if (common.isNotEmpty &&
      segments.every((parts) => _sameSegments(parts, common))) {
    common = common.sublist(0, common.length - 1);
  }

  final groups = <String, List<LibraryTrack>>{};
  final names = <String, String>{};
  final artists = <String, String>{};
  for (var i = 0; i < list.length; i++) {
    final parts = segments[i];
    final relative = parts.length > common.length
        ? parts.sublist(common.length)
        : const <String>[];
    final name = relative.isEmpty ? 'Sin álbum' : relative.last;
    final artist = relative.isEmpty || parts.length < 2
        ? ''
        : parts[parts.length - 2];
    final key = '${artist.toLowerCase()}\u0000${name.toLowerCase()}';
    (groups[key] ??= <LibraryTrack>[]).add(list[i]);
    names[key] = name;
    artists[key] = artist;
  }

  final albums =
      <LibraryAlbum>[
        for (final entry in groups.entries)
          LibraryAlbum(
            name: names[entry.key] ?? 'Sin álbum',
            artist: artists[entry.key] ?? '',
            tracks: List<LibraryTrack>.unmodifiable(entry.value),
          ),
      ]..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (byName != 0) return byName;
        return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      });
  return List<LibraryAlbum>.unmodifiable(albums);
}

List<String> _segments(String directory) => <String>[
  for (final part in directory.replaceAll('\\', '/').split('/'))
    if (part.isNotEmpty) part,
];

bool _sameSegments(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
