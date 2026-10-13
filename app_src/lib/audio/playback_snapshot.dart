import 'playback_controller.dart';
import 'track.dart';

Map<String, Object?> trackToJson(Track t) => {
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'uri': t.uri.toString(),
      'source': t.source.name,
      'durationMs': t.duration?.inMilliseconds,
      'allowMixing': t.allowMixing,
      'loudnessLufs': t.loudnessLufs,
      'album': t.album,
      'genre': t.genre,
      'countsAsListening': t.countsAsListening,
    };

/// A song read back from a save. Songs from Vyro have no way to find their address yet: the caller adds it.
Track trackFromJson(Map<String, Object?> j) {
  final ms = (j['durationMs'] as num?)?.toInt();
  return Track(
    id: j['id'] as String,
    title: (j['title'] as String?) ?? '',
    artist: (j['artist'] as String?) ?? '',
    uri: Uri.parse(j['uri'] as String),
    source: TrackSource.values.firstWhere((s) => s.name == j['source'], orElse: () => TrackSource.local),
    duration: ms == null ? null : Duration(milliseconds: ms),
    allowMixing: j['allowMixing'] != false,
    loudnessLufs: (j['loudnessLufs'] as num?)?.toDouble(),
    album: j['album'] as String?,
    genre: j['genre'] as String?,
    countsAsListening: j['countsAsListening'] != false,
  );
}

/// The state of the player that is worth keeping across restarts: the queue, where in it, and where in the song.
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.queue,
    required this.ids,
    required this.originalIds,
    required this.index,
    required this.position,
    required this.shuffle,
    required this.repeat,
    required this.mode,
    required this.autoSeconds,
    required this.manualSeconds,
    required this.origin,
  });

  final List<Track> queue;
  final List<int> ids;
  final List<int> originalIds;
  final int index;
  final Duration position;
  final bool shuffle;
  final RepeatMode repeat;
  final PlaybackMode mode;
  final double autoSeconds;
  final double manualSeconds;
  final String origin;

  Map<String, Object?> toJson() => {
        'version': 1,
        'queue': [for (final t in queue) trackToJson(t)],
        'ids': ids,
        'originalIds': originalIds,
        'index': index,
        'positionMs': position.inMilliseconds,
        'shuffle': shuffle,
        'repeat': repeat.name,
        'mode': mode.name,
        'autoSeconds': autoSeconds,
        'manualSeconds': manualSeconds,
        'origin': origin,
      };

  /// Reads a save. [attach] gives each song back whatever it needs to be played (for Vyro songs, a way to ask
  /// for a fresh address). Throws a [FormatException] for a save that does not make sense.
  factory PlaybackSnapshot.fromJson(Map<String, Object?> j, {Track Function(Track)? attach}) {
    try {
      final queue = [for (final t in (j['queue'] as List)) (attach ?? (x) => x)(trackFromJson((t as Map).cast<String, Object?>()))];
      final ids = [for (final i in (j['ids'] as List)) (i as num).toInt()];
      final originalIds = [for (final i in (j['originalIds'] as List? ?? const [])) (i as num).toInt()];
      if (ids.length != queue.length) throw const FormatException('queue and ids do not match');
      return PlaybackSnapshot(
        queue: queue,
        ids: ids,
        originalIds: originalIds,
        index: (j['index'] as num).toInt(),
        position: Duration(milliseconds: ((j['positionMs'] as num?)?.toInt() ?? 0).clamp(0, 1 << 40)),
        shuffle: j['shuffle'] == true,
        repeat: RepeatMode.values.firstWhere((r) => r.name == j['repeat'], orElse: () => RepeatMode.off),
        mode: PlaybackMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => PlaybackMode.normal),
        autoSeconds: (j['autoSeconds'] as num?)?.toDouble() ?? 6,
        manualSeconds: (j['manualSeconds'] as num?)?.toDouble() ?? 3,
        origin: (j['origin'] as String?) ?? 'direct',
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('unreadable playback state: $e');
    }
  }
}
