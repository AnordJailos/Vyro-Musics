import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/catalog/artist_page.dart';
import 'package:vyro_music/catalog/catalog_models.dart';
import 'package:vyro_music/catalog/charts_page.dart';
import 'package:vyro_music/catalog/recent_searches.dart';
import 'package:vyro_music/catalog/search_page.dart';
import 'package:vyro_music/history/history_store.dart';
import 'package:vyro_music/history/play_record.dart';
import 'package:vyro_music/library/library_controller.dart';
import 'package:vyro_music/library/library_scanner.dart';
import 'package:vyro_music/library/library_store.dart';
import 'package:vyro_music/shell/pages.dart';

import 'catalog_fakes.dart';
import 'fakes.dart';
import 'library_fixtures.dart';

ArtistPageData page({String id = 'a1', String name = 'Nova Wave', bool verified = true, int followers = 12, bool following = false}) => ArtistPageData(
      artist: ArtistSummary(id: id, stageName: name, verified: verified, followers: followers),
      bio: 'Afro fusion from Nairobi.',
      genres: const ['afrobeats'],
      links: const [ArtistLink(label: 'Instagram', url: 'https://instagram.com/nova')],
      monthlyListeners: 340,
      following: following,
      // the songs credit another name, so the artist's own name appears once on the page
      topTracks: [catalogTrack('1', 'Night Drive', artist: 'Feat Friend', artistId: id)],
      discography: [catalogTrack('1', 'Night Drive', artist: 'Feat Friend', artistId: id), catalogTrack('2', 'Sunrise Run', artist: 'Feat Friend', artistId: id)],
      similar: const [ArtistSummary(id: 'a2', stageName: 'Zuri', followers: 1)],
    );

