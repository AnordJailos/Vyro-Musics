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
    this.hasLyrics = false,
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
  final bool hasLyrics;

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
      hasLyrics: j['hasLyrics'] == true,
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
        genre: genre,
        resolveUri: () => streamUri(id),
      );
}

/// A row of suggestions on the Home screen: picked for you, popular where you are, or a list chosen by Vyro's staff.
class RecSection {
  const RecSection({required this.id, required this.kind, required this.title, required this.reason, required this.tracks});

  final String id;

  /// for_you, popular or editorial.
  final String kind;
  final String title;

  /// Why these songs are here, in plain words.
  final String reason;
  final List<CatalogTrack> tracks;

  factory RecSection.fromJson(Map<String, Object?> j) => RecSection(
        id: j['id'] as String,
        kind: (j['kind'] as String?) ?? 'editorial',
        title: j['title'] as String,
        reason: (j['reason'] as String?) ?? '',
        tracks: [for (final t in (j['tracks'] as List)) CatalogTrack.fromJson((t as Map).cast<String, Object?>())],
      );
}

class ArtistSummary {
  const ArtistSummary({required this.id, required this.stageName, this.verified = false, this.followers = 0});

  final String id;
  final String stageName;
  final bool verified;
  final int followers;

  factory ArtistSummary.fromJson(Map<String, Object?> j) => ArtistSummary(
        id: j['id'] as String,
        stageName: j['stageName'] as String,
        verified: j['verified'] == true,
        followers: (j['followers'] as num?)?.toInt() ?? 0,
      );
}

class SearchResults {
  const SearchResults({this.artists = const [], this.tracks = const []});

  final List<ArtistSummary> artists;
  final List<CatalogTrack> tracks;
}

/// Something to offer while the person is still typing.
class Suggestion {
  const Suggestion({required this.kind, required this.id, required this.text, this.subtitle = ''});

  /// artist or song.
  final String kind;
  final String id;
  final String text;
  final String subtitle;

  bool get isArtist => kind == 'artist';

  factory Suggestion.fromJson(Map<String, Object?> j) => Suggestion(kind: j['kind'] as String, id: j['id'] as String, text: j['text'] as String, subtitle: (j['subtitle'] as String?) ?? '');
}

class GenreCount {
  const GenreCount(this.genre, this.count);

  final String genre;
  final int count;
}

class ArtistLink {
  const ArtistLink({required this.label, required this.url});

  final String label;
  final String url;
}

class ArtistPageData {
  const ArtistPageData({
    required this.artist,
    this.bio = '',
    this.genres = const [],
    this.links = const [],
    this.monthlyListeners = 0,
    this.following = false,
    this.topTracks = const [],
    this.discography = const [],
    this.similar = const [],
  });

  final ArtistSummary artist;
  final String bio;
  final List<String> genres;
  final List<ArtistLink> links;
  final int monthlyListeners;
  final bool following;
  final List<CatalogTrack> topTracks;
  final List<CatalogTrack> discography;
  final List<ArtistSummary> similar;

  ArtistPageData withFollowing(bool value) => ArtistPageData(
        artist: ArtistSummary(id: artist.id, stageName: artist.stageName, verified: artist.verified, followers: artist.followers + (value == following ? 0 : (value ? 1 : -1))),
        bio: bio,
        genres: genres,
        links: links,
        monthlyListeners: monthlyListeners,
        following: value,
        topTracks: topTracks,
        discography: discography,
        similar: similar,
      );

  factory ArtistPageData.fromJson(Map<String, Object?> j) {
    Map<String, Object?> map(Object? o) => (o as Map).cast<String, Object?>();
    final a = map(j['artist']);
    return ArtistPageData(
      artist: ArtistSummary.fromJson(a),
      bio: (a['bio'] as String?) ?? '',
      genres: [for (final g in (a['genres'] as List? ?? const [])) '$g'],
      links: [
        for (final l in (a['links'] as List? ?? const []))
          if (l is Map) ArtistLink(label: '${l['label'] ?? l['name'] ?? l['type'] ?? ''}', url: '${l['url'] ?? ''}') else ArtistLink(label: '', url: '$l'),
      ],
      monthlyListeners: (a['monthlyListeners'] as num?)?.toInt() ?? 0,
      following: j['following'] == true,
      topTracks: [for (final t in (j['topTracks'] as List? ?? const [])) CatalogTrack.fromJson(map(t))],
      discography: [for (final t in (j['discography'] as List? ?? const [])) CatalogTrack.fromJson(map(t))],
      similar: [for (final x in (j['similar'] as List? ?? const [])) ArtistSummary.fromJson(map(x))],
    );
  }
}

class ArtistChartEntry {
  const ArtistChartEntry({required this.rank, required this.artist, required this.plays, this.change});

  final int rank;
  final ArtistSummary artist;
  final int plays;

  /// For rising artists: how many more plays than the week before.
  final int? change;

  factory ArtistChartEntry.fromJson(Map<String, Object?> j) => ArtistChartEntry(
        rank: (j['rank'] as num).toInt(),
        artist: ArtistSummary.fromJson(j),
        plays: (j['plays'] as num?)?.toInt() ?? 0,
        change: (j['change'] as num?)?.toInt(),
      );
}
