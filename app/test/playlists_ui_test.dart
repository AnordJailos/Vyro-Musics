import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/catalog/catalog_widgets.dart';
import 'package:vyro_music/playlists/playlist_models.dart';
import 'package:vyro_music/playlists/playlist_page.dart';
import 'package:vyro_music/playlists/playlist_store.dart';
import 'package:vyro_music/playlists/playlists_controller.dart';
import 'package:vyro_music/playlists/playlists_scope.dart';
import 'package:vyro_music/playlists/playlists_tab.dart';
import 'package:vyro_music/shell/player_ui.dart';

import 'catalog_fakes.dart';
import 'fakes.dart';

Track song(String id, {TrackSource source = TrackSource.vyro, int seconds = 180}) => Track(
      id: source == TrackSource.local ? 'local:/music/$id.mp3' : 'vyro:$id',
      title: 'Song $id',
      artist: 'Artist $id',
      uri: source == TrackSource.local ? Uri.file('/music/$id.mp3') : Uri.parse('vyro:$id'),
      source: source,
      duration: Duration(seconds: seconds),
    );

String order(Playlist p) => p.entries.map((e) => e.track.id.replaceAll(RegExp(r'^(vyro:|local:/music/)'), '').replaceAll('.mp3', '')).join();

void main() {
  late PlaylistsController c;
  late PlaybackController playback;
  late FakePicker picker;
  var tick = 0;

  setUp(() {
    tick = 0;
    c = PlaylistsController(store: MemoryPlaylistStore(), clock: () => DateTime.utc(2026, 10, 12, 12, tick++));
    playback = PlaybackController(deckA: FakeDeck(), deckB: FakeDeck());
    picker = FakePicker(image: pickedFile('cover.png', 1000));
  });

  Future<Playlist> seed(String letters, {String name = 'Road trip'}) async {
    final p = await c.create(name);
    await c.addTracks(p.id, [for (final l in letters.split('')) song(l, source: l == 'l' ? TrackSource.local : TrackSource.vyro)]);
    return c.byId(p.id)!;
  }

  Widget scoped(Widget home) => PlaylistsScope(controller: c, picker: picker, child: MaterialApp(home: home));

  /// Shows a start screen with a button, so the playlist page can be left again like in the real app.
  Future<void> openPage(WidgetTester tester, String id) async {
    await tester.pumpWidget(scoped(Builder(
      builder: (context) => Scaffold(body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlistId: id, playback: playback))), child: const Text('open'))),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tall(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> pick(WidgetTester tester, String menuTooltip, String item) async {
    await tester.tap(find.byTooltip(menuTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  group('the Playlists tab', () {
    testWidgets('invites the person to make one, and opens the new playlist', (tester) async {
      await tester.pumpWidget(scoped(Scaffold(body: PlaylistsTab(playback: playback))));
      expect(find.textContaining('Make a playlist'), findsOneWidget);
      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create')).onPressed, isNull); // a name is needed
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Road trip');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(c.playlists.single.name, 'Road trip');
      expect(find.text('No songs yet. Use the menu on any song and choose "Add to playlist".'), findsOneWidget); // the page opened
    });

    testWidgets('lists playlists with their size and length', (tester) async {
      await seed('ab', name: 'Two songs');
      await seed('a', name: 'One song');
      await tester.pumpWidget(scoped(Scaffold(body: PlaylistsTab(playback: playback))));
      expect(find.text('2 songs · 6 min'), findsOneWidget);
      expect(find.text('1 song · 3 min'), findsOneWidget);
      await tester.tap(find.text('Two songs'));
      await tester.pumpAndSettle();
      expect(find.text('Song a'), findsOneWidget);
    });
  });

  group('a playlist', () {
    testWidgets('shows each song with where it comes from, and plays from the one tapped', (tester) async {
      await tall(tester);
      final p = await seed('abl');
      await openPage(tester, p.id);
      expect(find.text('Vyro'), findsNWidgets(2));
      expect(find.text('Local'), findsOneWidget);
      await tester.tap(find.text('Song b'));
      await tester.pump();
      await tester.pump();
      expect(playback.current!.id, 'vyro:b');
      expect(playback.queue.length, 3);
    });

    testWidgets('Play starts from the top, and Shuffle turns shuffle on', (tester) async {
      await tall(tester);
      final p = await seed('abc');
      await openPage(tester, p.id);
      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.pump();
      expect([playback.current!.id, playback.shuffle], ['vyro:a', false]);
      await tester.tap(find.text('Shuffle'));
      await tester.pump();
      await tester.pump();
      expect(playback.shuffle, isTrue);
      expect(playback.queue.length, 3);
    });

    testWidgets('dragging a song changes the order for good', (tester) async {
      await tall(tester);
      final p = await seed('abcd');
      await openPage(tester, p.id);
      tester.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorder(0, 3); // the list reports the place after removal
      await tester.pumpAndSettle();
      expect(order(c.byId(p.id)!), 'bcad');
    });

    testWidgets('selects songs with a long press, and removes them all at once', (tester) async {
      await tall(tester);
      final p = await seed('abcd');
      await openPage(tester, p.id);
      await tester.longPress(find.text('Song a'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('Song c'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove selected'));
      await tester.pumpAndSettle();
      expect(order(c.byId(p.id)!), 'bd');
      expect(find.byType(Checkbox), findsNothing); // back to normal
    });

    testWidgets('selects everything, and adds the selection to the queue in playlist order', (tester) async {
      await tall(tester);
      final p = await seed('abc');
      await openPage(tester, p.id);
      await tester.tap(find.byTooltip('Select songs'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Add selected to queue'));
      await tester.pumpAndSettle();
      expect(playback.queue.map((t) => t.id), ['vyro:a', 'vyro:b', 'vyro:c']);
    });

    testWidgets('sorts, and removes duplicates', (tester) async {
      await tall(tester);
      final p = await seed('cab');
      await c.addTracks(p.id, [song('a'), song('b')], allowDuplicates: true);
      await openPage(tester, p.id);
      await pick(tester, 'Playlist options', 'Sort by title');
      expect(order(c.byId(p.id)!), 'aabbc');
      await pick(tester, 'Playlist options', 'Remove duplicates');
      expect(order(c.byId(p.id)!), 'abc');
      expect(find.text('Removed 2 duplicates.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6)); // let the first message go, so the next one shows
      await tester.pumpAndSettle();
      await pick(tester, 'Playlist options', 'Remove duplicates');
      expect(find.text('There are no duplicates.'), findsOneWidget);
    });

    testWidgets('each song has a menu: play next, add to queue, remove from the playlist', (tester) async {
      await tall(tester);
      final p = await seed('abc');
      await openPage(tester, p.id);
      await tester.tap(find.text('Song a')); // something is playing
      await tester.pump();
      await tester.pump();
      await pick(tester, 'Options for Song c', 'Play next');
      expect(playback.queue[1].id, 'vyro:c');
      await pick(tester, 'Options for Song b', 'Add to queue');
      expect(playback.queue.last.id, 'vyro:b');
      await pick(tester, 'Options for Song b', 'Remove from playlist');
      expect(order(c.byId(p.id)!), 'ac');
    });

    testWidgets('edits the name, the description and the cover picture', (tester) async {
      await tall(tester);
      final p = await seed('a');
      await openPage(tester, p.id);
      await pick(tester, 'Playlist options', 'Edit details');
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Night drive');
      await tester.enterText(find.widgetWithText(TextField, 'Description'), 'After dark');
      await tester.tap(find.text('Choose cover picture'));
      await tester.pumpAndSettle();
      expect(find.text('Remove cover'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      final after = c.byId(p.id)!;
      expect([after.name, after.description, after.coverPath != null], ['Night drive', 'After dark', true]);
      expect(find.text('After dark'), findsOneWidget);
    });

    testWidgets('will not save an empty name', (tester) async {
      await tall(tester);
      final p = await seed('a');
      await openPage(tester, p.id);
      await pick(tester, 'Playlist options', 'Edit details');
      await tester.enterText(find.widgetWithText(TextField, 'Name'), '   ');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    });

    testWidgets('deletes the playlist after asking, and leaves the page', (tester) async {
      await tall(tester);
      final p = await seed('a');
      await openPage(tester, p.id);
      await pick(tester, 'Playlist options', 'Delete playlist');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.playlists.length, 1);
      await pick(tester, 'Playlist options', 'Delete playlist');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(c.playlists, isEmpty);
      expect(find.text('open'), findsOneWidget); // back on the screen before
    });
  });

  group('adding a song to a playlist from anywhere', () {
    Widget row() => scoped(Scaffold(body: CatalogTrackTile(track: catalogTrack('9', 'Night Drive'), catalog: FakeCatalogApi(), playback: playback, onTap: () {})));

    testWidgets('the song menu offers it, the sheet lists playlists, and a repeat is noticed', (tester) async {
      final p = await seed('a', name: 'Favourites');
      await tester.pumpWidget(row());
      await pick(tester, 'More options for Night Drive', 'Add to playlist');
      expect(find.text('Add to playlist'), findsOneWidget); // the sheet
      expect(find.text('1 song'), findsOneWidget);
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();
      expect(find.text('Added to "Favourites"'), findsOneWidget);
      expect(c.byId(p.id)!.entries.last.track.title, 'Night Drive');
      await tester.pump(const Duration(seconds: 6)); // let the first message go, so the next one shows
      await tester.pumpAndSettle();

      await pick(tester, 'More options for Night Drive', 'Add to playlist');
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();
      expect(find.text('Already in "Favourites"'), findsOneWidget);
      expect(c.byId(p.id)!.entries.length, 2);
      await tester.tap(find.text('Add anyway'));
      await tester.pumpAndSettle();
      expect(c.byId(p.id)!.entries.length, 3);
    });

    testWidgets('can make a new playlist on the spot', (tester) async {
      await tester.pumpWidget(row());
      await pick(tester, 'More options for Night Drive', 'Add to playlist');
      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Fresh');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(c.playlists.single.name, 'Fresh');
      expect(c.playlists.single.entries.single.track.title, 'Night Drive');
    });

    testWidgets('without playlists in the app, the menu does not offer it', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CatalogTrackTile(track: catalogTrack('9', 'Night Drive'), catalog: FakeCatalogApi(), playback: playback, onTap: () {}))));
      await tester.tap(find.byTooltip('More options for Night Drive'));
      await tester.pumpAndSettle();
      expect(find.text('Play next'), findsOneWidget);
      expect(find.text('Add to playlist'), findsNothing);
    });

    testWidgets('Now Playing can add the current song', (tester) async {
      final p = await seed('a', name: 'Favourites');
      unawaited(playback.setQueue([song('z')]));
      await tester.pump();
      await tester.pumpWidget(scoped(NowPlayingPage(controller: playback)));
      await tester.tap(find.byTooltip('Add to playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();
      expect(c.byId(p.id)!.entries.last.track.id, 'vyro:z');
    });
  });
}
