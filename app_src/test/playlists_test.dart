import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/playlists/playlist_models.dart';
import 'package:vyro_music/playlists/playlist_store.dart';
import 'package:vyro_music/playlists/playlists_controller.dart';
import 'package:vyro_music/studio/studio_models.dart';

Track song(String id, {String? title, String artist = 'Artist', int seconds = 180, TrackSource source = TrackSource.vyro}) => Track(
      id: source == TrackSource.local ? 'local:/music/$id.mp3' : 'vyro:$id',
      title: title ?? 'Song $id',
      artist: artist,
      uri: source == TrackSource.local ? Uri.file('/music/$id.mp3') : Uri.parse('vyro:$id'),
      source: source,
      duration: Duration(seconds: seconds),
    );

PickedFile picture(String name, int length) => PickedFile(name: name, length: length, open: () => Stream.value(List<int>.filled(length, 7)));

String titles(Playlist p) => p.entries.map((e) => e.track.id.replaceAll('vyro:', '')).join();

void main() {
  late MemoryPlaylistStore store;
  late PlaylistsController c;
  var tick = 0;
  var ids = 0;

  setUp(() {
    store = MemoryPlaylistStore();
    tick = 0;
    ids = 0;
    // every change happens one minute after the last, so "most recent first" is predictable
    c = PlaylistsController(store: store, clock: () => DateTime.utc(2026, 10, 12, 12, tick++), newId: () => 'id${ids++}');
  });

  Future<Playlist> withSongs(String letters, {String name = 'Mix'}) async {
    final p = await c.create(name);
    await c.addTracks(p.id, [for (final l in letters.split('')) song(l)]);
    return c.byId(p.id)!;
  }

  group('making and editing playlists', () {
    test('creates playlists with a name and a description, newest change first', () async {
      final a = await c.create('  Road trip  ', description: ' Long drives ');
      await c.create('Gym');
      expect([a.name, a.description], ['Road trip', 'Long drives']);
      expect(c.playlists.map((p) => p.name), ['Gym', 'Road trip']);
      await c.update(a.id, name: 'Road trip 2');
      expect(c.playlists.map((p) => p.name), ['Road trip 2', 'Gym']); // the one just changed comes first
    });

    test('refuses an empty name, and trims names and descriptions that are too long', () async {
      expect(() => c.create('   '), throwsArgumentError);
      final p = await c.create('x' * 150, description: 'd' * 500);
      expect([p.name.length, p.description.length], [maxPlaylistName, maxPlaylistDescription]);
      expect(() => c.update(p.id, name: ''), throwsArgumentError);
    });

    test('renames, changes the description, and deletes', () async {
      final p = await c.create('Old');
      await c.update(p.id, name: 'New', description: 'About');
      expect([c.byId(p.id)!.name, c.byId(p.id)!.description], ['New', 'About']);
      await c.delete(p.id);
      expect(c.byId(p.id), isNull);
      await c.delete('nothing'); // deleting what is not there is harmless
    });

    test('keeps a cover picture, replaces it, and removes it, cleaning up the old files', () async {
      final p = await c.create('Covered');
      await c.setCover(p.id, picture('cover.PNG', 100));
      final first = c.byId(p.id)!.coverPath!;
      expect(first, endsWith('.png'));
      expect(store.covers.keys, [first]);
      await c.setCover(p.id, picture('other.jpg', 50));
      expect(store.covers.length, 1); // the old picture is not left behind
      await c.removeCover(p.id);
      expect([c.byId(p.id)!.coverPath, store.covers], [null, isEmpty]);
      await c.setCover(p.id, picture('a.jpg', 10));
      await c.delete(p.id);
      expect(store.covers, isEmpty); // deleting the playlist deletes its picture
    });

    test('refuses a cover over 5 MB', () async {
      final p = await c.create('Big');
      await expectLater(c.setCover(p.id, picture('huge.jpg', maxCoverBytes + 1)), throwsFormatException);
      expect(c.byId(p.id)!.coverPath, isNull);
    });
  });

  group('adding songs from any source', () {
    test('adds Vyro songs and songs from the device to the end', () async {
      final p = await c.create('Mixed');
      final r = await c.addTracks(p.id, [song('a'), song('b', source: TrackSource.local)]);
      expect([r.added, r.duplicates], [2, 0]);
      expect(c.byId(p.id)!.entries.map((e) => e.track.source), [TrackSource.vyro, TrackSource.local]);
    });

    test('leaves out songs the playlist already has, unless asked to add them anyway', () async {
      final p = await withSongs('ab');
      final r = await c.addTracks(p.id, [song('b'), song('c'), song('c')]);
      expect([r.added, r.duplicates], [1, 2]); // b is there already; the second c repeats the first
      expect(titles(c.byId(p.id)!), 'abc');
      final again = await c.addTracks(p.id, [song('a')], allowDuplicates: true);
      expect(again.added, 1);
      expect(titles(c.byId(p.id)!), 'abca');
      expect(c.byId(p.id)!.entries.map((e) => e.id).toSet().length, 4); // the two a's are separate entries
    });

    test('knows which playlists have a song', () async {
      final one = await withSongs('ab', name: 'One');
      await withSongs('b', name: 'Two');
      expect(c.containing('vyro:b').length, 2);
      expect(c.containing('vyro:a').single.id, one.id);
      expect(c.containing('vyro:z'), isEmpty);
    });
  });

  group('changing the order', () {
    test('moves a song to a new place', () async {
      final p = await withSongs('abcd');
      await c.moveEntry(p.id, 0, 2);
      expect(titles(c.byId(p.id)!), 'bcad');
      await c.moveEntry(p.id, 3, 0);
      expect(titles(c.byId(p.id)!), 'dbca');
      await c.moveEntry(p.id, 1, 1);
      await c.moveEntry(p.id, 9, 0);
      expect(titles(c.byId(p.id)!), 'dbca');
    });

    test('sorts by title, artist, date added and length, either way, keeping the order of equals', () async {
      final p = await c.create('Sorted');
      await c.addTracks(p.id, [song('1', title: 'banana', artist: 'Zed', seconds: 100)]);
      await c.addTracks(p.id, [song('2', title: 'Apple', artist: 'Amy', seconds: 300)]);
      await c.addTracks(p.id, [song('3', title: 'cherry', artist: 'amy', seconds: 100)]);
      Future<String> order(PlaylistSort k, {bool asc = true}) async {
        await c.sortBy(p.id, k, ascending: asc);
        return titles(c.byId(p.id)!);
      }

      expect(await order(PlaylistSort.title), '213'); // not case sensitive
      expect(await order(PlaylistSort.title, asc: false), '312');
      // each sort starts from the order the previous one left, and songs that are equal keep that order
      expect(await order(PlaylistSort.artist), '321'); // Amy and amy are equal, and 3 came before 2
      expect(await order(PlaylistSort.duration), '312'); // 3 and 1 are both 100 seconds
      expect(await order(PlaylistSort.duration, asc: false), '231');
      expect(await order(PlaylistSort.dateAdded), '123');
    });

    test('removes duplicates, keeping the first of each, and says how many it took out', () async {
      final p = await withSongs('abc');
      await c.addTracks(p.id, [song('a'), song('b'), song('a')], allowDuplicates: true);
      expect(titles(c.byId(p.id)!), 'abcaba');
      expect(await c.removeDuplicates(p.id), 3);
      expect(titles(c.byId(p.id)!), 'abc');
      expect(await c.removeDuplicates(p.id), 0);
    });

    test('removes several songs at once', () async {
      final p = await withSongs('abcde');
      final entries = c.byId(p.id)!.entries;
      await c.removeEntries(p.id, {entries[1].id, entries[3].id});
      expect(titles(c.byId(p.id)!), 'ace');
    });
  });

  group('lasting', () {
    test('every change is saved, and a fresh start brings everything back', () async {
      final p = await withSongs('abc', name: 'Kept');
      await c.update(p.id, description: 'Still here');
      await c.setCover(p.id, picture('c.jpg', 10));
      final restarted = PlaylistsController(store: store);
      await restarted.load();
      final back = restarted.playlists.single;
      expect([back.name, back.description, titles(back), back.coverPath != null], ['Kept', 'Still here', 'abc', true]);
      expect(back.entries.first.addedAt, c.byId(p.id)!.entries.first.addedAt);
    });

    test('songs from Vyro get a way to find their address again when read back', () async {
      await withSongs('a');
      final restarted = PlaylistsController(store: store, attach: (t) => t.withResolveUri(() async => Uri.parse('https://example.com/${t.id}')));
      await restarted.load();
      expect(restarted.playlists.single.entries.single.track.resolveUri, isNotNull);
    });

    test('changes made at the same moment all arrive in the saved list', () async {
      final p = await c.create('Busy');
      await Future.wait([for (var i = 0; i < 10; i++) c.addTracks(p.id, [song('s$i')])]);
      final restarted = PlaylistsController(store: store);
      await restarted.load();
      expect(restarted.playlists.single.entries.length, 10);
    });

    test('the length and the songs of a playlist', () async {
      final p = await withSongs('ab');
      expect(c.byId(p.id)!.totalDuration, const Duration(minutes: 6));
      expect(c.byId(p.id)!.tracks.length, 2);
    });
  });

  group('on disk', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vyro_pl_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('saves and loads, leaves no half-written file, and stores covers in their own folder', () async {
      final disk = FilePlaylistStore(directory: () async => dir);
      final p = Playlist(id: 'p1', name: 'Disk', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026), entries: [PlaylistEntry(id: 'e1', track: song('a'), addedAt: DateTime.utc(2026))]);
      await disk.save([p]);
      expect(dir.listSync().map((f) => f.path.split(Platform.pathSeparator).last), ['playlists.json']);
      expect((await disk.load()).single.entries.single.track.title, 'Song a');
      final cover = await disk.saveCover('p1', [1, 2, 3], 'png');
      expect(File(cover).readAsBytesSync(), [1, 2, 3]);
      await disk.deleteCover(cover);
      expect(File(cover).existsSync(), isFalse);
      await disk.deleteCover(cover); // already gone: harmless
    });

    test('a damaged file gives no playlists instead of stopping the app', () async {
      File('${dir.path}/playlists.json').writeAsStringSync('{ not json');
      expect(await FilePlaylistStore(directory: () async => dir).load(), isEmpty);
    });
  });
}
