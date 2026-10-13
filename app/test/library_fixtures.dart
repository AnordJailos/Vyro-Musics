import 'dart:io';

import 'package:vyro_music/library/library_models.dart';

File makeAudio(Directory dir, String relative, {int bytes = 10}) {
  return File('${dir.path}/$relative')
    ..createSync(recursive: true)
    ..writeAsBytesSync(List<int>.filled(bytes, 1));
}

/// Stands in for the tag reader: returns the tags registered for a file name.
class FakeTagReader {
  final Map<String, TagInfo> byFileName = {};
  int reads = 0;

  Future<List<TagInfo?>> call(List<String> paths) async {
    reads += paths.length;
    return [for (final p in paths) byFileName[p.split(RegExp(r'[\\/]')).last]];
  }
}

LibraryTrack libTrack(String title, {String artist = 'Artist', String album = 'Album', int number = 0, String? path}) => LibraryTrack(
      id: 'local:${path ?? '/music/$title.mp3'}',
      path: path ?? '/music/$title.mp3',
      title: title,
      artist: artist,
      album: album,
      genre: 'Pop',
      durationMs: 180000,
      trackNumber: number,
      year: 2026,
      sizeBytes: 10,
      modifiedMs: 1,
      addedMs: 1,
    );
