import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/auth/api_client.dart';
import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/catalog/catalog_api.dart';
import 'package:vyro_music/catalog/catalog_models.dart';
import 'package:vyro_music/lyrics/lyrics_models.dart';
import 'package:vyro_music/lyrics/lyrics_provider.dart';
import 'package:vyro_music/lyrics/lyrics_view.dart';
import 'package:vyro_music/shell/player_ui.dart';
import 'package:vyro_music/studio/releases_page.dart';
import 'package:vyro_music/studio/studio_api.dart';
import 'package:vyro_music/studio/studio_models.dart';

import 'catalog_fakes.dart';
import 'fakes.dart';

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const synced = '[00:05.00]First line\n[00:10.00]Second line\n[00:15.00]Third line';

Track vyroTrack(String id, {String title = 'Song'}) =>
    Track(id: 'vyro:$id', title: title, artist: 'Nova Wave', uri: Uri.parse('https://example.com/$id'), source: TrackSource.vyro, duration: const Duration(minutes: 3));

Track localTrack(String path) => Track(id: 'local:$path', title: 'Local Song', artist: 'Me', uri: Uri.file(path), source: TrackSource.local, duration: const Duration(minutes: 3));

class Rig {
  Rig({Map<String, String> files = const {}, this.embedded}) {
    provider = LyricsProvider(
      catalog: catalog,
      embedded: embedded,
      readText: (path) async => files[path.replaceAll('\\', '/')],
      clock: () => now,
    );
  }

  final catalog = FakeCatalogApi();
  final TextReader? embedded;
  late final LyricsProvider provider;
  DateTime now = DateTime(2026, 10, 10, 12);
}

