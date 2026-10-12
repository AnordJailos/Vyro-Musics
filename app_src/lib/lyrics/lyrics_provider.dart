import 'dart:convert';
import 'dart:io';

import '../audio/track.dart';
import '../catalog/catalog_api.dart';
import 'lyrics_models.dart';

typedef TextReader = Future<String?> Function(String path);

/// Reads a small text file, tolerating odd encodings. Null when there is no such file.
Future<String?> readTextFile(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > 512 * 1024) return null; // not a lyrics file
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

class _Entry {
  _Entry(this.lyrics, this.at);
  final Lyrics? lyrics;
  final DateTime at;
}

/// Finds the lyrics for whatever is playing: from Vyro for catalog songs; for songs on the device, from a .lrc or
/// .txt file with the same name next to the song, or from lyrics embedded in the file's tags.
class LyricsProvider {
  LyricsProvider({required this.catalog, this.embedded, TextReader? readText, DateTime Function()? clock, this.cacheFor = const Duration(minutes: 5)})
      : _readText = readText ?? readTextFile,
        _clock = clock ?? DateTime.now;

  final CatalogApi catalog;

  /// Reads lyrics stored inside an audio file.
  final TextReader? embedded;
  final TextReader _readText;
  final DateTime Function() _clock;
  final Duration cacheFor;
  final Map<String, _Entry> _cache = {};

  /// The lyrics, or null when the song has none. Throws when Vyro cannot be reached (so the screen can offer a retry).
  Future<Lyrics?> lyricsFor(Track track) async {
    final cached = _cache[track.id];
    if (cached != null && _clock().difference(cached.at) < cacheFor) return cached.lyrics;
    final found = await _lookup(track);
    _cache[track.id] = _Entry(found, _clock());
    return found;
  }

  /// Tells Vyro (and through it the artist) that the lyrics of a song are wrong.
  Future<void> report(Track track, String reason) async {
    if (track.source != TrackSource.vyro) return;
    await catalog.reportLyrics(track.id.startsWith('vyro:') ? track.id.substring(5) : track.id, reason: reason);
  }

  Future<Lyrics?> _lookup(Track track) async {
    switch (track.source) {
      case TrackSource.vyro:
        return catalog.lyrics(track.id.startsWith('vyro:') ? track.id.substring(5) : track.id);
      case TrackSource.local:
        return _local(track);
      default:
        return null;
    }
  }

  Future<Lyrics?> _local(Track track) async {
    if (track.uri.scheme != 'file') return null;
    final path = track.uri.toFilePath();
    final base = path.replaceFirst(RegExp(r'\.[^./\\]+$'), '');
    for (final ext in const ['.lrc', '.LRC', '.txt']) {
      final text = await _readText('$base$ext');
      if (text == null) continue;
      final parsed = parseLyrics(text);
      if (!parsed.isEmpty) return parsed;
    }
    final inside = await embedded?.call(path);
    if (inside != null) {
      final parsed = parseLyrics(inside);
      if (!parsed.isEmpty) return parsed;
    }
    return null;
  }
}