void main() {
  late FakeCatalogApi catalog;
  late PlaybackController playback;
  late LibraryController library;
  late RecentSearches recents;

  setUp(() {
    catalog = FakeCatalogApi();
    playback = PlaybackController(deckA: FakeDeck(), deckB: FakeDeck());
    library = LibraryController(store: MemoryLibraryStore(LibrarySnapshot()), scanner: LibraryScanner(readTags: FakeTagReader().call));
    recents = RecentSearches(store: MemoryRecentSearchStore());
  });

  Future<void> tall(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Widget host(Widget home) => RecentSearchesScope(controller: recents, child: MaterialApp(home: Scaffold(body: home)));
  Widget searchPage({String? country}) => host(SearchPage(catalog: catalog, library: library, playback: playback, country: country));

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  group('searching', () {
    testWidgets('shows artists above songs, and opens an artist', (tester) async {
      await tall(tester);
      catalog = FakeCatalogApi(all: [catalogTrack('1', 'Nova Night', artist: 'Someone')])
        ..artists = [const ArtistSummary(id: 'a1', stageName: 'Nova Wave', verified: true, followers: 12)]
        ..pages['a1'] = page();
      await tester.pumpWidget(searchPage());
      await type(tester, 'nova');
      expect(find.text('Artist · 12 followers'), findsOneWidget);
      expect(find.text('Nova Night'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Nova Wave')).dy, lessThan(tester.getTopLeft(find.text('Nova Night')).dy));
      await tester.tap(find.text('Nova Wave'));
      await tester.pumpAndSettle();
      expect(find.text('Afro fusion from Nairobi.'), findsOneWidget); // the artist page
    });

    testWidgets('remembers a search when it is submitted or a result is used', (tester) async {
      await tall(tester);
      catalog = FakeCatalogApi(all: [catalogTrack('1', 'Night Drive')]);
      await tester.pumpWidget(searchPage());
      await tester.enterText(find.byType(TextField), 'night');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(recents.items, ['night']);
      await type(tester, 'drive');
      await tester.tap(find.text('Night Drive'));
      await tester.pump();
      expect(recents.items, ['drive', 'night']);
    });

    testWidgets('suggests while there are only one or two letters, and not after', (tester) async {
      await tall(tester);
      catalog = FakeCatalogApi()
        ..suggestions = [const Suggestion(kind: 'artist', id: 'a1', text: 'Nova Wave', subtitle: 'Artist'), const Suggestion(kind: 'song', id: 's1', text: 'Night Drive', subtitle: 'Nova Wave')]
        ..pages['a1'] = page();
      await tester.pumpWidget(searchPage());
      await type(tester, 'n');
      expect(find.text('Suggestions'), findsOneWidget);
      expect(find.text('Night Drive'), findsOneWidget);
      await tester.tap(find.text('Night Drive')); // a song suggestion fills in the search
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Night Drive');
      expect(find.text('Suggestions'), findsNothing); // a full search has begun

      await type(tester, 'no');
      await tester.tap(find.text('Nova Wave').first); // an artist suggestion opens the artist
      await tester.pumpAndSettle();
      expect(find.text('Afro fusion from Nairobi.'), findsOneWidget);
      expect(catalog.suggestQueries, ['n', 'no']); // none for "Night Drive"
    });

    testWidgets('with nothing typed, shows recent searches that can be used, removed and cleared', (tester) async {
      await recents.add('nova');
      await recents.add('kito');
      await tester.pumpWidget(searchPage());
      expect(find.text('Recent searches'), findsOneWidget);
      await tester.tap(find.text('nova'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(catalog.searches, ['nova']);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'nova');

      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove kito'));
      await tester.pumpAndSettle();
      expect(recents.items, ['nova']);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Recent searches'), findsNothing);
    });

    testWidgets('with nothing typed, offers genres to browse and the charts', (tester) async {
      await tall(tester);
      catalog = FakeCatalogApi(top: [catalogTrack('9', 'Chart Hit')])
        ..genreCounts = const [GenreCount('afrobeats', 3), GenreCount('hip hop', 2)]
        ..genreSongs['afrobeats'] = [catalogTrack('1', 'Night Drive')];
      await tester.pumpWidget(searchPage());
      await tester.pumpAndSettle();
      expect(find.text('Afrobeats (3)'), findsOneWidget);
      expect(find.text('Hip Hop (2)'), findsOneWidget);
      await tester.tap(find.text('Afrobeats (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Night Drive'), findsOneWidget);
      await tester.tap(find.text('Most played'));
      await tester.pumpAndSettle();
      expect(catalog.chartRequests, ['genre:afrobeats:new', 'genre:afrobeats:popular']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Charts'));
      await tester.pumpAndSettle();
      expect(find.text('Chart Hit'), findsOneWidget);
    });
  });

  group('the artist page', () {
    Future<void> open(WidgetTester tester, {String id = 'a1'}) async {
      await tall(tester);
      await tester.pumpWidget(host(ArtistPage(artistId: id, catalog: catalog, playback: playback)));
      await tester.pumpAndSettle();
    }

    testWidgets('shows who the artist is, their songs, about, and similar artists', (tester) async {
      catalog.pages['a1'] = page();
      await open(tester);
      expect(find.text('Nova Wave'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.text('12 followers · 340 monthly listeners'), findsOneWidget);
      expect(find.text('Afrobeats'), findsOneWidget);
      expect(find.text('Night Drive'), findsNWidgets(2)); // Popular, and Songs
      expect(find.text('Sunrise Run'), findsOneWidget);
      expect(find.text('Afro fusion from Nairobi.'), findsOneWidget);
      expect(find.text('Instagram: https://instagram.com/nova'), findsOneWidget);
      expect(find.text('Zuri'), findsOneWidget);
    });

    testWidgets('plays the popular songs, or shuffles all of them', (tester) async {
      catalog.pages['a1'] = page();
      await open(tester);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(playback.queue.map((t) => t.title), ['Night Drive']);
      await tester.tap(find.text('Shuffle'));
      await tester.pumpAndSettle();
      expect([playback.shuffle, playback.queue.length], [true, 2]);
    });

    testWidgets('follows and unfollows, with the count following along', (tester) async {
      catalog.pages['a1'] = page();
      await open(tester);
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('13 followers · 340 monthly listeners'), findsOneWidget);
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('12 followers · 340 monthly listeners'), findsOneWidget);
      expect(catalog.follows, ['follow:a1', 'unfollow:a1']);
    });

    testWidgets('a guest who tries to follow is told to sign in, and nothing changes', (tester) async {
      catalog.pages['a1'] = page();
      catalog.followFailure = const ApiException(401, 'unauthorized');
      await open(tester);
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to follow artists.'), findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);
      expect(find.text('12 followers · 340 monthly listeners'), findsOneWidget);
    });

    testWidgets('opens a similar artist', (tester) async {
      catalog.pages['a1'] = page();
      catalog.pages['a2'] = page(id: 'a2', name: 'Zuri', verified: false, followers: 1);
      await open(tester);
      await tester.tap(find.text('Zuri'));
      await tester.pumpAndSettle();
      expect(find.text('1 follower · 340 monthly listeners'), findsOneWidget);
    });

    testWidgets('says so when the artist is gone, and offers a retry when the page cannot be loaded', (tester) async {
      await open(tester, id: 'nobody');
      expect(find.text('This artist is not available.'), findsOneWidget);

      catalog.pageFailure = const ApiException(0, 'network');
      catalog.pages['a1'] = page();
      await tester.pumpWidget(host(ArtistPage(artistId: 'a1', catalog: catalog, playback: playback)));
      await tester.pumpAndSettle();
      expect(find.text('Could not load this artist.'), findsOneWidget);
      catalog.pageFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Afro fusion from Nairobi.'), findsOneWidget);
    });
  });

  group('charts', () {
    ArtistChartEntry entry(int rank, String id, String name, int plays, {int? change}) => ArtistChartEntry(rank: rank, artist: ArtistSummary(id: id, stageName: name, verified: rank == 1), plays: plays, change: change);

    testWidgets('top songs, top artists and rising artists, each on its own tab', (tester) async {
      await tall(tester);
      catalog = FakeCatalogApi(top: [catalogTrack('1', 'Night Drive')])
        ..chartTop = [entry(1, 'a1', 'Nova Wave', 120), entry(2, 'a2', 'Zuri', 80)]
        ..chartRising = [entry(1, 'a2', 'Zuri', 30, change: 20)]
        ..pages['a2'] = page(id: 'a2', name: 'Zuri', verified: false, followers: 1);
      await tester.pumpWidget(host(ChartsPage(catalog: catalog, playback: playback)));
      await tester.pumpAndSettle();
      expect(find.text('Night Drive'), findsOneWidget);
      expect(find.text('Worldwide'), findsNothing); // no country known, so no choice
      await tester.tap(find.text('Top artists'));
      await tester.pumpAndSettle();
      expect(find.text('120 plays in the last 28 days'), findsOneWidget);
      expect(find.text('Zuri'), findsOneWidget);
      await tester.tap(find.text('Rising'));
      await tester.pumpAndSettle();
      expect(find.text('30 plays this week, 20 more than the week before'), findsOneWidget);
      await tester.tap(find.text('Zuri'));
      await tester.pumpAndSettle();
      expect(find.text('1 follower · 340 monthly listeners'), findsOneWidget); // the artist's page
    });

    testWidgets('can show the person\'s own country instead of the whole world', (tester) async {
      await tall(tester);
      await tester.pumpWidget(host(ChartsPage(catalog: catalog, playback: playback, country: 'KE')));
      await tester.pumpAndSettle();
      expect(catalog.chartRequests, ['songs:world', 'artists:top:world', 'artists:rising:world']);
      await tester.tap(find.text('My country (KE)'));
      await tester.pumpAndSettle();
      expect(catalog.chartRequests.skip(3), ['songs:KE', 'artists:top:KE', 'artists:rising:KE']);
    });

    testWidgets('says so when nothing has been played', (tester) async {
      await tester.pumpWidget(host(ChartsPage(catalog: catalog, playback: playback)));
      await tester.pumpAndSettle();
      expect(find.text('Nothing has been played yet.'), findsOneWidget);
      await tester.tap(find.text('Rising'));
      await tester.pumpAndSettle();
      expect(find.text('No artist is rising right now.'), findsOneWidget);
    });
  });

  group('Home', () {
    PlayRecord record(String id, int minutesAgo) => PlayRecord(
          id: 'r$id',
          trackId: id,
          source: 'vyro',
          title: 'Song $id',
          artist: 'Artist $id',
          startedAt: DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo)),
          listenedMs: 90000,
          durationMs: 200000,
          mode: 'normal',
          origin: 'search',
          platform: 'android',
        );

    testWidgets('has "Continue listening" with what was played lately, and a Charts button', (tester) async {
      await tall(tester);
      final history = MemoryHistoryStore();
      await history.append(record('a', 30));
      await history.append(record('b', 5));
      catalog = FakeCatalogApi(top: [catalogTrack('9', 'Chart Hit')]);
      await tester.pumpWidget(host(HomePage(controller: playback, catalog: catalog, history: history, country: 'KE')));
      await tester.pumpAndSettle();
      expect(find.text('Continue listening'), findsOneWidget);
      final newest = tester.getTopLeft(find.text('Song b')).dy;
      expect(newest, lessThan(tester.getTopLeft(find.text('Song a')).dy)); // newest first
      await tester.tap(find.text('Song a'));
      await tester.pump();
      await tester.pump();
      expect(playback.current!.id, 'vyro:a');
      expect(playback.queue.map((t) => t.id), ['vyro:b', 'vyro:a']);

      await tester.tap(find.text('Charts'));
      await tester.pumpAndSettle();
      expect(find.text('My country (KE)'), findsOneWidget);
    });

    testWidgets('has no such row without history, and an artist\'s name on a song opens their page', (tester) async {
      await tall(tester);
      catalog = FakeCatalogApi(fresh: [catalogTrack('1', 'Night Drive', artistId: 'a1')])..pages['a1'] = page();
      await tester.pumpWidget(host(HomePage(controller: playback, catalog: catalog)));
      await tester.pumpAndSettle();
      expect(find.text('Continue listening'), findsNothing);
      await tester.tap(find.text('Nova Wave').first); // the artist under the song
      await tester.pumpAndSettle();
      expect(find.text('Afro fusion from Nairobi.'), findsOneWidget);
    });
  });
}
