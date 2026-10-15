import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/library/library_controller.dart';
import 'package:vyro_music/library/library_index.dart';
import 'package:vyro_music/library/library_models.dart';
import 'package:vyro_music/library/library_platform.dart';
import 'package:vyro_music/library/library_scanner.dart';
import 'package:vyro_music/library/library_store.dart';
import 'package:vyro_music/playlists/playlist_store.dart';
import 'package:vyro_music/playlists/playlists_controller.dart';

import 'fakes.dart';
import 'library_fixtures.dart';

class Platform1 implements LibraryPlatform {
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

LibraryTrack inGenre(String title, String genre, String path) => LibraryTrack(
      id: 'local:$path',
      path: path,
      title: title,
      artist: 'A',
      album: 'Al',
      genre: genre,
      durationMs: 180000,
      trackNumber: 0,
      year: 0,
      sizeBytes: 1,
      modifiedMs: 1,
      addedMs: 1,
    );

void main() {
  group('genres and folders', () {
    test('genres group songs whatever the capital letters, sort by name, and put "no genre" last', () {
      final groups = genresOf([
        inGenre('b', 'Pop', '/m/b.mp3'),
        inGenre('a', 'pop', '/m/a.mp3'),
        inGenre('c', 'Jazz', '/m/c.mp3'),
        inGenre('d', 'Unknown genre', '/m/d.mp3'),
        inGenre('e', 'Afrobeats', '/m/e.mp3'),
      ]);
      expect(groups.map((g) => g.name), ['Afrobeats', 'Jazz', 'Pop', 'Unknown genre']);
      expect(groups[2].tracks.map((t) => t.title), ['a', 'b']);
    });

    test('folders group songs by where the file is, on any kind of device, and show the last part of the path', () {
      final groups = foldersOf([
        inGenre('a', 'Pop', '/storage/Music/Rock/a.mp3'),
        inGenre('b', 'Pop', '/storage/Music/rock/b.mp3'),
        inGenre('c', 'Pop', 'C:\\Users\\me\\Music\\Jazz\\c.mp3'),
        inGenre('d', 'Pop', '/storage/Music/Afro/d.mp3'),
      ]);
      expect(groups.map((g) => g.name), ['Afro', 'Jazz', 'Rock']);
      expect(groups.last.tracks.map((t) => t.title), ['a', 'b']); // "Rock" and "rock" are one folder
      expect(groups[1].path, 'C:/Users/me/Music/Jazz');
      expect(folderOf('/a/b/c.mp3'), '/a/b');
    });

    test('the controller offers both, from the songs that match the search', () async {
      final c = LibraryController(
        store: MemoryLibraryStore(LibrarySnapshot(tracks: [inGenre('Alpha', 'Pop', '/m/x/alpha.mp3'), inGenre('Beta', 'Jazz', '/m/y/beta.mp3')])),
        scanner: LibraryScanner(readTags: FakeTagReader().call),
      );
      await c.load();
      expect([c.genres.length, c.folders.length], [2, 2]);
      c.setQuery('beta');
      expect([c.genres.map((g) => g.name), c.folders.map((f) => f.name)], [['Jazz'], ['y']]);
    });
  });

  group('what the scan looks at', () {
    late Directory root;
    late FakeTagReader reader;
    late MemoryLibraryStore store;
    late Platform1 platform;

    LibraryController controller({Future<void> Function(String)? deleter}) => LibraryController(
          store: store,
          scanner: LibraryScanner(readTags: reader.call),
          platform: platform,
          deleteFile: deleter ?? deleteFileFromDisk,
        );

    setUp(() {
      root = Directory.systemTemp.createTempSync('vyro_lib_');
      reader = FakeTagReader();
      store = MemoryLibraryStore(LibrarySnapshot(roots: [root.path]));
      platform = Platform1();
      for (final f in ['alpha.mp3', 'notes/memo.mp3', 'short.mp3', 'tiny.mp3']) {
        makeAudio(root, f);
      }
      reader.byFileName['alpha.mp3'] = const TagInfo(title: 'Alpha', duration: Duration(minutes: 3));
      reader.byFileName['memo.mp3'] = const TagInfo(title: 'Memo', duration: Duration(minutes: 2));
      reader.byFileName['short.mp3'] = const TagInfo(title: 'Short', duration: Duration(seconds: 20));
      reader.byFileName['tiny.mp3'] = const TagInfo(title: 'Tiny', duration: Duration(seconds: 5));
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('a folder left out disappears at once, stays out when the device is scanned again, and comes back when included', () async {
      final c = controller();
      await c.load();
      await c.scan();
      expect(c.songs.map((t) => t.title), ['Alpha', 'Memo']);
      platform.folder = '${root.path}/notes';
      await c.addExcludedFolder();
      expect(c.songs.map((t) => t.title), ['Alpha']);
      expect(c.excludedFolders, ['${root.path}/notes']);
      await c.scan();
      expect(c.songs.map((t) => t.title), ['Alpha']);
      expect(store.snapshot.excluded.length, 1); // remembered
      await c.removeExcludedFolder('${root.path}/notes');
      expect(c.songs.map((t) => t.title), ['Alpha', 'Memo']);
      expect(c.excludedFolders, isEmpty);
    });

    test('short clips are left out, and the limit can be changed either way', () async {
      final c = controller();
      await c.load();
      await c.scan();
      expect(c.minSeconds, 30);
      expect(c.songs.map((t) => t.title), ['Alpha', 'Memo']); // 20 and 5 seconds are too short
      await c.setMinSeconds(10);
      expect(c.songs.map((t) => t.title), ['Alpha', 'Memo', 'Short']); // brought back by looking again
      await c.setMinSeconds(0);
      expect(c.songs.map((t) => t.title), ['Alpha', 'Memo', 'Short', 'Tiny']);
      await c.setMinSeconds(100);
      expect(c.songs.map((t) => t.title), ['Alpha', 'Memo']); // 3 min and 2 min remain
      await c.setMinSeconds(170);
      expect(c.songs.map((t) => t.title), ['Alpha']);
      expect(store.snapshot.minSeconds, 170);
    });

    test('the limit is remembered, and an old save without it means 30 seconds', () async {
      final c = controller();
      await c.load();
      await c.setMinSeconds(60);
      final again = controller();
      await again.load();
      expect(again.minSeconds, 60);
      expect(LibrarySnapshot.fromJson(const {}).minSeconds, 30);
    });

    test('deleting removes the file, the song and its like', () async {
      final c = controller();
      await c.load();
      await c.scan();
      final alpha = c.songs.first;
      await c.toggleLike(alpha.id);
      expect(await c.deleteTrack(alpha), isTrue);
      expect(File(alpha.path).existsSync(), isFalse);
      expect(c.songs.map((t) => t.title), ['Memo']);
      expect(c.isLiked(alpha.id), isFalse);
      expect(c.message, 'Deleted "Alpha".');
      expect(store.snapshot.tracks.length, 1);
    });

    test('a file that cannot be deleted stays in the library, and the person is told', () async {
      final c = controller(deleter: (_) async => throw const FileSystemException('in use'));
      await c.load();
      await c.scan();
      final alpha = c.songs.first;
      expect(await c.deleteTrack(alpha), isFalse);
      expect(c.songs.length, 2);
      expect(c.message, contains('Could not delete "Alpha"'));
    });

    test('a file that is already gone counts as deleted', () async {
      final c = controller();
      await c.load();
      await c.scan();
      final alpha = c.songs.first;
      File(alpha.path).deleteSync();
      expect(await c.deleteTrack(alpha), isTrue);
      expect(c.songs.map((t) => t.title), ['Memo']);
    });
  });

  group('a song that no longer exists', () {
    Track t(String id) => Track(id: id, title: 'Song $id', artist: 'A', uri: Uri.file('/m/$id.mp3'), source: TrackSource.local, duration: const Duration(seconds: 60));

    void run(void Function(FakeAsync async, PlaybackController c, FakeDeck a) body) {
      fakeAsync((async) {
        final a = FakeDeck();
        final c = PlaybackController(deckA: a, deckB: FakeDeck());
        body(async, c, a);
        c.dispose();
      });
    }

    void go(FakeAsync async, Future<void> f) {
      unawaited(f);
      async.flushMicrotasks();
    }

    String ids(PlaybackController c) => c.queue.map((x) => x.id).join();

    test('is taken out of the queue; if it was playing, playback moves on first', () {
      run((async, c, a) {
        go(async, c.setQueue([t('a'), t('b'), t('c')], startIndex: 1));
        go(async, c.dropTrack('b'));
        expect(ids(c), 'ac');
        expect(c.current!.id, 'c');
        expect(a.loaded!.id, 'c'); // the deck let go of the old file
        expect(c.isPlaying, isTrue);
      });
    });

    test('moves back to an earlier song when it was the last one', () {
      run((async, c, a) {
        go(async, c.setQueue([t('a'), t('b'), t('c')], startIndex: 2));
        go(async, c.dropTrack('c'));
        expect(ids(c), 'ab');
        expect(c.current!.id, 'a');
      });
    });

    test('empties the player when it was the only song', () {
      run((async, c, a) {
        go(async, c.setQueue([t('a')]));
        go(async, c.dropTrack('a'));
        expect(c.queue, isEmpty);
        expect(c.current, isNull);
        expect(c.isPlaying, isFalse);
      });
    });

    test('takes out every copy, and forgets it in the history, but does nothing for a song that is not there', () {
      run((async, c, a) {
        go(async, c.setQueue([t('a'), t('x'), t('b'), t('x'), t('c')]));
        go(async, c.next()); // x is playing; a goes into the history
        go(async, c.next());
        go(async, c.jumpTo(3)); // the second x
        expect(c.history.map((h) => h.id), ['b', 'x', 'a']);
        go(async, c.dropTrack('x'));
        expect(ids(c), 'abc');
        expect(c.current!.id, 'c');
        expect(c.history.map((h) => h.id), ['b', 'a']);
        go(async, c.dropTrack('nothing'));
        expect(ids(c), 'abc');
      });
    });

    test('keeps shuffle working: the original order has no trace of it', () {
      run((async, c, a) {
        go(async, c.setQueue([t('a'), t('b'), t('c'), t('d')]));
        go(async, c.setShuffle(true));
        go(async, c.dropTrack('c'));
        go(async, c.setShuffle(false));
        expect(ids(c), 'abd');
      });
    });
  });

  test('a deleted song is taken out of every playlist', () async {
    final playlists = PlaylistsController(store: MemoryPlaylistStore());
    Track song(String id) => Track(id: id, title: id, artist: 'A', uri: Uri.parse('x:$id'), source: TrackSource.local);
    final one = await playlists.create('One');
    final two = await playlists.create('Two');
    await playlists.addTracks(one.id, [song('a'), song('b')]);
    await playlists.addTracks(two.id, [song('b')]);
    await playlists.addTracks(two.id, [song('b')], allowDuplicates: true);
    expect(await playlists.removeTrackEverywhere('b'), 3);
    expect(playlists.byId(one.id)!.entries.map((e) => e.track.id), ['a']);
    expect(playlists.byId(two.id)!.entries, isEmpty);
    expect(await playlists.removeTrackEverywhere('b'), 0);
  });
}
