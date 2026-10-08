import '../auth/api_client.dart';
import '../auth/api_errors.dart';
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
}
