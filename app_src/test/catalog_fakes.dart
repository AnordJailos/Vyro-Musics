import 'dart:convert';
import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/catalog/catalog_api.dart';
import 'package:vyro_music/lyrics/lyrics_models.dart';
import 'package:vyro_music/catalog/catalog_models.dart';
import 'package:vyro_music/studio/file_picker_service.dart';
import 'package:vyro_music/studio/studio_api.dart';
import 'package:vyro_music/studio/studio_models.dart';

CatalogTrack catalogTrack(String id, String title, {String artist = 'Nova Wave', String? artistId, bool explicit = false, bool allowMixing = true, int? rank}) => CatalogTrack(
      id: id,
      title: title,
      artistId: artistId ?? 'artist-$id',
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
  final lyricsByTrack = <String, Lyrics?>{};
  final lyricsLookups = <String>[];
  final reports = <String>[];
  List<RecSection> recs = [];
  Object? recsFailure;
  final dismissed = <String>[];
  int resets = 0;
  List<CatalogTrack> saved = [];
  List<ArtistSummary> artists = [];
  List<Suggestion> suggestions = [];
  List<GenreCount> genreCounts = [];
  final genreSongs = <String, List<CatalogTrack>>{};
  final pages = <String, ArtistPageData>{};
  List<ArtistChartEntry> chartTop = [];
  List<ArtistChartEntry> chartRising = [];
  final suggestQueries = <String>[];
  final chartRequests = <String>[];
  final follows = <String>[];
  Object? followFailure;
  Object? pageFailure;
  final saveCalls = <String>[];
  Object? saveFailure;
  Object? lyricsFailure;

  T _go<T>(T v) {
    final e = failWith;
    if (e != null) throw e;
    return v;
  }

  @override
  Future<List<CatalogTrack>> newReleases() async => _go(fresh);

  @override
  Future<List<CatalogTrack>> charts({String range = '7d', String? country}) async {
    chartRequests.add('songs:${country ?? 'world'}');
    return _go(top);
  }

  @override
  Future<List<CatalogTrack>> search(String query) async {
    searches.add(query);
    return _go([for (final t in all) if (t.title.toLowerCase().contains(query.toLowerCase())) t]);
  }

  @override
  Future<Uri> streamUri(String trackId) async => Uri.parse('http://localhost:3000/v1/stream/$trackId.token');

  @override
  Future<Lyrics?> lyrics(String trackId) async {
    lyricsLookups.add(trackId);
    final e = lyricsFailure;
    if (e != null) throw e;
    return lyricsByTrack[trackId];
  }

  @override
  Future<void> reportLyrics(String trackId, {String reason = 'other'}) async => reports.add('$trackId:$reason');

  @override
  Future<List<RecSection>> recommendations() async {
    final e = recsFailure;
    if (e != null) throw e;
    return recs;
  }

  @override
  Future<void> notInterested({required String kind, required String id}) async => dismissed.add('$kind:$id');

  @override
  Future<void> resetRecommendations() async => resets++;

  @override
  Future<List<CatalogTrack>> savedTracks() async {
    final e = saveFailure;
    if (e != null) throw e;
    return List.of(saved);
  }

  @override
  Future<void> saveTrack(String trackId) async {
    final e = saveFailure;
    if (e != null) throw e;
    saveCalls.add('save:$trackId');
    if (!saved.any((t) => t.id == trackId)) saved.insert(0, catalogTrack(trackId, 'Song $trackId'));
  }

  @override
  Future<SearchResults> searchAll(String query) async => SearchResults(
        artists: [for (final a in artists) if (a.stageName.toLowerCase().contains(query.toLowerCase())) a],
        tracks: await search(query),
      );

  @override
  Future<List<Suggestion>> suggest(String query) async {
    suggestQueries.add(query);
    return [for (final s in suggestions) if (s.text.toLowerCase().contains(query.toLowerCase())) s];
  }

  @override
  Future<List<GenreCount>> genres() async => genreCounts;

  @override
  Future<List<CatalogTrack>> genreTracks(String genre, {String sort = 'new'}) async {
    chartRequests.add('genre:$genre:$sort');
    return genreSongs[genre] ?? const [];
  }

  @override
  Future<ArtistPageData> artistPage(String artistId) async {
    final e = pageFailure;
    if (e != null) throw e;
    return pages[artistId] ?? (throw const ApiException(404, 'not_found'));
  }

  @override
  Future<List<ArtistChartEntry>> artistChart({String kind = 'top', String? country}) async {
    chartRequests.add('artists:$kind:${country ?? 'world'}');
    return kind == 'rising' ? chartRising : chartTop;
  }

  @override
  Future<void> followArtist(String artistId) async {
    final e = followFailure;
    if (e != null) throw e;
    follows.add('follow:$artistId');
  }

  @override
  Future<void> unfollowArtist(String artistId) async {
    final e = followFailure;
    if (e != null) throw e;
    follows.add('unfollow:$artistId');
  }

  @override
  Future<void> unsaveTrack(String trackId) async {
    final e = saveFailure;
    if (e != null) throw e;
    saveCalls.add('unsave:$trackId');
    saved.removeWhere((t) => t.id == trackId);
  }

  @override
  Uri coverUri(String coverPath) => Uri.parse('http://localhost:3000$coverPath');
}

