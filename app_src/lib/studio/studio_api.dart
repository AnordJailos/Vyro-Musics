import '../auth/api_client.dart';
import '../auth/api_errors.dart';
import 'studio_models.dart';

/// The artist's side: create songs, upload audio and covers, publish.
abstract class StudioApi {
  Future<List<StudioTrack>> myTracks();
  Future<StudioTrack> createTrack({required String title, String genre = 'other', bool explicit = false, bool allowMixing = true});
  Future<StudioTrack> uploadAudio(String trackId, PickedFile file, {void Function(int sent, int total)? onProgress});
  Future<StudioTrack> uploadCover(String trackId, PickedFile file);
  Future<StudioTrack> publish(String trackId);
  Future<StudioTrack> unpublish(String trackId);
  Future<void> deleteTrack(String trackId);
}

Map<String, Object?> _map(Object? v) => (v as Map).cast<String, Object?>();

/// "song.mp3" -> audio/mpeg, and so on. The server checks the real content; this is only a label.
String audioContentType(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'mp3' => 'audio/mpeg',
    'm4a' || 'aac' => 'audio/mp4',
    'flac' => 'audio/flac',
    'wav' => 'audio/wav',
    'ogg' || 'opus' => 'audio/ogg',
    'aif' || 'aiff' => 'audio/aiff',
    _ => 'audio/mpeg',
  };
}

String imageContentType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

class HttpStudioApi implements StudioApi {
  HttpStudioApi(this._client);

  /// Matches the server's default upload limit.
  static const maxAudioBytes = 300 * 1024 * 1024;
  static const maxCoverBytes = 5 * 1024 * 1024;

  final ApiClient _client;

  @override
  Future<List<StudioTrack>> myTracks() async {
    final m = _map(await _client.send('GET', '/v1/artists/me/tracks'));
    return [for (final t in (m['tracks'] as List)) StudioTrack.fromJson(_map(t))];
  }

  @override
  Future<StudioTrack> createTrack({required String title, String genre = 'other', bool explicit = false, bool allowMixing = true}) async => StudioTrack.fromJson(
        _map(await _client.send('POST', '/v1/artists/me/tracks', body: {'title': title, 'genre': genre, 'explicit': explicit, 'allowMixing': allowMixing})),
      );

  @override
  Future<StudioTrack> uploadAudio(String trackId, PickedFile file, {void Function(int sent, int total)? onProgress}) async {
    if (file.length > maxAudioBytes) throw const ApiException(413, 'file_too_large'); // no point sending it
    return StudioTrack.fromJson(_map(await _client.upload(
      '/v1/artists/me/tracks/$trackId/audio',
      open: file.open,
      length: file.length,
      contentType: audioContentType(file.name),
      onProgress: onProgress,
    )));
  }

  @override
  Future<StudioTrack> uploadCover(String trackId, PickedFile file) async {
    if (file.length > maxCoverBytes) throw const ApiException(413, 'file_too_large');
    return StudioTrack.fromJson(_map(await _client.upload(
      '/v1/artists/me/tracks/$trackId/cover',
      open: file.open,
      length: file.length,
      contentType: imageContentType(file.name),
    )));
  }

  @override
  Future<StudioTrack> publish(String trackId) async => StudioTrack.fromJson(_map(await _client.send('POST', '/v1/artists/me/tracks/$trackId/publish')));

  @override
  Future<StudioTrack> unpublish(String trackId) async => StudioTrack.fromJson(_map(await _client.send('POST', '/v1/artists/me/tracks/$trackId/unpublish')));

  @override
  Future<void> deleteTrack(String trackId) async {
    await _client.send('DELETE', '/v1/artists/me/tracks/$trackId');
  }
}

/// Used where there is no server: every call fails as "no connection".
class OfflineStudioApi implements StudioApi {
  const OfflineStudioApi();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(const ApiException(0, 'network'));
}
