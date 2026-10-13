import '../auth/api_client.dart';
import '../auth/api_errors.dart';
import 'admin_models.dart';

/// The moderators' tools. The server refuses everything here for anyone who is not staff.
abstract class AdminApi {
  Future<List<ReviewItem>> reviewQueue({String status = 'in_review'});
  Future<void> approve(String trackId, {String? note});
  Future<void> reject(String trackId, {required String reason, String? note});

  /// Decides many songs at once. Returns how many were decided.
  Future<int> bulk({required String action, required List<String> ids, String? reason});

  /// A short-lived address so a reviewer can listen to a song that is not public.
  Future<Uri> previewUri(String trackId);
  Future<List<TakedownNotice>> takedowns();
  Future<void> resolveTakedown(String noticeId, {required String decision, String? note});
  Future<List<AdminArtist>> artists(String query);
  Future<void> verifyArtist(String artistId, bool verified);
  Future<void> suspend(String userId, String reason);
  Future<void> unsuspend(String userId);
}

Map<String, Object?> _map(Object? v) => (v as Map).cast<String, Object?>();

class HttpAdminApi implements AdminApi {
  HttpAdminApi(this._client);

  final ApiClient _client;

  @override
  Future<List<ReviewItem>> reviewQueue({String status = 'in_review'}) async {
    final m = _map(await _client.send('GET', '/v1/admin/review/queue', query: {'status': status}));
    return [for (final i in (m['items'] as List)) ReviewItem.fromJson(_map(i))];
  }

  @override
  Future<void> approve(String trackId, {String? note}) async {
    await _client.send('POST', '/v1/admin/review/tracks/$trackId/approve', body: {if (note != null && note.isNotEmpty) 'note': note});
  }

  @override
  Future<void> reject(String trackId, {required String reason, String? note}) async {
    await _client.send('POST', '/v1/admin/review/tracks/$trackId/reject', body: {'reason': reason, if (note != null && note.isNotEmpty) 'note': note});
  }

  @override
  Future<int> bulk({required String action, required List<String> ids, String? reason}) async {
    final m = _map(await _client.send('POST', '/v1/admin/review/bulk', body: {'action': action, 'ids': ids, if (reason != null) 'reason': reason}));
    return (m['done'] as num).toInt();
  }

  @override
  Future<Uri> previewUri(String trackId) async {
    final m = _map(await _client.send('GET', '/v1/admin/tracks/$trackId/stream-url'));
    return _client.baseUrl.replace(path: m['url'] as String);
  }

  @override
  Future<List<TakedownNotice>> takedowns() async {
    final m = _map(await _client.send('GET', '/v1/admin/takedowns'));
    return [for (final n in (m['notices'] as List)) TakedownNotice.fromJson(_map(n))];
  }

  @override
  Future<void> resolveTakedown(String noticeId, {required String decision, String? note}) async {
    await _client.send('POST', '/v1/admin/takedowns/$noticeId/resolve', body: {'decision': decision, if (note != null && note.isNotEmpty) 'note': note});
  }

  @override
  Future<List<AdminArtist>> artists(String query) async {
    final m = _map(await _client.send('GET', '/v1/admin/artists', query: {'q': query}));
    return [for (final a in (m['artists'] as List)) AdminArtist.fromJson(_map(a))];
  }

  @override
  Future<void> verifyArtist(String artistId, bool verified) async {
    await _client.send('POST', '/v1/admin/artists/$artistId/verify', body: {'verified': verified});
  }

  @override
  Future<void> suspend(String userId, String reason) async {
    await _client.send('POST', '/v1/admin/users/$userId/suspend', body: {'reason': reason});
  }

  @override
  Future<void> unsuspend(String userId) async {
    await _client.send('POST', '/v1/admin/users/$userId/unsuspend');
  }
}

/// Used where there is no server: every call fails as "no connection".
class OfflineAdminApi implements AdminApi {
  const OfflineAdminApi();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(const ApiException(0, 'network'));
}
