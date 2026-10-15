import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/catalog/catalog_widgets.dart';
import 'package:vyro_music/library/library_controller.dart';
import 'package:vyro_music/library/library_models.dart';
import 'package:vyro_music/library/library_page.dart';
import 'package:vyro_music/library/library_platform.dart';
import 'package:vyro_music/library/library_scanner.dart';
import 'package:vyro_music/library/library_settings_page.dart';
import 'package:vyro_music/library/library_store.dart';
import 'package:vyro_music/library/likes_controller.dart';
import 'package:vyro_music/library/likes_scope.dart';
import 'package:vyro_music/library/likes_store.dart';
import 'package:vyro_music/playlists/playlist_store.dart';
import 'package:vyro_music/playlists/playlists_controller.dart';
import 'package:vyro_music/playlists/playlists_scope.dart';
import 'package:vyro_music/shell/player_ui.dart';

import 'catalog_fakes.dart';
import 'fakes.dart';
import 'library_fixtures.dart';

class Platform2 implements LibraryPlatform {
  String? folder;

  @override
  Future<List<String>> defaultRoots() async => [];

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<String?> pickFolder() async => folder;

  @override
  Future<List<String>> pickSongs() async => [];
}

LibraryTrack song(String title, {String genre = 'Pop', String folder = '/music'}) => LibraryTrack(
      id: 'local:$folder/$title.mp3',
      path: '$folder/$title.mp3',
      title: title,
      artist: 'Artist $title',
      album: 'Album',
      genre: genre,
      durationMs: 180000,
      trackNumber: 0,
      year: 0,
      sizeBytes: 1,
      modifiedMs: 1,
      addedMs: 1,
    );

