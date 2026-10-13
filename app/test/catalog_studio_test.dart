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
import 'package:vyro_music/catalog/search_page.dart';
import 'package:vyro_music/library/library_controller.dart';
import 'package:vyro_music/library/library_scanner.dart';
import 'package:vyro_music/library/library_store.dart';
import 'package:vyro_music/shell/pages.dart';
import 'package:vyro_music/studio/releases_page.dart';
import 'package:vyro_music/studio/studio_api.dart';
import 'package:vyro_music/studio/studio_models.dart';
import 'package:vyro_music/studio/studio_page.dart';

import 'catalog_fakes.dart';
import 'fakes.dart';
import 'library_fixtures.dart';

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

PlaybackController _playback() => PlaybackController(deckA: FakeDeck(), deckB: FakeDeck());
Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('catalog data', () {
    test('a catalog song becomes a playable song that asks for its address at play time', () async {
      final track = CatalogTrack.fromJson({
        'id': 'abc',
        'title': 'Night Drive',
        'artist': {'id': 'a1', 'stageName': 'Nova Wave'},
        'genre': 'afrobeats',
        'durationMs': 200000,
        'explicit': false,
        'allowMixing': false,
        'loudnessLufs': -14.2,
        'coverUrl': '/v1/tracks/abc/cover',
      });
      final asked = <String>[];
      final playable = track.toPlayable((id) async {
        asked.add(id);
        return Uri.parse('http://x/stream/$id');
      });
      expect(playable.id, 'vyro:abc');
      expect(playable.source, TrackSource.vyro);
      expect(playable.duration, const Duration(milliseconds: 200000));
      expect(playable.mixable, isFalse); // the artist turned blending off
      expect(asked, isEmpty); // nothing is requested until playback starts
      expect(await playable.resolveUri!(), Uri.parse('http://x/stream/abc'));
      expect(asked, ['abc']);
    });

    test('the HTTP catalog reads lists, sends the search words and builds the stream address', () async {
      final seen = <Uri>[];
      final client = ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: ApiSession(),
        client: MockClient((request) async {
          seen.add(request.url);
          if (request.url.path.endsWith('/stream-url')) return _json(200, {'url': '/v1/stream/abc.123.sig', 'expiresAt': 'x'});
          return _json(200, {
            'tracks': [
              {'id': 'abc', 'title': 'Night Drive', 'artist': {'id': 'a1', 'stageName': 'Nova Wave'}, 'durationMs': 1000, 'rank': 1, 'plays': 5},
            ],
          });
        }),
      );
      final api = HttpCatalogApi(client);
      expect((await api.newReleases()).single.title, 'Night Drive');
      expect((await api.search('night drive')).single.artistName, 'Nova Wave');
      expect(seen.last.queryParameters['q'], 'night drive');
      final chart = (await api.charts(country: 'KE')).single;
      expect([chart.rank, chart.plays], [1, 5]);
      expect(seen.last.queryParameters['country'], 'KE');
      expect(await api.streamUri('abc'), Uri.parse('http://localhost:3000/v1/stream/abc.123.sig'));
    });
  });

  group('uploads', () {
    test('send the file as the body with progress, the token and the right type', () async {
      late http.BaseRequest seen;
      List<int> body = [];
      final client = ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: ApiSession()..accessToken = 'tok',
        client: MockClient((request) async {
          seen = request;
          body = request.bodyBytes;
          return _json(200, {'ok': true});
        }),
      );
      final progress = <int>[];
      final bytes = List<int>.generate(10, (i) => i);
      final result = await client.upload(
        '/v1/artists/me/tracks/t1/audio',
        open: () => Stream.fromIterable([bytes.sublist(0, 4), bytes.sublist(4)]),
        length: 10,
        contentType: 'audio/mpeg',
        onProgress: (sent, total) => progress.add(sent),
      );
      expect(result, {'ok': true});
      expect(seen.method, 'PUT');
      expect(seen.headers['content-type'], 'audio/mpeg');
      expect(seen.headers['authorization'], 'Bearer tok');
      expect(body, bytes);
      expect(progress, [4, 10]);
    });

    test('are sent again after a token refresh', () async {
      var opened = 0;
      var calls = 0;
      final session = ApiSession()..accessToken = 'old';
      session.onUnauthorized = () async {
        session.accessToken = 'new';
        return true;
      };
      final client = ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: session,
        client: MockClient((request) async {
          calls++;
          return request.headers['authorization'] == 'Bearer new' ? _json(200, {'ok': 1}) : _json(401, {'error': 'unauthorized'});
        }),
      );
      await client.upload('/x', open: () {
        opened++;
        return Stream.value([1, 2, 3]);
      }, length: 3, contentType: 'audio/wav');
      expect([opened, calls], [2, 2]);
    });

    test('a file over the limit is refused before anything is sent', () async {
      var sent = false;
      final client = ApiClient(baseUrl: Uri.parse('http://localhost:3000'), session: ApiSession(), client: MockClient((_) async {
        sent = true;
        return _json(200, {});
      }));
      final studio = HttpStudioApi(client);
      final huge = PickedFile(name: 'big.wav', length: HttpStudioApi.maxAudioBytes + 1, open: () => Stream<List<int>>.empty());
      await expectLater(studio.uploadAudio('t1', huge), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'file_too_large')));
      expect(sent, isFalse);
    });

    test('file names turn into suggested titles and content types', () {
      expect(PickedFile(name: '01 - My_Song.mp3', length: 1, open: () => Stream<List<int>>.empty()).suggestedTitle, 'My Song');
      expect(PickedFile(name: 'Plain.wav', length: 1, open: () => Stream<List<int>>.empty()).suggestedTitle, 'Plain');
      expect(audioContentType('a.FLAC'), 'audio/flac');
      expect(audioContentType('a.m4a'), 'audio/mp4');
      expect(imageContentType('cover.PNG'), 'image/png');
      expect(imageContentType('cover.jpg'), 'image/jpeg');
    });
  });

  group('home', () {
    testWidgets('shows what is new, plays the song you tap, and explains an empty catalog', (tester) async {
      final catalog = FakeCatalogApi(fresh: [catalogTrack('id1', 'Night Drive'), catalogTrack('id2', 'Golden Hour')]);
      final playback = _playback();
      await tester.pumpWidget(_host(HomePage(controller: playback, catalog: catalog)));
      await tester.pumpAndSettle();
      expect(find.text('New on Vyro'), findsOneWidget);
      expect(find.text('Night Drive'), findsOneWidget);
      expect(find.text('The most played songs will appear here.'), findsOneWidget);

      await tester.tap(find.text('Golden Hour'));
      await tester.pump();
      await tester.pump();
      expect(playback.current!.id, 'vyro:id2');
      expect(playback.current!.source, TrackSource.vyro);
      expect(playback.queue.length, 2);
      expect(await playback.current!.resolveUri!(), Uri.parse('http://localhost:3000/v1/stream/id2.token'));
    });

    testWidgets('says so when the catalog cannot be reached', (tester) async {
      final catalog = FakeCatalogApi(failWith: const ApiException(0, 'network'));
      await tester.pumpWidget(_host(HomePage(controller: _playback(), catalog: catalog)));
      await tester.pumpAndSettle();
      expect(find.text('Could not load. Pull down to try again.'), findsWidgets);
    });
  });

  group('search', () {
    testWidgets('searches Vyro and this device together, labelled by source', (tester) async {
      final catalog = FakeCatalogApi(all: [catalogTrack('id1', 'Sunrise Drive'), catalogTrack('id2', 'Moon')]);
      final library = LibraryController(store: MemoryLibraryStore(LibrarySnapshot(tracks: [libTrack('Sunny Local'), libTrack('Other')])), scanner: LibraryScanner(readTags: FakeTagReader().call));
      await library.load();
      final playback = _playback();
      await tester.pumpWidget(_host(SearchPage(catalog: catalog, library: library, playback: playback)));
      expect(find.textContaining('one place'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'sun');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(catalog.searches, ['sun']);
      expect(find.text('Sunrise Drive'), findsOneWidget);
      expect(find.text('Sunny Local'), findsOneWidget);
      expect(find.text('Moon'), findsNothing);
      expect(find.text('Vyro'), findsOneWidget);
      expect(find.text('On device'), findsOneWidget);

      await tester.tap(find.text('Sunrise Drive'));
      await tester.pump();
      await tester.pump();
      expect(playback.current!.id, 'vyro:id1');
    });

    testWidgets('waits for typing to pause before asking the server', (tester) async {
      final catalog = FakeCatalogApi(all: [catalogTrack('id1', 'Sunrise')]);
      final library = LibraryController(store: MemoryLibraryStore(), scanner: LibraryScanner(readTags: FakeTagReader().call));
      await tester.pumpWidget(_host(SearchPage(catalog: catalog, library: library, playback: _playback())));
      await tester.enterText(find.byType(TextField), 's');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'su');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'sun');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(catalog.searches, ['sun']);
    });
  });

  group('Studio', () {
    testWidgets('uploads a song with a cover, then publishes it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final studio = FakeStudioApi()..publishStatus = 'published';
      final picker = FakePicker(audio: pickedFile('01 - Night_Drive.mp3', 3 * 1024 * 1024), image: pickedFile('cover.png', 1000));
      await tester.pumpWidget(_host(StudioPage(studio: studio, picker: picker)));

      await tester.tap(find.text('Upload'));
      await tester.pump();
      expect(find.text('Choose an audio file first.'), findsOneWidget);

      await tester.tap(find.text('Choose audio file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('01 - Night_Drive.mp3'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Night Drive'); // title suggested from the file name

      await tester.tap(find.text('Add a cover picture (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
      await tester.pumpAndSettle();
      expect(studio.calls, ['createTrack', 'uploadAudio', 'uploadCover']);
      expect(find.text('"Night Drive" is uploaded'), findsOneWidget);
      expect(find.textContaining('192 kbps'), findsOneWidget);
      expect(find.textContaining('-14.2 LUFS'), findsOneWidget);

      await tester.tap(find.text('Submit for release'));
      await tester.pumpAndSettle();
      expect(studio.calls.last, 'publish');
      expect(find.text('Your song is live on Vyro.'), findsOneWidget);

      await tester.tap(find.text('Upload another song'));
      await tester.pumpAndSettle();
      expect(find.text('Upload a song'), findsOneWidget);
    });

    testWidgets('says a submitted song is waiting for review, or on hold for a copyright check', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final status in ['in_review', 'held']) {
        final studio = FakeStudioApi()..publishStatus = status;
        await tester.pumpWidget(
          _host(
            StudioPage(
              key: ValueKey(status),
              studio: studio,
              picker: FakePicker(audio: pickedFile('song.mp3', 2048)),
            ),
          ),
        );
        // await tester.pumpWidget(_host(StudioPage(studio: studio, picker: FakePicker(audio: pickedFile('song.mp3', 2048)))));
        await tester.tap(find.text('Choose audio file'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Submit for release'));
        await tester.pumpAndSettle();
        expect(find.text('Your song is live on Vyro.'), findsNothing);
        expect(find.textContaining(status == 'held' ? 'quick copyright check' : 'Submitted for review'), findsOneWidget);
        expect(find.text('Submit for release'), findsNothing); // it cannot be submitted twice
      }
    });

    testWidgets('explains a rejected upload, and a retry reuses the same song instead of creating another', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final studio = FakeStudioApi()..failNextUpload = uploadTooLow;
      await tester.pumpWidget(_host(StudioPage(studio: studio, picker: FakePicker(audio: pickedFile('low.mp3', 2048)))));
      await tester.tap(find.text('Choose audio file'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
      await tester.pumpAndSettle();
      expect(find.textContaining('audio quality is too low'), findsOneWidget);
      expect(studio.tracks.length, 1);

      await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
      await tester.pumpAndSettle();
      expect(studio.tracks.length, 1); // still just one song
      expect(studio.calls, ['createTrack', 'uploadAudio', 'uploadAudio']);
      expect(find.text('"low" is uploaded'), findsOneWidget);
    });
  });

  group('Releases', () {
    testWidgets('lists the artist\'s songs and publishes, takes offline and deletes them', (tester) async {
      final studio = FakeStudioApi()..publishStatus = 'published';
      final a = await studio.createTrack(title: 'Ready Song');
      await studio.uploadAudio(a.id, pickedFile('a.mp3', 10));
      await studio.createTrack(title: 'Empty Draft');
      await tester.pumpWidget(_host(ReleasesPage(studio: studio)));
      await tester.pumpAndSettle();
      expect(find.text('Ready Song'), findsOneWidget);
      expect(find.textContaining('Ready to submit'), findsOneWidget);
      expect(find.textContaining('no audio yet'), findsOneWidget);

      await tester.tap(find.byTooltip('Options for Ready Song'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit for release'));
      await tester.pumpAndSettle();
      expect(studio.tracks.firstWhere((t) => t.title == 'Ready Song').isLive, isTrue);
      expect(find.textContaining('Live'), findsOneWidget);

      await tester.tap(find.byTooltip('Options for Ready Song'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take offline'));
      await tester.pumpAndSettle();
      expect(studio.calls, contains('unpublish'));

      await tester.tap(find.byTooltip('Options for Empty Draft'));
      await tester.pumpAndSettle();
      expect(find.text('Submit for release'), findsNothing); // a song without audio cannot be submitted
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Empty Draft'), findsNothing);
    });

    testWidgets('shows where each song stands, why one was not approved, and lets it be fixed and submitted again', (tester) async {
      final studio = FakeStudioApi();
      studio.seed('a', 'Waiting Song', 'in_review');
      studio.seed('b', 'Held Song', 'held');
      studio.seed('c', 'Refused Song', 'rejected', rejectReason: 'low_quality');
      await tester.pumpWidget(_host(ReleasesPage(studio: studio)));
      await tester.pumpAndSettle();
      expect(find.textContaining('In review'), findsOneWidget);
      expect(find.textContaining('On hold for a copyright check'), findsOneWidget);
      expect(find.textContaining('Not approved'), findsOneWidget);
      expect(find.textContaining('Because the audio quality is too low'), findsOneWidget);

      await tester.tap(find.byTooltip('Options for Refused Song'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fix and submit again'));
      await tester.pumpAndSettle();
      expect(studio.calls, contains('publish'));
      expect(studio.tracks.firstWhere((t) => t.id == 'c').status, 'in_review');

      await tester.tap(find.byTooltip('Options for Waiting Song'));
      await tester.pumpAndSettle();
      expect(find.text('Withdraw from review'), findsOneWidget);
      expect(find.text('Submit for release'), findsNothing);
    });

    testWidgets('lets an artist answer a copyright notice with a counter-notice', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final studio = FakeStudioApi();
      studio.seed('t1', 'Taken Song', 'taken_down');
      studio.notices.add(const TakedownInfo(id: 'n1', status: 'open', trackId: 't1', trackTitle: 'Taken Song', claimantName: 'Rights Holder', statement: 'This is my recording.'));
      await tester.pumpWidget(_host(ReleasesPage(studio: studio)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Taken down'), findsOneWidget);

      await tester.tap(find.byTooltip('Options for Taken Song'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing); // a song under a notice cannot be deleted
      await tester.tap(find.text('Send a counter-notice'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rights Holder says'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNull); // needs everything filled in

      await tester.enterText(find.widgetWithText(TextField, 'Why the notice is a mistake (at least 30 characters)'), 'I wrote and recorded this song myself, so the notice is a mistake.');
      await tester.enterText(find.widgetWithText(TextField, 'Your full name, as a signature'), 'Amani Beats');
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send'));
      await tester.pumpAndSettle();
      expect(studio.calls, contains('counterNotice'));
      expect(studio.notices.single.status, 'counter_filed');
    });

    testWidgets('invites the artist to upload when there is nothing yet', (tester) async {
      await tester.pumpWidget(_host(ReleasesPage(studio: FakeStudioApi())));
      await tester.pumpAndSettle();
      expect(find.textContaining('Upload your first one'), findsOneWidget);
    });
  });

  test('review states, reasons and notices read from the server', () {
    final t = StudioTrack.fromJson({'id': 'x', 'title': 'Song', 'status': 'rejected', 'hasAudio': true, 'rejectReason': 'duplicate', 'reviewNote': 'Same as another song'});
    expect(t.canSubmit, isTrue);
    expect(t.statusLabel, 'Not approved');
    expect(rejectReasonText(t.rejectReason), 'it duplicates another song on Vyro');
    expect(rejectReasonText('something-new'), contains('guidelines'));
    for (final status in ['in_review', 'held']) {
      final w = StudioTrack(id: 'w', title: 'W', status: status, hasAudio: true);
      expect([w.isWaiting, w.canSubmit], [true, false]);
    }
    expect(const StudioTrack(id: 'd', title: 'D', status: 'taken_down', hasAudio: true).canSubmit, isFalse);
    expect(const StudioTrack(id: 'n', title: 'N', status: 'ready').canSubmit, isFalse); // no audio
    final n = TakedownInfo.fromJson({'id': 'n1', 'status': 'open', 'track': {'id': 't1', 'title': 'Song'}, 'claimantName': 'Someone', 'statement': 'Mine'});
    expect([n.trackTitle, n.claimantName], ['Song', 'Someone']);
  });

  test('the placeholder catalog is empty and cannot stream', () async {
    const api = EmptyCatalogApi();
    expect(await api.newReleases(), isEmpty);
    await expectLater(api.streamUri('x'), throwsA(isA<ApiException>()));
  });
}
