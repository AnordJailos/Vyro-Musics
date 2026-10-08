import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/catalog/catalog_api.dart';
import 'package:vyro_music/catalog/catalog_models.dart';
import 'package:vyro_music/studio/file_picker_service.dart';
import 'package:vyro_music/studio/studio_api.dart';
import 'package:vyro_music/studio/studio_models.dart';

CatalogTrack catalogTrack(String id, String title, {String artist = 'Nova Wave', bool explicit = false, bool allowMixing = true, int? rank}) => CatalogTrack(
      id: id,
      title: title,
      artistId: 'artist-$id',
      artistName: artist,
      durationMs: 200000,
      explicit: explicit,
      allowMixing: allowMixing,
      rank: rank,
    );

class FakeCatalogApi implements CatalogApi {
  FakeCatalogApi({this.fresh = const [], this.top = const [], this.all = const [], this.failWith});

  final List<CatalogTrack> fresh;
  final List<CatalogTrack> top;
  final List<CatalogTrack> all;
  Object? failWith;
  final searches = <String>[];

  T _go<T>(T v) {
    final e = failWith;
    if (e != null) throw e;
    return v;
  }

  @override
  Future<List<CatalogTrack>> newReleases() async => _go(fresh);

  @override
  Future<List<CatalogTrack>> charts({String range = '7d', String? country}) async => _go(top);

  @override
  Future<List<CatalogTrack>> search(String query) async {
    searches.add(query);
    return _go([for (final t in all) if (t.title.toLowerCase().contains(query.toLowerCase())) t]);
  }

  @override
  Future<Uri> streamUri(String trackId) async => Uri.parse('http://localhost:3000/v1/stream/$trackId.token');

  @override
  Uri coverUri(String coverPath) => Uri.parse('http://localhost:3000$coverPath');
}

class FakeStudioApi implements StudioApi {
  final tracks = <StudioTrack>[];
  final calls = <String>[];
  Object? failNextUpload;
  var _n = 0;

  StudioTrack _set(String id, StudioTrack Function(StudioTrack t) change) {
    final i = tracks.indexWhere((t) => t.id == id);
    tracks[i] = change(tracks[i]);
    return tracks[i];
  }

  StudioTrack _copy(StudioTrack t, {String? status, bool? hasAudio, bool? hasCover}) => StudioTrack(
        id: t.id,
        title: t.title,
        status: status ?? t.status,
        genre: t.genre,
        durationMs: hasAudio == true ? 180000 : t.durationMs,
        explicit: t.explicit,
        allowMixing: t.allowMixing,
        hasAudio: hasAudio ?? t.hasAudio,
        hasCover: hasCover ?? t.hasCover,
        codec: hasAudio == true ? 'mp3' : t.codec,
        bitrateKbps: hasAudio == true ? 192 : t.bitrateKbps,
        loudnessLufs: hasAudio == true ? -14.2 : t.loudnessLufs,
      );

  @override
  Future<List<StudioTrack>> myTracks() async => List.of(tracks);

  @override
  Future<StudioTrack> createTrack({required String title, String genre = 'other', bool explicit = false, bool allowMixing = true}) async {
    calls.add('createTrack');
    final t = StudioTrack(id: 't${++_n}', title: title, status: 'draft', genre: genre, explicit: explicit, allowMixing: allowMixing);
    tracks.insert(0, t);
    return t;
  }

  @override
  Future<StudioTrack> uploadAudio(String trackId, PickedFile file, {void Function(int sent, int total)? onProgress}) async {
    calls.add('uploadAudio');
    final e = failNextUpload;
    if (e != null) {
      failNextUpload = null;
      throw e;
    }
    onProgress?.call(file.length, file.length);
    return _set(trackId, (t) => _copy(t, status: 'ready', hasAudio: true));
  }

  @override
  Future<StudioTrack> uploadCover(String trackId, PickedFile file) async {
    calls.add('uploadCover');
    return _set(trackId, (t) => _copy(t, hasCover: true));
  }

  @override
  Future<StudioTrack> publish(String trackId) async {
    calls.add('publish');
    return _set(trackId, (t) => _copy(t, status: 'published'));
  }

  @override
  Future<StudioTrack> unpublish(String trackId) async {
    calls.add('unpublish');
    return _set(trackId, (t) => _copy(t, status: 'ready'));
  }

  @override
  Future<void> deleteTrack(String trackId) async {
    calls.add('deleteTrack');
    tracks.removeWhere((t) => t.id == trackId);
  }
}

class FakePicker implements FilePickerService {
  FakePicker({this.audio, this.image});

  PickedFile? audio;
  PickedFile? image;

  @override
  Future<PickedFile?> pickAudio() async => audio;

  @override
  Future<PickedFile?> pickImage() async => image;
}

PickedFile pickedFile(String name, int length) => PickedFile(name: name, length: length, open: () => Stream.value(List<int>.filled(length, 7)));

ApiException get uploadTooLow => const ApiException(422, 'bitrate_too_low');
