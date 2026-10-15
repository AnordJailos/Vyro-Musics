import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/auth/api_client.dart';
import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/auth/screens/account_page.dart';
import 'package:vyro_music/catalog/catalog_api.dart';
import 'package:vyro_music/catalog/catalog_models.dart';
import 'package:vyro_music/shell/pages.dart';

import 'auth_fakes.dart';
import 'catalog_fakes.dart';
import 'fakes.dart';

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> trackJson(String id, String title) => {
      'id': id,
      'title': title,
      'artist': {'id': 'artist-$id', 'stageName': 'Nova Wave'},
      'durationMs': 200000,
    };

RecSection section(String id, String kind, String title, List<CatalogTrack> tracks, {String reason = ''}) => RecSection(id: id, kind: kind, title: title, reason: reason, tracks: tracks);

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

    test('reads the suggestion sections, with their reasons and songs', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) => _json(200, {
            'sections': [
              {'id': 'for_you', 'kind': 'for_you', 'title': 'Picked for you', 'reason': 'Based on the genres and artists you chose', 'tracks': [trackJson('1', 'Night Drive'), trackJson('2', 'Sunrise')]},
              {'id': 'editorial:x', 'kind': 'editorial', 'title': 'Late night', 'reason': '', 'tracks': <Object>[]},
            ],
          }), seen);
      final sections = await api.recommendations();
      expect([seen.single.method, seen.single.url.path], ['GET', '/v1/recommendations/home']);
      expect(sections.map((s) => [s.id, s.kind, s.title, s.tracks.length]), [
        ['for_you', 'for_you', 'Picked for you', 2],
        ['editorial:x', 'editorial', 'Late night', 0],
      ]);
      expect(sections.first.reason, startsWith('Based on'));
      expect(sections.first.tracks.first.title, 'Night Drive');
    });

    test('sends "not interested" and the reset', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) => http.Response('', 204), seen);
      await api.notInterested(kind: 'artist', id: 'abc');
      await api.resetRecommendations();
      expect([seen[0].method, seen[0].url.path, jsonDecode(seen[0].body)], ['POST', '/v1/recommendations/not-interested', {'kind': 'artist', 'id': 'abc'}]);
      expect([seen[1].method, seen[1].url.path], ['DELETE', '/v1/recommendations']);
    });
  });

  group('Home', () {
    late FakeCatalogApi catalog;
    late PlaybackController playback;

    setUp(() => playback = PlaybackController(deckA: FakeDeck(), deckB: FakeDeck()));

    Future<void> show(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomePage(controller: playback, catalog: catalog))));
      await tester.pumpAndSettle();
    }

    Future<void> menu(WidgetTester tester, String song, String item) async {
      await tester.tap(find.byTooltip('More options for $song'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('shows suggestions above the rest, with the reason for each row of songs', (tester) async {
      catalog = FakeCatalogApi(fresh: [catalogTrack('9', 'Brand New')])
        ..recs = [
          section('for_you', 'for_you', 'Picked for you', [catalogTrack('1', 'Night Drive')], reason: 'Based on the genres and artists you chose'),
          section('popular', 'popular', 'Popular in Kenya', [catalogTrack('2', 'Sunrise')]),
          section('editorial:x', 'editorial', 'Late night', [catalogTrack('3', 'Moonlight')], reason: 'For after dark'),
        ];
      await show(tester);
      for (final t in ['Picked for you', 'Popular in Kenya', 'Late night', 'Night Drive', 'Sunrise', 'Moonlight']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text('Based on the genres and artists you chose'), findsOneWidget);
      expect(find.text('For after dark'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Picked for you')).dy, lessThan(tester.getTopLeft(find.text('New on Vyro')).dy));
    });

    testWidgets('tapping a suggestion plays that row as the queue', (tester) async {
      catalog = FakeCatalogApi()..recs = [section('for_you', 'for_you', 'Picked for you', [catalogTrack('1', 'Night Drive'), catalogTrack('2', 'Sunrise'), catalogTrack('3', 'Moonlight')])];
      await show(tester);
      await tester.tap(find.text('Sunrise'));
      await tester.pump();
      await tester.pump();
      expect(playback.current!.title, 'Sunrise');
      expect(playback.queue.map((t) => t.title), ['Night Drive', 'Sunrise', 'Moonlight']);
    });

    testWidgets('carries on when suggestions cannot be loaded', (tester) async {
      catalog = FakeCatalogApi(fresh: [catalogTrack('9', 'Brand New')])..recsFailure = const ApiException(0, 'network');
      await show(tester);
      expect(find.text('Brand New'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing); // suggestions are a bonus, not an error
    });

    testWidgets('"Not interested" hides the song and tells Vyro', (tester) async {
      catalog = FakeCatalogApi()..recs = [section('for_you', 'for_you', 'Picked for you', [catalogTrack('1', 'Night Drive'), catalogTrack('2', 'Sunrise')])];
      await show(tester);
      await menu(tester, 'Night Drive', 'Not interested');
      expect(find.text('Night Drive'), findsNothing);
      expect(find.text('Sunrise'), findsOneWidget);
      expect(catalog.dismissed, ['track:1']);
      expect(find.text('OK, we will suggest fewer songs like this.'), findsOneWidget);
    });

    testWidgets('"Don\'t suggest this artist" hides all their songs, and a row with nothing left disappears', (tester) async {
      catalog = FakeCatalogApi()
        ..recs = [
          section('for_you', 'for_you', 'Picked for you', [
            catalogTrack('1', 'Night Drive', artistId: 'same'),
            catalogTrack('2', 'Sunrise', artistId: 'same'),
            catalogTrack('3', 'Moonlight', artistId: 'other'),
          ]),
          section('popular', 'popular', 'Popular on Vyro', [catalogTrack('4', 'Daybreak', artistId: 'same')]),
        ];
      await show(tester);
      await menu(tester, 'Night Drive', "Don't suggest this artist");
      expect(find.text('Night Drive'), findsNothing);
      expect(find.text('Sunrise'), findsNothing);
      expect(find.text('Moonlight'), findsOneWidget);
      expect(find.text('Popular on Vyro'), findsNothing); // its only song was by that artist
      expect(catalog.dismissed, ['artist:same']);
    });

    testWidgets('the ordinary song rows have no "Not interested"', (tester) async {
      catalog = FakeCatalogApi(fresh: [catalogTrack('9', 'Brand New')]);
      await show(tester);
      await tester.tap(find.byTooltip('More options for Brand New'));
      await tester.pumpAndSettle();
      expect(find.text('Play next'), findsOneWidget);
      expect(find.text('Not interested'), findsNothing);
    });
  });

  group('Account', () {
    testWidgets('resets recommendations after asking', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var resets = 0;
      final auth = await signedIn(FakeAuthApi());
      await tester.pumpWidget(MaterialApp(home: AccountPage(auth: auth, onResetRecommendations: () async => resets++)));
      await tester.tap(find.text('Reset recommendations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(resets, 0);
      await tester.tap(find.text('Reset recommendations'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await tester.pumpAndSettle();
      expect(resets, 1);
      expect(find.text('Recommendations reset.'), findsOneWidget);
    });

    testWidgets('has no such option when there is nothing to reset', (tester) async {
      final auth = await signedIn(FakeAuthApi());
      await tester.pumpWidget(MaterialApp(home: AccountPage(auth: auth)));
      expect(find.text('Reset recommendations'), findsNothing);
    });
  });
}
