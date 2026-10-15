import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/brand/vyro_mark.dart';
import 'package:vyro_music/catalog/catalog_widgets.dart';
import 'package:vyro_music/shell/player_ui.dart';
import 'package:vyro_music/shell/queue_page.dart';

import 'catalog_fakes.dart';
import 'fakes.dart';

Track t(String id) => Track(id: id, title: 'Song $id', artist: 'Artist $id', uri: Uri.parse('https://example.com/$id.mp3'), duration: const Duration(minutes: 3));

List<Track> tracks(String ids) => [for (final id in ids.split('')) t(id)];

String order(PlaybackController c) => c.queue.map((x) => x.id).join();

void main() {
  late FakeDeck deckA;
  late PlaybackController c;

  setUp(() {
    deckA = FakeDeck();
    c = PlaybackController(deckA: deckA, deckB: FakeDeck());
  });

  Future<void> start(WidgetTester tester, String ids, {int startIndex = 0}) async {
    unawaited(c.setQueue(tracks(ids), startIndex: startIndex));
    await tester.pump();
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  group('Now Playing', () {
    testWidgets('has a shuffle button that switches shuffle on and off', (tester) async {
      await start(tester, 'abc');
      await tester.pumpWidget(MaterialApp(home: NowPlayingPage(controller: c)));
      await tester.tap(find.byTooltip('Shuffle'));
      await settle(tester);
      expect(c.shuffle, isTrue);
      await tester.tap(find.byTooltip('Shuffle'));
      await settle(tester);
      expect(c.shuffle, isFalse);
    });

    testWidgets('opens the queue', (tester) async {
      await start(tester, 'abc');
      await tester.pumpWidget(MaterialApp(home: NowPlayingPage(controller: c)));
      await tester.tap(find.byTooltip('Queue'));
      await tester.pumpAndSettle();
      expect(find.text('Next up'), findsOneWidget);
      expect(find.text('Song b'), findsOneWidget);
    });

    testWidgets('swiping the artwork sideways changes songs', (tester) async {
      await start(tester, 'abc');
      await tester.pumpWidget(MaterialApp(home: NowPlayingPage(controller: c)));
      await tester.fling(find.byType(VyroMark), const Offset(-300, 0), 1000);
      await settle(tester);
      expect(c.current!.id, 'b');
      await tester.fling(find.byType(VyroMark), const Offset(300, 0), 1000);
      await settle(tester);
      expect(c.current!.id, 'a');
    });

    testWidgets('shows a spinner while the song is buffering, and says when it is reconnecting', (tester) async {
      await start(tester, 'ab');
      await tester.pumpWidget(MaterialApp(home: NowPlayingPage(controller: c)));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      deckA.emitBuffering(true);
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      deckA.emitBuffering(false);
      deckA.emitError(Exception('connection reset'));
      await settle(tester);
      expect(find.text('Reconnecting…'), findsOneWidget);
      c.dispose(); // stops the retry timer
    });
  });

  group('the mini player', () {
    Widget host() => MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer(controller: c))));

    testWidgets('a flick to the left skips to the next song, and to the right goes back', (tester) async {
      await start(tester, 'abc');
      await tester.pumpWidget(host());
      await tester.fling(find.text('Song a'), const Offset(-300, 0), 1000);
      await settle(tester);
      expect(c.current!.id, 'b');
      await tester.fling(find.text('Song b'), const Offset(300, 0), 1000);
      await settle(tester);
      expect(c.current!.id, 'a');
    });

    testWidgets('a flick upwards opens Now Playing', (tester) async {
      await start(tester, 'ab');
      await tester.pumpWidget(host());
      await tester.fling(find.text('Song a'), const Offset(0, -300), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Now playing'), findsOneWidget);
    });

    testWidgets('shows a spinner for buffering and "Reconnecting…" instead of the artist', (tester) async {
      await start(tester, 'ab');
      await tester.pumpWidget(host());
      deckA.emitBuffering(true);
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      deckA.emitError(Exception('connection reset'));
      await settle(tester);
      expect(find.text('Reconnecting…'), findsOneWidget);
      c.dispose();
    });
  });

  group('the queue screen', () {
    Widget host() => MaterialApp(home: QueuePage(controller: c));

    testWidgets('shows what is playing, what is next, and says when nothing is queued', (tester) async {
      await start(tester, 'abc');
      await tester.pumpWidget(host());
      expect(find.text('Now playing'), findsOneWidget);
      for (final id in ['a', 'b', 'c']) {
        expect(find.text('Song $id'), findsOneWidget);
      }
      expect(find.text('Songs you have played will appear here.'), findsOneWidget);

      unawaited(c.clearUpcoming());
      await settle(tester);
      expect(find.text('Nothing is queued after this song.'), findsOneWidget);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Clear queue')).onPressed, isNull); // nothing to clear
    });

    testWidgets('removes a song from the queue', (tester) async {
      await start(tester, 'abcd');
      await tester.pumpWidget(host());
      await tester.tap(find.byTooltip('Remove Song c'));
      await settle(tester);
      expect(order(c), 'abd');
      expect(find.text('Song c'), findsNothing);
      expect(c.current!.id, 'a');
    });

    testWidgets('clears the queue after the current song', (tester) async {
      await start(tester, 'abcd', startIndex: 1);
      await tester.pumpWidget(host());
      await tester.tap(find.text('Clear queue'));
      await settle(tester);
      expect(order(c), 'ab');
    });

    testWidgets('tapping a song in the queue plays it, and the song left behind shows up in the history', (tester) async {
      await start(tester, 'abc');
      await tester.pumpWidget(host());
      await tester.tap(find.text('Song c'));
      await settle(tester);
      expect(c.current!.id, 'c');
      expect(c.history.map((x) => x.id), ['a']);
      expect(find.text('Songs you have played will appear here.'), findsNothing);
    });

    testWidgets('tapping a song in the history plays it again', (tester) async {
      await start(tester, 'abc');
      unawaited(c.next());
      await settle(tester);
      await tester.pumpWidget(host());
      await tester.tap(find.text('Song a')); // the only place 'Song a' appears is the history
      await settle(tester);
      expect(c.current!.id, 'a');
    });

    testWidgets('dragging a song to a new place reorders the queue', (tester) async {
      await start(tester, 'abcd');
      await tester.pumpWidget(host());
      // The list reports a move of the first song to the end as (0, 3): "to" counts the spot after removal.
      tester.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorder(0, 3);
      await settle(tester);
      expect(order(c), 'acdb');
      tester.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorder(1, 0); // the second of the songs still to come, to the front of them
      await settle(tester);
      expect(order(c), 'adcb');
    });

    testWidgets('says when the queue is shuffled', (tester) async {
      await start(tester, 'abc');
      unawaited(c.setShuffle(true));
      await settle(tester);
      await tester.pumpWidget(host());
      expect(find.text('Next up (shuffled)'), findsOneWidget);
    });
  });

  group('song rows', () {
    testWidgets('have a menu to play a song next or add it to the queue', (tester) async {
      await start(tester, 'ab');
      final tile = CatalogTrackTile(track: catalogTrack('9', 'Night Drive'), catalog: FakeCatalogApi(), playback: c, onTap: () {});
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: tile)));

      await tester.tap(find.byTooltip('More options for Night Drive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play next'));
      await tester.pumpAndSettle();
      expect(c.queue[1].title, 'Night Drive');
      expect(find.text('Playing next'), findsOneWidget);

      await tester.tap(find.byTooltip('More options for Night Drive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(c.queue.last.title, 'Night Drive');
      expect(c.queue.length, 4);
    });

    testWidgets('have no menu when there is no player to put the song in', (tester) async {
      final tile = CatalogTrackTile(track: catalogTrack('9', 'Night Drive'), catalog: FakeCatalogApi(), onTap: () {});
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: tile)));
      expect(find.byTooltip('More options for Night Drive'), findsNothing);
    });
  });
}