void main() {
  group('reading lyrics (the same rules as the server)', () {
    test('time-stamped lines, ignoring the title, artist and album tags', () {
      final r = parseLyrics('[ar:Someone]\n[ti:Song]\n[00:12.00]First\n[00:15.50]Second\n[01:02.5]Late');
      expect(r.synced, isTrue);
      expect(r.lines.map((l) => [l.timeMs, l.text]), [
        [12000, 'First'],
        [15500, 'Second'],
        [62500, 'Late'],
      ]);
    });

    test('several time stamps on one line, in time order', () {
      final r = parseLyrics('[00:40.00]Verse two\n[00:10.00][01:20.00]Chorus\n[00:05.00]Intro');
      expect(r.lines.map((l) => [l.timeMs, l.text]), [
        [5000, 'Intro'],
        [10000, 'Chorus'],
        [40000, 'Verse two'],
        [80000, 'Chorus'],
      ]);
    });

    test('the offset tag: positive shows lyrics sooner, negative later, never before zero', () {
      expect(parseLyrics('[offset:+500]\n[00:10.00]Hi').lines.single.timeMs, 9500);
      expect(parseLyrics('[offset:-500]\n[00:10.00]Hi').lines.single.timeMs, 10500);
      expect(parseLyrics('[offset:+5000]\n[00:01.00]Hi').lines.single.timeMs, 0);
    });

    test('every way of writing the fraction of a second', () {
      int t(String s) => parseLyrics(s).lines.first.timeMs!;
      expect([t('[00:10]x'), t('[00:10.5]x'), t('[00:10.50]x'), t('[00:10.500]x'), t('[00:10:50]x'), t('[100:00.00]x')], [10000, 10500, 10500, 10500, 10500, 6000000]);
    });

    test('word-by-word stamps are dropped and the words kept', () {
      expect(parseLyrics('[00:10.00]<00:10.00>Hel<00:10.50>lo <00:11.00>there').lines.single.text, 'Hello there');
    });

    test('one gap for an instrumental break, but no leading or doubled gaps', () {
      final r = parseLyrics('[00:01.00]\n[00:10.00]a\n[00:12.00]\n[00:12.50]\n[00:20.00]b');
      expect(r.lines.map((l) => l.text), ['a', '', 'b']);
    });

    test('a byte order mark and Windows line endings', () {
      expect(parseLyrics('\uFEFF[00:01.00]x\r\n[00:02.00]y').lines.map((l) => l.text), ['x', 'y']);
    });

    test('text without time stamps is plain lyrics, with verse breaks kept', () {
      final r = parseLyrics('Line one\n\n\nLine two  \n\n');
      expect(r.synced, isFalse);
      expect(r.lines.map((l) => [l.timeMs, l.text]), [
        [null, 'Line one'],
        [null, ''],
        [null, 'Line two'],
      ]);
    });

    test('text that only has tags has no lyrics', () {
      expect(parseLyrics('[ar:Someone]\n[ti:Song]').isEmpty, isTrue);
      expect(parseLyrics('').isEmpty, isTrue);
    });
  });

  test('finds the line being sung', () {
    final l = parseLyrics(synced);
    int at(int ms) => currentLineIndex(l, Duration(milliseconds: ms));
    expect([at(0), at(4999), at(5000), at(9999), at(10000), at(15000), at(999999)], [-1, -1, 0, 0, 1, 2, 2]);
    expect(currentLineIndex(parseLyrics('Just words'), const Duration(seconds: 5)), -1);
    expect(currentLineIndex(const Lyrics(synced: true, lines: []), const Duration(seconds: 5)), -1);
  });

  group('the HTTP catalog', () {
    ApiClient clientFor(http.Response Function(http.Request) answer, [List<Uri>? seen]) => ApiClient(
          baseUrl: Uri.parse('http://localhost:3000'),
          session: ApiSession(),
          client: MockClient((request) async {
            seen?.add(request.url);
            return answer(request);
          }),
        );

    test('reads lyrics, and treats "no lyrics" as null rather than an error', () async {
      final api = HttpCatalogApi(clientFor((r) => r.url.path.contains('missing')
          ? _json(404, {'error': 'not_found'})
          : _json(200, {
              'synced': true,
              'lines': [
                {'timeMs': 5000, 'text': 'First'},
                {'timeMs': 9000, 'text': ''},
              ],
            })));
      final found = (await api.lyrics('abc'))!;
      expect(found.synced, isTrue);
      expect(found.lines.map((l) => [l.timeMs, l.text]), [
        [5000, 'First'],
        [9000, ''],
      ]);
      expect(await api.lyrics('missing'), isNull);
    });

    test('other failures are not mistaken for "no lyrics"', () async {
      final api = HttpCatalogApi(clientFor((r) => _json(403, {'error': 'explicit_not_allowed'})));
      await expectLater(api.lyrics('abc'), throwsA(isA<ApiException>()));
    });

    test('sends a report with the reason', () async {
      late http.Request seen;
      final api = HttpCatalogApi(clientFor((r) {
        seen = r;
        return http.Response('', 204);
      }));
      await api.reportLyrics('abc', reason: 'wrong_timing');
      expect([seen.method, seen.url.path, jsonDecode(seen.body)], ['POST', '/v1/tracks/abc/lyrics/report', {'reason': 'wrong_timing'}]);
    });

    test('songs know whether they have lyrics', () {
      final t = CatalogTrack.fromJson({'id': 'a', 'title': 'T', 'artist': {'id': 'x', 'stageName': 'S'}, 'durationMs': 1000, 'hasLyrics': true});
      expect(t.hasLyrics, isTrue);
      expect(StudioTrack.fromJson({'id': 'a', 'title': 'T', 'status': 'ready', 'hasLyrics': true}).hasLyrics, isTrue);
      expect(StudioTrack.fromJson({'id': 'a', 'title': 'T', 'status': 'ready'}).hasLyrics, isFalse);
    });

    test('the artist side: read, save and remove', () async {
      final calls = <String>[];
      Object? sent;
      final studio = HttpStudioApi(clientFor((r) {
        calls.add('${r.method} ${r.url.path}');
        if (r.method == 'PUT') sent = jsonDecode(r.body);
        if (r.method == 'GET' && r.url.path.contains('none')) return _json(404, {'error': 'not_found'});
        if (r.method == 'GET') return _json(200, {'text': synced, 'synced': true});
        if (r.method == 'PUT') return _json(200, {'synced': true, 'lineCount': 3});
        return http.Response('', 204);
      }));
      expect((await studio.lyrics('t1'))!.text, synced);
      expect(await studio.lyrics('none'), isNull);
      final saved = await studio.setLyrics('t1', synced);
      expect([saved.synced, saved.lineCount, sent], [true, 3, {'text': synced}]);
      await studio.removeLyrics('t1');
      expect(calls, ['GET /v1/artists/me/tracks/t1/lyrics', 'GET /v1/artists/me/tracks/none/lyrics', 'PUT /v1/artists/me/tracks/t1/lyrics', 'DELETE /v1/artists/me/tracks/t1/lyrics']);
    });
  });

  group('finding the lyrics of a song', () {
    test('a Vyro song asks Vyro, by its own id, and remembers the answer for a while', () async {
      final rig = Rig();
      rig.catalog.lyricsByTrack['abc'] = parseLyrics(synced);
      final t = vyroTrack('abc');
      expect((await rig.provider.lyricsFor(t))!.synced, isTrue);
      await rig.provider.lyricsFor(t);
      expect(rig.catalog.lyricsLookups, ['abc']); // the second time came from memory

      rig.now = rig.now.add(const Duration(minutes: 6));
      await rig.provider.lyricsFor(t);
      expect(rig.catalog.lyricsLookups, ['abc', 'abc']); // fresh again, so a correction by the artist shows up
    });

    test('remembers that a song has no lyrics, but never remembers a failure', () async {
      final rig = Rig();
      expect(await rig.provider.lyricsFor(vyroTrack('none')), isNull);
      await rig.provider.lyricsFor(vyroTrack('none'));
      expect(rig.catalog.lyricsLookups.length, 1);

      rig.catalog.lyricsFailure = const ApiException(0, 'network');
      await expectLater(rig.provider.lyricsFor(vyroTrack('abc')), throwsA(isA<ApiException>()));
      rig.catalog.lyricsFailure = null;
      rig.catalog.lyricsByTrack['abc'] = parseLyrics('Words');
      expect((await rig.provider.lyricsFor(vyroTrack('abc')))!.synced, isFalse);
    });

    test('a song on the device uses the .lrc file next to it, then a .txt, then lyrics inside the file', () async {
      final rig = Rig(
        files: {'/music/a.lrc': synced, '/music/b.txt': 'Plain words', '/music/c.lrc': '   ', '/music/c.txt': 'From text'},
        embedded: (path) async => path.replaceAll('\\', '/') == '/music/d.mp3' ? '[00:01.00]Inside the tag' : null,
      );
      expect((await rig.provider.lyricsFor(localTrack('/music/a.mp3')))!.synced, isTrue);
      expect((await rig.provider.lyricsFor(localTrack('/music/b.mp3')))!.lines.single.text, 'Plain words');
      expect((await rig.provider.lyricsFor(localTrack('/music/c.mp3')))!.lines.single.text, 'From text'); // a blank file is skipped
      expect((await rig.provider.lyricsFor(localTrack('/music/d.mp3')))!.lines.single.text, 'Inside the tag');
      expect(await rig.provider.lyricsFor(localTrack('/music/e.mp3')), isNull);
    });

    test('only the last part of the file name is taken as the extension', () async {
      final rig = Rig(files: {'/music/Artist - Song.v2.lrc': synced});
      expect(await rig.provider.lyricsFor(localTrack('/music/Artist - Song.v2.mp3')), isNotNull);
    });

    test('demo songs have no lyrics', () async {
      final rig = Rig();
      final demo = Track(id: 'demo-1', title: 'Demo', artist: 'X', uri: Uri.parse('https://example.com/x.mp3'), source: TrackSource.open);
      expect(await rig.provider.lyricsFor(demo), isNull);
    });

    test('a report goes to Vyro for a Vyro song, and nowhere for a song on the device', () async {
      final rig = Rig();
      await rig.provider.report(vyroTrack('abc'), 'wrong_text');
      await rig.provider.report(localTrack('/music/a.mp3'), 'wrong_text');
      expect(rig.catalog.reports, ['abc:wrong_text']);
    });
  });

  group('the lyrics view', () {
    late FakeDeck deckA;
    late PlaybackController controller;
    late Rig rig;

    setUp(() {
      deckA = FakeDeck();
      controller = PlaybackController(deckA: deckA, deckB: FakeDeck());
      rig = Rig();
    });

    Widget host(Rig r) => MaterialApp(home: Scaffold(body: SizedBox(height: 500, child: LyricsView(controller: controller, provider: r.provider))));

    Future<void> play(WidgetTester tester, List<Track> tracks) async {
      unawaited(controller.setQueue(tracks));
      await tester.pump();
      await tester.pump();
    }

    Future<void> at(WidgetTester tester, int seconds) async {
      deckA.emitPosition(Duration(seconds: seconds));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    String? current(WidgetTester tester) {
      final f = find.byKey(const ValueKey('current-lyric-line'));
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    testWidgets('shows synced lyrics and moves the highlight with the music', (tester) async {
      rig.catalog.lyricsByTrack['abc'] = parseLyrics(synced);
      await play(tester, [vyroTrack('abc')]);
      await tester.pumpWidget(host(rig));
      await tester.pump();
      expect(find.text('First line'), findsOneWidget);
      expect(find.text('Third line'), findsOneWidget);
      expect(current(tester), isNull); // before the first line

      await at(tester, 6);
      expect(current(tester), 'First line');
      await at(tester, 11);
      expect(current(tester), 'Second line');
      await at(tester, 16);
      expect(current(tester), 'Third line');
      await at(tester, 3); // the listener dragged the bar back
      expect(current(tester), isNull);
    });

    testWidgets('tapping a line jumps to it', (tester) async {
      rig.catalog.lyricsByTrack['abc'] = parseLyrics(synced);
      await play(tester, [vyroTrack('abc')]);
      await tester.pumpWidget(host(rig));
      await tester.pump();
      await tester.tap(find.text('Third line'));
      await tester.pump();
      expect(deckA.seeks.last, const Duration(seconds: 15));
    });

    testWidgets('plain lyrics are shown as they are, with no highlight and nothing to tap', (tester) async {
      rig.catalog.lyricsByTrack['abc'] = parseLyrics('Just some words\n\nAnd more words');
      await play(tester, [vyroTrack('abc')]);
      await tester.pumpWidget(host(rig));
      await tester.pump();
      expect(find.text('Just some words'), findsOneWidget);
      await at(tester, 6);
      expect(current(tester), isNull);
      await tester.tap(find.text('And more words'));
      await tester.pump();
      expect(deckA.seeks, isEmpty);
    });

    testWidgets('says so when a song has no lyrics, and tells people with their own files how to add them', (tester) async {
      await play(tester, [vyroTrack('abc')]);
      await tester.pumpWidget(host(rig));
      await tester.pump();
      expect(find.text('No lyrics for this song yet.'), findsOneWidget);

      await play(tester, [localTrack('/music/a.mp3')]);
      await tester.pump();
      expect(find.textContaining('.lrc file'), findsOneWidget);
      expect(find.byTooltip('Lyrics options'), findsNothing); // nothing to report on your own files
    });

    testWidgets('offers a retry when Vyro cannot be reached', (tester) async {
      rig.catalog.lyricsFailure = const ApiException(0, 'network');
      rig.catalog.lyricsByTrack['abc'] = parseLyrics(synced);
      await play(tester, [vyroTrack('abc')]);
      await tester.pumpWidget(host(rig));
      await tester.pump();
      expect(find.text('Could not load the lyrics.'), findsOneWidget);

      rig.catalog.lyricsFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(find.text('First line'), findsOneWidget);
    });

    testWidgets('follows the song when the next one starts', (tester) async {
      rig.catalog.lyricsByTrack['one'] = parseLyrics('[00:01.00]Words of one');
      rig.catalog.lyricsByTrack['two'] = parseLyrics('[00:01.00]Words of two');
      await play(tester, [vyroTrack('one'), vyroTrack('two')]);
      await tester.pumpWidget(host(rig));
      await tester.pump();
      expect(find.text('Words of one'), findsOneWidget);
      unawaited(controller.next());
      await tester.pump();
      await tester.pump();
      expect(find.text('Words of two'), findsOneWidget);
      expect(find.text('Words of one'), findsNothing);
    });

    testWidgets('lets a listener report wrong lyrics', (tester) async {
      rig.catalog.lyricsByTrack['abc'] = parseLyrics(synced);
      await play(tester, [vyroTrack('abc')]);
      await tester.pumpWidget(host(rig));
      await tester.pump();
      await tester.tap(find.byTooltip('Lyrics options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report wrong timing'));
      await tester.pumpAndSettle();
      expect(rig.catalog.reports, ['abc:wrong_timing']);
      expect(find.text('Thank you. The artist has been told.'), findsOneWidget);
    });

    testWidgets('the Now Playing screen has a lyrics button that swaps the artwork for the lyrics', (tester) async {
      rig.catalog.lyricsByTrack['abc'] = parseLyrics(synced);
      await play(tester, [vyroTrack('abc')]);
      await tester.pumpWidget(MaterialApp(home: NowPlayingPage(controller: controller, lyrics: rig.provider)));
      await tester.pump();
      expect(find.byType(LyricsView), findsNothing);
      await tester.tap(find.byTooltip('Show lyrics'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(LyricsView), findsOneWidget);
      expect(find.text('First line'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide lyrics'));
      await tester.pump();
      expect(find.byType(LyricsView), findsNothing);
    });

    testWidgets('without a lyrics source there is no lyrics button', (tester) async {
      await tester.pumpWidget(MaterialApp(home: NowPlayingPage(controller: controller)));
      expect(find.byTooltip('Show lyrics'), findsNothing);
    });
  });

  group('the artist adds lyrics', () {
    Widget host(FakeStudioApi studio, [FakePicker? picker]) => MaterialApp(home: Scaffold(body: ReleasesPage(studio: studio, picker: picker ?? FakePicker())));

    Future<void> openEditor(WidgetTester tester, String songTitle, String menuText) async {
      await tester.tap(find.byTooltip('Options for $songTitle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(menuText));
      await tester.pumpAndSettle();
    }

    final field = find.widgetWithText(TextField, 'Lyrics');
    final save = find.widgetWithText(FilledButton, 'Save lyrics');

    // Finder get field => find.widgetWithText(TextField, 'Lyrics');
    // Finder get save => find.widgetWithText(FilledButton, 'Save lyrics');

    testWidgets('writes lyrics, sees what kind they are, and saves', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final studio = FakeStudioApi()..seed('t1', 'Song One', 'ready');
      await tester.pumpWidget(host(studio));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Song One', 'Add lyrics');
      expect(tester.widget<FilledButton>(save).onPressed, isNull); // nothing to save yet

      await tester.enterText(field, 'Just words\nMore words');
      await tester.pump();
      expect(find.textContaining('Plain lyrics, 2 lines'), findsOneWidget);
      await tester.enterText(field, '[00:05.00]Hello\n[00:10.00]World');
      await tester.pump();
      expect(find.textContaining('Synced lyrics, 2 lines'), findsOneWidget);

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(studio.calls, contains('setLyrics'));
      expect(studio.lyricsText['t1'], '[00:05.00]Hello\n[00:10.00]World');
      expect(find.text('Lyrics saved. They will follow the music.'), findsOneWidget);

      await tester.tap(find.byTooltip('Options for Song One'));
      await tester.pumpAndSettle();
      expect(find.text('Edit lyrics'), findsOneWidget); // the song now has lyrics
    });

    testWidgets('edits and removes saved lyrics, after asking', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final studio = FakeStudioApi()..seed('t1', 'Song One', 'published');
      await studio.setLyrics('t1', '[00:01.00]Saved line');
      await tester.pumpWidget(host(studio));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Song One', 'Edit lyrics');
      expect(tester.widget<TextField>(field).controller!.text, '[00:01.00]Saved line');

      await tester.tap(find.text('Remove lyrics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(studio.calls, isNot(contains('removeLyrics')));

      await tester.tap(find.text('Remove lyrics'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(studio.calls, contains('removeLyrics'));
      await tester.tap(find.byTooltip('Options for Song One'));
      await tester.pumpAndSettle();
      expect(find.text('Add lyrics'), findsOneWidget);
    });

    testWidgets('imports a .lrc file into the editor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final studio = FakeStudioApi()..seed('t1', 'Song One', 'ready');
      await tester.pumpWidget(host(studio, FakePicker(lyrics: pickedText('song.lrc', '\uFEFF[00:01.00]Imported line'))));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Song One', 'Add lyrics');
      await tester.tap(find.text('Import a .lrc or .txt file'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '[00:01.00]Imported line'); // the byte order mark is dropped
      expect(find.textContaining('Synced lyrics, 1 line'), findsOneWidget);
    });

    testWidgets('refuses a file that is too big to be lyrics', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final studio = FakeStudioApi()..seed('t1', 'Song One', 'ready');
      final huge = PickedFile(name: 'big.txt', length: 300 * 1024, open: () => Stream.value(List<int>.filled(300 * 1024, 65)));
      await tester.pumpWidget(host(studio, FakePicker(lyrics: huge)));
      await tester.pumpAndSettle();
      await openEditor(tester, 'Song One', 'Add lyrics');
      await tester.tap(find.text('Import a .lrc or .txt file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('too large'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    });
  });
}
