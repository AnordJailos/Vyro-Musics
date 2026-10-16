import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/auth/api_client.dart';
import 'package:vyro_music/catalog/catalog_api.dart';
import 'package:vyro_music/catalog/catalog_models.dart';
import 'package:vyro_music/catalog/recent_searches.dart';
import 'package:vyro_music/history/play_record.dart';
import 'package:vyro_music/history/recent_tracks.dart';

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> trackJson(String id, String title) => {'id': id, 'title': title, 'artist': {'id': 'artist-$id', 'stageName': 'Nova Wave'}, 'durationMs': 200000};

PlayRecord play(String id, {String source = 'vyro', int seconds = 60, int minutesAgo = 0, String? title}) => PlayRecord(
      id: 'r-$id-$minutesAgo-$source',
      trackId: id,
      source: source,
      title: title ?? 'Song $id',
      artist: 'Artist',
      startedAt: DateTime.utc(2026, 10, 12, 12).subtract(Duration(minutes: minutesAgo)),
      listenedMs: seconds * 1000,
      durationMs: 200000,
      mode: 'normal',
      origin: 'search',
      platform: 'android',
    );

void main() {
  group('the HTTP catalog', () {
    HttpCatalogApi apiFor(http.Response Function(http.Request) answer, List<http.Request> seen) => HttpCatalogApi(ApiClient(
          baseUrl: Uri.parse('http://localhost:3000'),
          session: ApiSession(),
          client: MockClient((request) async {
            seen.add(request);
            return answer(request);
          }),
        ));

    test('searches artists and songs together', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) => _json(200, {'artists': [{'id': 'a1', 'stageName': 'Nova Wave', 'verified': true, 'followers': 12}], 'tracks': [trackJson('1', 'Night Drive')]}), seen);
      final r = await api.searchAll('nova wve');
      expect([seen.single.url.path, seen.single.url.queryParameters['q']], ['/v1/search', 'nova wve']);
      expect(r.artists.single.stageName, 'Nova Wave');
      expect([r.artists.single.verified, r.artists.single.followers], [true, 12]);
      expect(r.tracks.single.title, 'Night Drive');
    });

    test('asks for suggestions, genres, the songs of a genre, and artist charts', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) {
        if (r.url.path == '/v1/search/suggest') return _json(200, {'suggestions': [{'kind': 'artist', 'id': 'a1', 'text': 'Nova Wave', 'subtitle': 'Artist'}, {'kind': 'song', 'id': 's1', 'text': 'Night Drive', 'subtitle': 'Nova Wave'}]});
        if (r.url.path == '/v1/browse/genres') return _json(200, {'genres': [{'genre': 'afrobeats', 'count': 3}, {'genre': 'other', 'count': 1}]});
        if (r.url.path.startsWith('/v1/browse/genres/')) return _json(200, {'genre': 'hip hop', 'tracks': [trackJson('1', 'Night Drive')]});
        return _json(200, {'kind': 'rising', 'artists': [{'rank': 1, 'id': 'a1', 'stageName': 'Nova Wave', 'verified': false, 'followers': 2, 'plays': 6, 'change': 4}]});
      }, seen);
      final s = await api.suggest('no');
      expect(s.map((x) => [x.kind, x.text, x.isArtist]), [['artist', 'Nova Wave', true], ['song', 'Night Drive', false]]);
      expect((await api.genres()).map((g) => [g.genre, g.count]), [['afrobeats', 3], ['other', 1]]);
      expect((await api.genreTracks('hip hop', sort: 'popular')).single.title, 'Night Drive');
      expect(seen[2].url.path, '/v1/browse/genres/hip%20hop'); // spaces are safe in the address
      expect(seen[2].url.queryParameters['sort'], 'popular');
      final chart = await api.artistChart(kind: 'rising', country: 'KE');
      expect([seen[3].url.path, seen[3].url.queryParameters], ['/v1/charts/artists', {'kind': 'rising', 'country': 'KE'}]);
      expect([chart.single.rank, chart.single.artist.stageName, chart.single.plays, chart.single.change], [1, 'Nova Wave', 6, 4]);
    });

    test('reads an artist page, whether links come as objects or plain text', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) => _json(200, {
            'artist': {'id': 'a1', 'stageName': 'Nova Wave', 'verified': true, 'followers': 12, 'monthlyListeners': 340, 'bio': 'Afro fusion.', 'genres': ['afrobeats'], 'links': [{'label': 'Instagram', 'url': 'https://i.example/nova'}, 'https://nova.example']},
            'following': true,
            'topTracks': [trackJson('1', 'Night Drive')],
            'discography': [trackJson('1', 'Night Drive'), trackJson('2', 'Sunrise Run')],
            'similar': [{'id': 'a2', 'stageName': 'Zúri', 'verified': false, 'followers': 1}],
          }), seen);
      final p = await api.artistPage('a1');
      expect(seen.single.url.path, '/v1/artists/a1/page');
      expect([p.artist.stageName, p.artist.verified, p.artist.followers, p.monthlyListeners, p.following, p.bio, p.genres], ['Nova Wave', true, 12, 340, true, 'Afro fusion.', ['afrobeats']]);
      expect(p.links.map((l) => [l.label, l.url]), [['Instagram', 'https://i.example/nova'], ['', 'https://nova.example']]);
      expect([p.topTracks.length, p.discography.length, p.similar.single.stageName], [1, 2, 'Zúri']);
    });

    test('follows and unfollows', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) => http.Response('', 204), seen);
      await api.followArtist('a1');
      await api.unfollowArtist('a1');
      expect(seen.map((r) => '${r.method} ${r.url.path}'), ['POST /v1/artists/a1/follow', 'DELETE /v1/artists/a1/follow']);
    });
  });

  test('following changes the follower count by one, and only when it changes', () {
    const page = ArtistPageData(artist: ArtistSummary(id: 'a', stageName: 'A', followers: 5));
    expect(page.withFollowing(true).artist.followers, 6);
    expect(page.withFollowing(true).withFollowing(false).artist.followers, 5);
    expect(page.withFollowing(false).artist.followers, 5);
  });

  group('recent searches', () {
    test('keeps the newest first, once each, without noise', () async {
      final store = MemoryRecentSearchStore();
      final r = RecentSearches(store: store, max: 3);
      for (final q in ['nova', 'kito', 'a', '  ', 'NOVA ', 'zuri', 'rock']) {
        await r.add(q);
      }
      expect(r.items, ['rock', 'zuri', 'NOVA']); // one letter and blanks ignored; "nova" again moved to the front; only 3 kept
      expect(store.saved, ['rock', 'zuri', 'NOVA']);
    });

    test('removes one, clears all, and remembers across starts', () async {
      final store = MemoryRecentSearchStore();
      final r = RecentSearches(store: store);
      await r.add('nova');
      await r.add('kito');
      await r.remove('nova');
      expect(r.items, ['kito']);
      final again = RecentSearches(store: store);
      await again.load();
      expect(again.items, ['kito']);
      await again.clear();
      expect([again.items, store.saved], [isEmpty, isEmpty]);
    });

    test('on disk, and a damaged file is ignored', () async {
      final dir = Directory.systemTemp.createTempSync('vyro_recent_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final disk = FileRecentSearchStore(directory: () async => dir);
      await disk.save(['nova', 'kito']);
      expect(dir.listSync().map((f) => f.path.split(Platform.pathSeparator).last), ['recent_searches.json']);
      expect(await disk.load(), ['nova', 'kito']);
      File('${dir.path}/recent_searches.json').writeAsStringSync('{ broken');
      expect(await disk.load(), isEmpty);
    });
  });

  group('continue listening', () {
    Future<Uri> uri(String id) async => Uri.parse('https://example.com/$id');

    test('lists the songs played lately, newest first, once each', () async {
      final tracks = await recentTracks([play('a', minutesAgo: 30), play('b', minutesAgo: 20), play('a', minutesAgo: 5), play('c', minutesAgo: 10)], streamUri: uri);
      expect(tracks.map((t) => t.id), ['vyro:a', 'vyro:c', 'vyro:b']);
      expect(tracks.first.source, TrackSource.vyro);
      expect(tracks.first.duration, const Duration(milliseconds: 200000));
      expect(await tracks.first.resolveUri!(), Uri.parse('https://example.com/a'));
    });

    test('leaves out accidental taps, and caps the list', () async {
      final tracks = await recentTracks([play('tap', seconds: 4), for (var i = 0; i < 15; i++) play('s$i', minutesAgo: i)], streamUri: uri, limit: 5);
      expect(tracks.length, 5);
      expect(tracks.any((t) => t.id == 'vyro:tap'), isFalse);
    });

    test('keeps songs on the device only while their file is there', () async {
      final records = [play('local:/music/here.mp3', source: 'local', minutesAgo: 1), play('local:/music/gone.mp3', source: 'local', minutesAgo: 2)];
      final tracks = await recentTracks(records, streamUri: uri, fileExists: (p) => p.endsWith('here.mp3'));
      expect(tracks.map((t) => t.id), ['local:/music/here.mp3']);
      expect(tracks.single.source, TrackSource.local);
      expect(tracks.single.uri.toFilePath().replaceAll('\\', '/'), endsWith('/music/here.mp3'));
    });
  });
}
