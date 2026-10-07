import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import 'library_models.dart';

String? _clean(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

TagInfo? _readOne(String path) {
  try {
    final m = readMetadata(File(path), getImage: false);
    var genre = '';
    try {
      genre = m.genres.isEmpty ? '' : m.genres.first;
    } catch (_) {}
    return TagInfo(
      title: _clean(m.title),
      artist: _clean(m.artist),
      album: _clean(m.album),
      genre: _clean(genre),
      duration: m.duration,
      trackNumber: m.trackNumber,
      year: m.year?.year,
    );
  } catch (_) {
    return null; // unreadable tags: the scanner falls back to the file name
  }
}

/// Reads tags in a background isolate so scanning never freezes the screen.
Future<List<TagInfo?>> readTagsInIsolate(List<String> paths) {
  return Isolate.run(() => [for (final p in paths) _readOne(p)]);
}
