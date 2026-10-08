import '../audio/track.dart';

/// A song in the Vyro catalog, as the server describes it.
class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.title,
    required this.artistId,
    required this.artistName,
    required this.durationMs,
    this.genre = 'other',
    this.explicit = false,
    this.allowMixing = true,
    this.loudnessLufs,
    this.coverPath,
    this.rank,
    this.plays,
  });

  final String id;
  final String title;
  final String artistId;
  final String artistName;
  final int durationMs;
  final String genre;
  final bool explicit;
  final bool allowMixing;
  final double? loudnessLufs;
  final String? coverPath;

  /// Only on charts.
  final int? rank;
  final int? plays;

  factory CatalogTrack.fromJson(Map<String, Object?> j) {
    final artist = (j['artist'] as Map).cast<String, Object?>();
    return CatalogTrack(
      id: j['id'] as String,
      title: j['title'] as String,
      artistId: artist['id'] as String,
      artistName: artist['stageName'] as String,
      durationMs: (j['durationMs'] as num).toInt(),
      genre: (j['genre'] as String?) ?? 'other',
      explicit: j['explicit'] == true,
      allowMixing: j['allowMixing'] != false,
      loudnessLufs: (j['loudnessLufs'] as num?)?.toDouble(),
      coverPath: j['coverUrl'] as String?,
      rank: (j['rank'] as num?)?.toInt(),
      plays: (j['plays'] as num?)?.toInt(),
    );
  }

  /// The playable form. The stream address is asked for at play time, because it is short-lived.
  Track toPlayable(Future<Uri> Function(String trackId) streamUri) => Track(
        id: 'vyro:$id',
        title: title,
        artist: artistName,
        uri: Uri(scheme: 'vyro', path: id),
        source: TrackSource.vyro,
        duration: Duration(milliseconds: durationMs),
        allowMixing: allowMixing,
        loudnessLufs: loudnessLufs,
        resolveUri: () => streamUri(id),
      );
}
