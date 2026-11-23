import 'package:cyberhex/core/library_browse.dart';
import 'package:cyberhex/core/player_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LibraryTrack track(String path) => LibraryTrack.fromPath(path);

  test('agrupa por carpeta de álbum y deduce el artista', () {
    final albums = albumsFromTracks(<LibraryTrack>[
      track('/m/Radiohead/In Rainbows/01.flac'),
      track('/m/Radiohead/In Rainbows/02.flac'),
      track('/m/Radiohead/Kid A/01.flac'),
      track('/m/Björk/Homogenic/01.flac'),
    ]);

    expect(albums, hasLength(3));
    final rainbows = albums.firstWhere((a) => a.name == 'In Rainbows');
    expect(rainbows.artist, 'Radiohead');
    expect(rainbows.count, 2);
    expect(rainbows.tracks, hasLength(2));
    expect(albums.map((a) => a.name), ['Homogenic', 'In Rainbows', 'Kid A']);
  });

  test('una biblioteca de un solo álbum no lo deja como «Sin álbum»', () {
    final albums = albumsFromTracks(<LibraryTrack>[
      track('/m/Artista/Único/01.mp3'),
      track('/m/Artista/Único/02.mp3'),
    ]);

    expect(albums, hasLength(1));
    expect(albums.single.name, 'Único');
    expect(albums.single.artist, 'Artista');
  });

  test('las pistas sueltas en la raíz quedan en «Sin álbum»', () {
    final albums = albumsFromTracks(<LibraryTrack>[
      track('/m/suelta.flac'),
      track('/m/Artista/Álbum/01.flac'),
    ]);

    expect(albums.map((a) => a.name), contains('Sin álbum'));
    expect(albums.map((a) => a.name), contains('Álbum'));
  });

  test('una lista vacía devuelve vacío', () {
    expect(albumsFromTracks(const <LibraryTrack>[]), isEmpty);
  });
}
