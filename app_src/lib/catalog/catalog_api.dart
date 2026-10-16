import '../auth/api_client.dart';
import '../auth/api_errors.dart';
import '../lyrics/lyrics_models.dart';
import 'catalog_models.dart';

/// Browsing and playing songs from the Vyro catalog. Guests can use all of it.
abstract class CatalogApi {
  Future<List<CatalogTrack>> newReleases();
  Future<List<CatalogTrack>> search(String query);
  Future<List<CatalogTrack>> charts({String range = '7d', String? country});

  /// A short-lived address the player can open.
  Future<Uri> streamUri(String trackId);

  /// The full address of a cover picture.
  Uri coverUri(String coverPath);

  /// The lyrics of a song, or null when it has none.
  Future<Lyrics?> lyrics(String trackId);

  /// Tells the artist that something is wrong with the lyrics.
  Future<void> reportLyrics(String trackId, {String reason = 'other'});

  /// Suggestions for the Home screen.
  Future<List<RecSection>> recommendations();

  /// "Not interested": [kind] is track or artist.
  Future<void> notInterested({required String kind, required String id});

  /// Forgets the "not interested" choices and the taste picks.
  Future<void> resetRecommendations();

  /// The songs the signed-in person liked, newest first.
  Future<List<CatalogTrack>> savedTracks();
  Future<void> saveTrack(String trackId);
  Future<void> unsaveTrack(String trackId);

  /// Search that forgives typos and finds artists as well as songs.
  Future<SearchResults> searchAll(String query);

  /// What to offer while the person is still typing.
  Future<List<Suggestion>> suggest(String query);

  Future<List<GenreCount>> genres();

  /// Songs of a genre: [sort] is new or popular.
  Future<List<CatalogTrack>> genreTracks(String genre, {String sort = 'new'});

  Future<ArtistPageData> artistPage(String artistId);

  /// Top or rising artists, worldwide or for one country.
  Future<List<ArtistChartEntry>> artistChart({String kind = 'top', String? country});

  Future<void> followArtist(String artistId);
  Future<void> unfollowArtist(String artistId);
}

Map<String, Object?> _map(Object? v) => (v as Map).cast<String, Object?>();

class HttpCatalogApi implements CatalogApi {
  HttpCatalogApi(this._client);

  final ApiClient _client;

  Future<List<CatalogTrack>> _list(Future<Object?> call) async {
    final m = _map(await call);
    return [for (final t in (m['tracks'] as List)) CatalogTrack.fromJson(_map(t))];
  }

  @override
  Future<List<CatalogTrack>> newReleases() => _list(_client.send('GET', '/v1/catalog/new'));

  @override
  Future<List<CatalogTrack>> search(String query) => _list(_client.send('GET', '/v1/catalog/search', query: {'q': query}));

  @override
  Future<List<CatalogTrack>> charts({String range = '7d', String? country}) =>
      _list(_client.send('GET', '/v1/catalog/charts', query: {'range': range, if (country != null) 'country': country}));

  @override
  Future<Uri> streamUri(String trackId) async {
    final m = _map(await _client.send('GET', '/v1/tracks/$trackId/stream-url'));
    return _client.baseUrl.replace(path: m['url'] as String);
  }

  @override
  Uri coverUri(String coverPath) => _client.baseUrl.replace(path: coverPath);

  @override
  Future<Lyrics?> lyrics(String trackId) async {
    try {
      final m = _map(await _client.send('GET', '/v1/tracks/$trackId/lyrics'));
      return Lyrics(
        synced: m['synced'] == true,
        lines: [for (final l in (m['lines'] as List)) LyricLine((_map(l)['timeMs'] as num?)?.toInt(), (_map(l)['text'] as String?) ?? '')],
      );
    } on ApiException catch (e) {
      if (e.status == 404) return null; // the song simply has no lyrics
      rethrow;
    }
  }

  @override
  Future<void> reportLyrics(String trackId, {String reason = 'other'}) async {
    await _client.send('POST', '/v1/tracks/$trackId/lyrics/report', body: {'reason': reason});
  }

  @override
  Future<List<RecSection>> recommendations() async {
    final m = _map(await _client.send('GET', '/v1/recommendations/home'));
    return [for (final s in (m['sections'] as List)) RecSection.fromJson(_map(s))];
  }

  @override
  Future<void> notInterested({required String kind, required String id}) async {
    await _client.send('POST', '/v1/recommendations/not-interested', body: {'kind': kind, 'id': id});
  }

