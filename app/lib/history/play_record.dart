import 'dart:math' as math;

import '../audio/playback_controller.dart';
import '../audio/track.dart';

/// A random version-4 UUID. Every play gets one, so sending it twice can never count it twice.
String newUuid([math.Random? random]) {
  final r = random ?? math.Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) => b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// One song played, as kept in the listening history.
class PlayRecord {
  const PlayRecord({
    required this.id,
    required this.trackId,
    required this.source,
    required this.title,
    required this.artist,
    required this.startedAt,
    required this.listenedMs,
    required this.durationMs,
    required this.mode,
    required this.origin,
    required this.platform,
    this.album,
    this.genre,
    this.blended = false,
    this.mixedWithVyroId,
  });

  final String id;

  /// The Vyro song's id for catalog songs; a private identifier for songs on the device.
  final String trackId;

  /// vyro or local.
  final String source;
  final String title;
  final String artist;
  final String? album;
  final String? genre;
  final DateTime startedAt;
  final int listenedMs;
  final int durationMs;
  final String mode;
  final String origin;
  final String platform;

  /// This play ended by blending into another song.
  final bool blended;

  /// Set only when that other song is also on Vyro (the server only knows Vyro songs).
  final String? mixedWithVyroId;

  /// The same rule the server uses: 30 seconds, or half of a very short song.
  bool get isValidStream => listenedMs >= (durationMs > 0 ? math.min(30000, durationMs ~/ 2) : 30000);

  factory PlayRecord.fromEnded(PlayEnded e, {required String id, required String platform}) {
    final t = e.track;
    final onVyro = t.source == TrackSource.vyro;
    String? vyroId(Track x) => x.source == TrackSource.vyro && x.id.startsWith('vyro:') ? x.id.substring(5) : null;
    return PlayRecord(
      id: id,
      trackId: onVyro ? (vyroId(t) ?? t.id) : t.id,
      source: onVyro ? 'vyro' : 'local',
      title: t.title,
      artist: t.artist,
      album: t.album,
      genre: t.genre,
      startedAt: e.startedAt,
      listenedMs: e.listenedMs,
      durationMs: t.duration?.inMilliseconds ?? 0,
      mode: e.mode.name,
      origin: e.origin,
      platform: platform,
      blended: e.mixedInto != null,
      mixedWithVyroId: onVyro && e.mixedInto != null ? vyroId(e.mixedInto!) : null,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'trackId': trackId,
        'source': source,
        'title': title,
        'artist': artist,
        'album': album,
        'genre': genre,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'listenedMs': listenedMs,
        'durationMs': durationMs,
        'mode': mode,
        'origin': origin,
        'platform': platform,
        'blended': blended,
        'mixedWithVyroId': mixedWithVyroId,
      };

  factory PlayRecord.fromJson(Map<String, Object?> j) => PlayRecord(
        id: j['id'] as String,
        trackId: j['trackId'] as String,
        source: j['source'] as String,
        title: (j['title'] as String?) ?? '',
        artist: (j['artist'] as String?) ?? '',
        album: j['album'] as String?,
        genre: j['genre'] as String?,
        startedAt: DateTime.parse(j['startedAt'] as String),
        listenedMs: (j['listenedMs'] as num).toInt(),
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        mode: (j['mode'] as String?) ?? 'normal',
        origin: (j['origin'] as String?) ?? 'direct',
        platform: (j['platform'] as String?) ?? 'android',
        blended: j['blended'] == true,
        mixedWithVyroId: j['mixedWithVyroId'] as String?,
      );

  /// The shape the server accepts at POST /v1/events/listens.
  Map<String, Object?> toUpload() => {
        'id': id,
        'trackId': trackId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'listenedMs': listenedMs,
        'source': origin,
        'platform': platform,
        'mode': mode,
        if (mixedWithVyroId != null) 'mixedWithTrackId': mixedWithVyroId,
      };
}
