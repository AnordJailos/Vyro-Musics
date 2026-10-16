import 'dart:io';

import '../audio/track.dart';
import 'play_record.dart';

/// The songs the person played lately, newest first, each once: for "Continue listening". Plays under 10 seconds (an
/// accidental tap) are not counted, and songs on the device whose file is gone are left out.
Future<List<Track>> recentTracks(
  List<PlayRecord> records, {
  required Future<Uri> Function(String vyroId) streamUri,
  bool Function(String path)? fileExists,
  int limit = 10,
}) async {
  final exists = fileExists ?? (String path) => File(path).existsSync();
  final newestFirst = [...records]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final seen = <String>{};
  final out = <Track>[];
  for (final r in newestFirst) {
    if (out.length >= limit) break;
    if (r.listenedMs < 10000 || !seen.add('${r.source}:${r.trackId}')) continue;
    final duration = r.durationMs > 0 ? Duration(milliseconds: r.durationMs) : null;
    if (r.source == 'vyro') {
      out.add(Track(
        id: 'vyro:${r.trackId}',
        title: r.title,
        artist: r.artist,
        uri: Uri(scheme: 'vyro', path: r.trackId),
        source: TrackSource.vyro,
        duration: duration,
        album: r.album,
        genre: r.genre,
        resolveUri: () => streamUri(r.trackId),
      ));
    } else if (r.trackId.startsWith('local:')) {
      final path = r.trackId.substring(6);
      if (!exists(path)) continue;
      out.add(Track(id: r.trackId, title: r.title, artist: r.artist, uri: Uri.file(path), source: TrackSource.local, duration: duration, album: r.album, genre: r.genre));
    }
  }
  return out;
}
