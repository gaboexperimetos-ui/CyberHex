import 'library_browse.dart';
import 'player_api.dart';
import 'stats_store.dart';
import 'text_search.dart';

/// Una fila de la búsqueda global: una pista de la biblioteca o del historial.
class SearchHit {
  const SearchHit({
    required this.path,
    required this.title,
    required this.subtitle,
    this.recent = false,
  });

  final String path;
  final String title;
  final String subtitle;

  /// Ya sonó alguna vez: viene del historial y va antes que el resto.
  final bool recent;

  /// Texto estable para la carátula hexagonal.
  String get seed => subtitle.isEmpty ? title : '$title · $subtitle';
}

/// Busca en la biblioteca escaneada y en el historial, sin tocar disco.
///
/// Ordena primero las coincidencias del historial (lo que el oyente ya conoce)
/// y después el resto de la biblioteca por título. Con la consulta vacía
/// devuelve lo reciente para que la hoja no arranque en blanco. La búsqueda es
/// insensible a mayúsculas y tildes, y mira título, artista y álbum.
List<SearchHit> searchHits({
  required String query,
  required Iterable<LibraryTrack> library,
  required Iterable<HistoryEntry> history,
  int limit = 40,
}) {
  if (limit <= 0) return const <SearchHit>[];
  final needle = normalizeForSearch(query.trim());
  final albums = albumsFromTracks(library);
  final meta = <String, ({String album, String artist})>{};
  for (final album in albums) {
    for (final track in album.tracks) {
      meta[track.path] = (album: album.name, artist: album.artist);
    }
  }

  final seen = <String>{};
  final recents = <SearchHit>[];
  for (final entry in history) {
    if (entry.path.isEmpty) continue;
    final info = meta[entry.path];
    final title = entry.label;
    final artist = entry.artist.isNotEmpty
        ? entry.artist
        : (info?.artist ?? '');
    if (!_matches(needle, title, artist, info?.album ?? '')) continue;
    if (!seen.add(entry.path)) continue;
    recents.add(
      SearchHit(path: entry.path, title: title, subtitle: artist, recent: true),
    );
    if (recents.length >= limit) break;
  }

  final rest = <SearchHit>[];
  for (final track in library) {
    if (seen.contains(track.path)) continue;
    final info = meta[track.path];
    final artist = info?.artist ?? '';
    final album = info?.album ?? '';
    if (!_matches(needle, track.title, artist, album)) continue;
    rest.add(
      SearchHit(
        path: track.path,
        title: track.title,
        subtitle: <String>[
          if (artist.isNotEmpty) artist,
          if (album.isNotEmpty && album != 'Sin álbum') album,
        ].join(' · '),
      ),
    );
    if (rest.length >= limit) break;
  }
  rest.sort(
    (a, b) =>
        normalizeForSearch(a.title).compareTo(normalizeForSearch(b.title)),
  );
  final all = <SearchHit>[...recents, ...rest];
  return all.length > limit ? all.sublist(0, limit) : all;
}

bool _matches(String needle, String title, String artist, String album) {
  if (needle.isEmpty) return true;
  return normalizeForSearch(title).contains(needle) ||
      normalizeForSearch(artist).contains(needle) ||
      normalizeForSearch(album).contains(needle);
}