  @override
  Future<void> resetRecommendations() async {
    await _client.send('DELETE', '/v1/recommendations');
  }

  @override
  Future<List<CatalogTrack>> savedTracks() async {
    final m = _map(await _client.send('GET', '/v1/me/saves'));
    return [for (final t in (m['tracks'] as List)) CatalogTrack.fromJson(_map(t))];
  }

  @override
  Future<void> saveTrack(String trackId) async {
    await _client.send('POST', '/v1/tracks/$trackId/save');
  }

  @override
  Future<void> unsaveTrack(String trackId) async {
    await _client.send('DELETE', '/v1/tracks/$trackId/save');
  }

  @override
  Future<SearchResults> searchAll(String query) async {
    final m = _map(await _client.send('GET', '/v1/search', query: {'q': query}));
    return SearchResults(
      artists: [for (final a in (m['artists'] as List)) ArtistSummary.fromJson(_map(a))],
      tracks: [for (final t in (m['tracks'] as List)) CatalogTrack.fromJson(_map(t))],
    );
  }

  @override
  Future<List<Suggestion>> suggest(String query) async {
    final m = _map(await _client.send('GET', '/v1/search/suggest', query: {'q': query}));
    return [for (final x in (m['suggestions'] as List)) Suggestion.fromJson(_map(x))];
  }

  @override
  Future<List<GenreCount>> genres() async {
    final m = _map(await _client.send('GET', '/v1/browse/genres'));
    return [for (final g in (m['genres'] as List)) GenreCount(_map(g)['genre'] as String, (_map(g)['count'] as num).toInt())];
  }

  @override
  Future<List<CatalogTrack>> genreTracks(String genre, {String sort = 'new'}) => _list(_client.send('GET', '/v1/browse/genres/${Uri.encodeComponent(genre)}', query: {'sort': sort}));

  @override
  Future<ArtistPageData> artistPage(String artistId) async => ArtistPageData.fromJson(_map(await _client.send('GET', '/v1/artists/$artistId/page')));

  @override
  Future<List<ArtistChartEntry>> artistChart({String kind = 'top', String? country}) async {
    final m = _map(await _client.send('GET', '/v1/charts/artists', query: {'kind': kind, if (country != null) 'country': country}));
    return [for (final a in (m['artists'] as List)) ArtistChartEntry.fromJson(_map(a))];
  }

  @override
  Future<void> followArtist(String artistId) async {
    await _client.send('POST', '/v1/artists/$artistId/follow');
  }

  @override
  Future<void> unfollowArtist(String artistId) async {
    await _client.send('DELETE', '/v1/artists/$artistId/follow');
  }
}

/// Used where there is no server (tests, previews): the catalog is simply empty.
class EmptyCatalogApi implements CatalogApi {
  const EmptyCatalogApi();

  @override
  Future<List<CatalogTrack>> newReleases() async => const [];

  @override
  Future<List<CatalogTrack>> search(String query) async => const [];

  @override
  Future<List<CatalogTrack>> charts({String range = '7d', String? country}) async => const [];

  @override
  Future<Uri> streamUri(String trackId) async => throw const ApiException(0, 'network');

  @override
  Uri coverUri(String coverPath) => Uri.parse(coverPath);

  @override
  Future<Lyrics?> lyrics(String trackId) async => null;

  @override
  Future<void> reportLyrics(String trackId, {String reason = 'other'}) async {}

  @override
  Future<List<RecSection>> recommendations() async => const [];

  @override
  Future<void> notInterested({required String kind, required String id}) async {}

  @override
  Future<void> resetRecommendations() async {}

  @override
  Future<List<CatalogTrack>> savedTracks() async => const [];

  @override
  Future<void> saveTrack(String trackId) async {}

  @override
  Future<void> unsaveTrack(String trackId) async {}

  @override
  Future<SearchResults> searchAll(String query) async => const SearchResults();

  @override
  Future<List<Suggestion>> suggest(String query) async => const [];

  @override
  Future<List<GenreCount>> genres() async => const [];

  @override
  Future<List<CatalogTrack>> genreTracks(String genre, {String sort = 'new'}) async => const [];

  @override
  Future<ArtistPageData> artistPage(String artistId) async => throw const ApiException(0, 'network');

  @override
  Future<List<ArtistChartEntry>> artistChart({String kind = 'top', String? country}) async => const [];

  @override
  Future<void> followArtist(String artistId) async {}

  @override
  Future<void> unfollowArtist(String artistId) async {}
}