class FakeStudioApi implements StudioApi {
  final tracks = <StudioTrack>[];
  final notices = <TakedownInfo>[];
  final calls = <String>[];
  Object? failNextUpload;

  /// What the server decides when a song is submitted: in_review, held or published.
  String publishStatus = 'in_review';
  var _n = 0;

  StudioTrack _set(String id, StudioTrack Function(StudioTrack t) change) {
    final i = tracks.indexWhere((t) => t.id == id);
    tracks[i] = change(tracks[i]);
    return tracks[i];
  }

  StudioTrack _copy(StudioTrack t, {String? status, bool? hasAudio, bool? hasCover, String? rejectReason, bool? hasLyrics}) => StudioTrack(
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
        rejectReason: rejectReason ?? t.rejectReason,
        hasLyrics: hasLyrics ?? t.hasLyrics,
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
    return _set(trackId, (t) => _copy(t, status: publishStatus));
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

  final lyricsText = <String, String>{};

  @override
  Future<LyricsDraft?> lyrics(String trackId) async {
    final text = lyricsText[trackId];
    return text == null ? null : LyricsDraft(text: text, synced: parseLyrics(text).synced);
  }

  @override
  Future<LyricsSaved> setLyrics(String trackId, String text) async {
    calls.add('setLyrics');
    lyricsText[trackId] = text;
    _set(trackId, (t) => _copy(t, hasLyrics: true));
    final parsed = parseLyrics(text);
    return LyricsSaved(synced: parsed.synced, lineCount: parsed.lines.length);
  }

  @override
  Future<void> removeLyrics(String trackId) async {
    calls.add('removeLyrics');
    lyricsText.remove(trackId);
    _set(trackId, (t) => _copy(t, hasLyrics: false));
  }

  @override
  Future<List<TakedownInfo>> takedowns() async => List.of(notices);

  @override
  Future<void> counterNotice(String noticeId, {required String statement, required String signature}) async {
    calls.add('counterNotice');
    final i = notices.indexWhere((n) => n.id == noticeId);
    final n = notices[i];
    notices[i] = TakedownInfo(id: n.id, status: 'counter_filed', trackId: n.trackId, trackTitle: n.trackTitle, claimantName: n.claimantName, statement: n.statement);
  }

  /// Puts a song in a given state, as if the server had decided it.
  StudioTrack seed(String id, String title, String status, {bool hasAudio = true, String? rejectReason}) {
    final t = StudioTrack(id: id, title: title, status: status, hasAudio: hasAudio, durationMs: hasAudio ? 180000 : 0, rejectReason: rejectReason);
    tracks.add(t);
    return t;
  }
}

class FakePicker implements FilePickerService {
  FakePicker({this.audio, this.image, this.lyrics});

  PickedFile? audio;
  PickedFile? image;
  PickedFile? lyrics;

  @override
  Future<PickedFile?> pickAudio() async => audio;

  @override
  Future<PickedFile?> pickImage() async => image;

  @override
  Future<PickedFile?> pickLyrics() async => lyrics;
}

/// A text file the artist picked, such as a .lrc file.
PickedFile pickedText(String name, String text) {
  final bytes = utf8.encode(text);
  return PickedFile(name: name, length: bytes.length, open: () => Stream.value(bytes));
}

PickedFile pickedFile(String name, int length) => PickedFile(name: name, length: length, open: () => Stream.value(List<int>.filled(length, 7)));

ApiException get uploadTooLow => const ApiException(422, 'bitrate_too_low');