void main() {
  late LibraryController library;
  late PlaybackController playback;
  late PlaylistsController playlists;
  late LikesController likes;
  late FakeCatalogApi catalog;
  late Platform2 platform;
  final deleted = <String>[];
  Object? deleteFailure;

  Future<void> setUpWith(List<LibraryTrack> tracks, {List<String> roots = const [], List<String> excluded = const []}) async {
    deleted.clear();
    deleteFailure = null;
    platform = Platform2();
    catalog = FakeCatalogApi();
    library = LibraryController(
      store: MemoryLibraryStore(LibrarySnapshot(tracks: tracks, roots: roots, excluded: excluded)),
      scanner: LibraryScanner(readTags: FakeTagReader().call),
      platform: platform,
      deleteFile: (path) async {
        final e = deleteFailure;
        if (e != null) throw e;
        deleted.add(path);
      },
    );
    await library.load();
    playback = PlaybackController(deckA: FakeDeck(), deckB: FakeDeck());
    playlists = PlaylistsController(store: MemoryPlaylistStore());
    likes = LikesController(library: library, store: MemoryLikesStore(), catalog: catalog);
  }

  Widget scoped(Widget home) => LikesScope(controller: likes, child: PlaylistsScope(controller: playlists, child: MaterialApp(home: home)));
  Widget page() => scoped(Scaffold(body: LibraryPage(library: library, playback: playback)));

  Future<void> wide(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<void> menu(WidgetTester tester, String song, String item) async {
    await tester.tap(find.byTooltip('More options for $song'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  group('browsing', () {
    testWidgets('genres: songs grouped by genre, each playable', (tester) async {
      await wide(tester);
      await setUpWith([song('Alpha'), song('Beta', genre: 'Jazz'), song('Gamma')]);
      await tester.pumpWidget(page());
      await tester.tap(find.text('Genres'));
      await tester.pumpAndSettle();
      expect(find.text('Jazz'), findsOneWidget);
      expect(find.text('2 songs'), findsOneWidget); // Pop
      await tester.tap(find.text('Jazz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'));
      await tester.pump();
      await tester.pump();
      expect(playback.current!.title, 'Beta');
    });

    testWidgets('folders: songs grouped by where they are, with the full path shown', (tester) async {
      await wide(tester);
      await setUpWith([song('Alpha', folder: '/music/rock'), song('Beta', folder: '/music/jazz'), song('Gamma', folder: '/music/rock')]);
      await tester.pumpWidget(page());
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();
      expect(find.text('jazz'), findsOneWidget);
      expect(find.text('/music/rock · 2 songs'), findsOneWidget);
      await tester.tap(find.text('rock'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Gamma'), findsOneWidget);
    });
  });

  group('liking', () {
    testWidgets('the Liked tab brings songs from the device and from Vyro together, with their sources', (tester) async {
      await wide(tester);
      await setUpWith([song('Alpha'), song('Beta')]);
      await likes.toggle(library.allTracks.first.toPlayable());
      await likes.toggle(catalogTrack('1', 'Night Drive').toPlayable(catalog.streamUri));
      await tester.pumpWidget(page());
      await tester.tap(find.text('Liked'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Night Drive'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Vyro'), findsOneWidget);
      expect(find.text('Beta'), findsNothing); // not liked

      await tester.tap(find.byTooltip('Unlike Night Drive'));
      await tester.pumpAndSettle();
      expect(find.text('Night Drive'), findsNothing);
      await tester.tap(find.text('Alpha'));
      await tester.pump();
      await tester.pump();
      expect(playback.current!.title, 'Alpha');
    });

    testWidgets('says so when nothing is liked yet', (tester) async {
      await wide(tester);
      await setUpWith([song('Alpha')]);
      await tester.pumpWidget(page());
      await tester.tap(find.text('Liked'));
      await tester.pumpAndSettle();
      expect(find.text('Tap the heart on a song to keep it here.'), findsOneWidget);
    });

    testWidgets('Vyro rows have a heart', (tester) async {
      await setUpWith([]);
      await tester.pumpWidget(scoped(Scaffold(body: CatalogTrackTile(track: catalogTrack('1', 'Night Drive'), catalog: catalog, onTap: () {}))));
      await tester.tap(find.byTooltip('Like Night Drive'));
      await tester.pump();
      expect(likes.tracks.single.title, 'Night Drive');
      expect(find.byTooltip('Unlike Night Drive'), findsOneWidget);
    });

    testWidgets('Now Playing has a heart for whatever is playing', (tester) async {
      await setUpWith([song('Alpha')]);
      unawaited(playback.setQueue([library.allTracks.first.toPlayable()]));
      await tester.pump();
      await tester.pumpWidget(scoped(NowPlayingPage(controller: playback)));
      await tester.tap(find.byTooltip('Like'));
      await tester.pump();
      expect(library.isLiked(library.allTracks.first.id), isTrue);
      expect(find.byTooltip('Unlike'), findsOneWidget);
    });
  });

  group('library settings', () {
    testWidgets('lists the folders being used and lets one go', (tester) async {
      await setUpWith([], roots: ['/music/a', '/music/b']);
      await tester.pumpWidget(MaterialApp(home: LibrarySettingsPage(library: library)));
      expect(find.text('/music/a'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove folder /music/a'));
      await tester.pumpAndSettle();
      expect(library.roots, ['/music/b']);
    });

    testWidgets('explains the default when no folder was chosen', (tester) async {
      await setUpWith([]);
      await tester.pumpWidget(MaterialApp(home: LibrarySettingsPage(library: library)));
      expect(find.text("Your device's usual music folders"), findsOneWidget);
    });

    testWidgets('leaves a folder out, and includes it again', (tester) async {
      await setUpWith([song('Alpha', folder: '/music/notes'), song('Beta')]);
      platform.folder = '/music/notes';
      await tester.pumpWidget(MaterialApp(home: LibrarySettingsPage(library: library)));
      expect(find.text('No folders are left out.'), findsOneWidget);
      await tester.tap(find.text('Leave out a folder'));
      await tester.pumpAndSettle();
      expect(find.text('/music/notes'), findsOneWidget);
      expect(library.songs.map((t) => t.title), ['Beta']); // gone at once
      await tester.tap(find.text('Include again'));
      await tester.pumpAndSettle();
      expect(find.text('No folders are left out.'), findsOneWidget);
    });

    testWidgets('changes how short a song can be and still be kept', (tester) async {
      await setUpWith([]);
      await tester.pumpWidget(MaterialApp(home: LibrarySettingsPage(library: library)));
      expect(find.text('30 seconds'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 minute').last);
      await tester.pumpAndSettle();
      expect(library.minSeconds, 60);
      expect(find.text('1 minute'), findsOneWidget);
    });
  });

  group('deleting a song from the device', () {
    testWidgets('asks first; then deletes the file and takes the song out of the library, the queue and the playlists', (tester) async {
      await wide(tester);
      await setUpWith([song('Alpha'), song('Beta')]);
      final alpha = library.allTracks.firstWhere((t) => t.title == 'Alpha');
      final beta = library.allTracks.firstWhere((t) => t.title == 'Beta');
      unawaited(playback.setQueue([alpha.toPlayable(), beta.toPlayable()]));
      final list = await playlists.create('Mine');
      await playlists.addTracks(list.id, [alpha.toPlayable(), beta.toPlayable()]);
      await tester.pumpWidget(page());
      await tester.pump();

      await menu(tester, 'Alpha', 'Delete from device');
      expect(find.text('Delete this song?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);

      await menu(tester, 'Alpha', 'Delete from device');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deleted, [alpha.path]);
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Deleted "Alpha".'), findsWidgets); // shown at the top of the library and as a message
      expect(playback.queue.map((t) => t.title), ['Beta']); // it was playing: playback moved on
      expect(playback.current!.title, 'Beta');
      expect(playlists.byId(list.id)!.entries.map((e) => e.track.title), ['Beta']);
    });

    testWidgets('a song that cannot be deleted stays where it is, and the person is told', (tester) async {
      await wide(tester);
      await setUpWith([song('Alpha')]);
      deleteFailure = Exception('in use');
      await tester.pumpWidget(page());
      await menu(tester, 'Alpha', 'Delete from device');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.textContaining('Could not delete "Alpha"'), findsWidgets);
    });

    testWidgets('only songs on the device have the option', (tester) async {
      await setUpWith([]);
      await tester.pumpWidget(scoped(Scaffold(body: CatalogTrackTile(track: catalogTrack('1', 'Night Drive'), catalog: catalog, playback: playback, onTap: () {}))));
      await tester.tap(find.byTooltip('More options for Night Drive'));
      await tester.pumpAndSettle();
      expect(find.text('Delete from device'), findsNothing);
    });
  });
}
