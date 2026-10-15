import 'library_models.dart';

int _compare(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

List<LibraryTrack> sortedSongs(List<LibraryTrack> tracks) => [...tracks]..sort((a, b) => _compare(a.title, b.title));

/// Every word typed must appear in the title, artist or album.
List<LibraryTrack> searchTracks(List<LibraryTrack> tracks, String query) {
  final terms = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (terms.isEmpty) return tracks;
  return [
    for (final t in tracks)
      if (terms.every((term) => '${t.title} ${t.artist} ${t.album}'.toLowerCase().contains(term))) t,
  ];
}

class AlbumGroup {
  const AlbumGroup(this.name, this.artist, this.tracks);
  final String name;
  final String artist;
  final List<LibraryTrack> tracks;
}

class ArtistGroup {
  const ArtistGroup(this.name, this.tracks);
  final String name;
  final List<LibraryTrack> tracks;
}

List<AlbumGroup> albumsOf(List<LibraryTrack> tracks) {
  final groups = <String, List<LibraryTrack>>{};
  for (final t in tracks) {
    groups.putIfAbsent(t.album.toLowerCase(), () => []).add(t);
  }
  final result = <AlbumGroup>[];
  for (final list in groups.values) {
    list.sort((a, b) {
      final byNumber = a.trackNumber.compareTo(b.trackNumber);
      return byNumber != 0 ? byNumber : _compare(a.title, b.title);
    });
    final artists = {for (final t in list) t.artist};
    result.add(AlbumGroup(list.first.album, artists.length == 1 ? artists.first : 'Various artists', list));
  }
  result.sort((a, b) => _compare(a.name, b.name));
  return result;
}

List<ArtistGroup> artistsOf(List<LibraryTrack> tracks) {
  final groups = <String, List<LibraryTrack>>{};
  for (final t in tracks) {
    groups.putIfAbsent(t.artist.toLowerCase(), () => []).add(t);
  }
  final result = [
    for (final list in groups.values) ArtistGroup(list.first.artist, [...list]..sort((a, b) => _compare(a.title, b.title))),
  ];
  result.sort((a, b) => _compare(a.name, b.name));
  return result;
}

class GenreGroup {
  const GenreGroup(this.name, this.tracks);
  final String name;
  final List<LibraryTrack> tracks;
}

class FolderGroup {
  const FolderGroup(this.path, this.name, this.tracks);

  /// The full folder, and just its last part for showing in a list.
  final String path;
  final String name;
  final List<LibraryTrack> tracks;
}

bool _unknown(String genre) => genre.toLowerCase().startsWith('unknown');

List<GenreGroup> genresOf(List<LibraryTrack> tracks) {
  final groups = <String, List<LibraryTrack>>{};
  for (final t in tracks) {
    groups.putIfAbsent(t.genre.toLowerCase(), () => []).add(t);
  }
  final result = [
    for (final list in groups.values) GenreGroup(list.first.genre, [...list]..sort((a, b) => _compare(a.title, b.title))),
  ];
  // Songs with no genre go last.
  result.sort((a, b) => _unknown(a.name) != _unknown(b.name) ? (_unknown(a.name) ? 1 : -1) : _compare(a.name, b.name));
  return result;
}

/// The folder a file is in, whichever way the device writes paths.
String folderOf(String path) {
  final p = path.replaceAll('\\', '/');
  final i = p.lastIndexOf('/');
  return i <= 0 ? p : p.substring(0, i);
}

List<FolderGroup> foldersOf(List<LibraryTrack> tracks) {
  final groups = <String, List<LibraryTrack>>{};
  for (final t in tracks) {
    groups.putIfAbsent(folderOf(t.path).toLowerCase(), () => []).add(t);
  }
  final result = [
    for (final list in groups.values)
      () {
        final path = folderOf(list.first.path);
        final name = path.split('/').lastWhere((x) => x.isNotEmpty, orElse: () => path);
        return FolderGroup(path, name, [...list]..sort((a, b) => _compare(a.title, b.title)));
      }(),
  ];
  result.sort((a, b) => _compare(a.name, b.name));
  return result;
}
