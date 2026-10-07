import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/library/library_controller.dart';
import 'package:vyro_music/library/library_models.dart';
import 'package:vyro_music/library/library_platform.dart';
import 'package:vyro_music/library/library_scanner.dart';
import 'package:vyro_music/library/library_store.dart';

import 'library_fixtures.dart';

class FakePlatform implements LibraryPlatform {
  FakePlatform({this.access = true, this.roots = const [], this.folder, this.songs = const []});

  bool access;
  List<String> roots;
  String? folder;
  List<String> songs;

  @override
  Future<List<String>> defaultRoots() async => roots;

  @override
  Future<bool> requestAccess() async => access;

  @override
  Future<String?> pickFolder() async => folder;

  @override
  Future<List<String>> pickSongs() async => songs;
}

void main() {
  late Directory root;
  late FakeTagReader reader;
  late MemoryLibraryStore store;

  LibraryController controller(FakePlatform platform) => LibraryController(
        store: store,
        scanner: LibraryScanner(readTags: reader.call),
        platform: platform,
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('vyro_ctrl_');
    reader = FakeTagReader();
    store = MemoryLibraryStore();
    makeAudio(root, 'alpha.mp3');
    makeAudio(root, 'beta.mp3');
    reader.byFileName['alpha.mp3'] = const TagInfo(title: 'Alpha', artist: 'Ann', duration: Duration(minutes: 3));
    reader.byFileName['beta.mp3'] = const TagInfo(title: 'Beta', artist: 'Bob', duration: Duration(minutes: 3));
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('scanning the usual music folders fills and saves the library', () async {
    final c = controller(FakePlatform(roots: [root.path]));
    await c.scan();
    expect(c.songs.map((t) => t.title), ['Alpha', 'Beta']);
    expect(c.message, '2 songs, 2 new');
    expect(store.snapshot.tracks.length, 2);
    expect(c.isScanning, isFalse);
  });

  test('without permission nothing is scanned and the user is told', () async {
    final c = controller(FakePlatform(access: false, roots: [root.path]));
    await c.scan();
    expect(c.hasTracks, isFalse);
    expect(c.message, contains('Allow access'));
  });

  test('where there is no folder to scan (iOS) the user is pointed to Add songs', () async {
    final c = controller(FakePlatform());
    await c.scan();
    expect(c.message, contains('Add songs'));
  });

  test('adding a folder remembers it and scans it', () async {
    final c = controller(FakePlatform(folder: root.path));
    await c.addFolder();
    expect(c.roots, [root.path]);
    expect(store.snapshot.roots, [root.path]);
    expect(c.songs.length, 2);
  });

  test('picked songs are added to the library', () async {
    final extra = makeAudio(root, 'extra/gamma.mp3');
    reader.byFileName['gamma.mp3'] = const TagInfo(title: 'Gamma', duration: Duration(minutes: 2));
    final c = controller(FakePlatform(songs: [extra.path]));
    await c.addSongs();
    expect(c.songs.map((t) => t.title), ['Gamma']);
    expect(store.snapshot.tracks.length, 1);
  });

  test('liking a song is remembered and shows in Liked', () async {
    final c = controller(FakePlatform(roots: [root.path]));
    await c.scan();
    final id = c.songs.first.id;
    await c.toggleLike(id);
    expect(c.isLiked(id), isTrue);
    expect(c.likedSongs.map((t) => t.id), [id]);
    expect(store.snapshot.liked, {id});
    await c.toggleLike(id);
    expect(c.likedSongs, isEmpty);
  });

  test('searching filters every view', () async {
    final c = controller(FakePlatform(roots: [root.path]));
    await c.scan();
    c.setQuery('bob');
    expect(c.songs.map((t) => t.title), ['Beta']);
    expect(c.artists.map((a) => a.name), ['Bob']);
  });

  test('removing a folder drops its songs', () async {
    final c = controller(FakePlatform(folder: root.path));
    await c.addFolder();
    await c.removeFolder(root.path);
    expect(c.hasTracks, isFalse);
    expect(c.roots, isEmpty);
  });

  test('a restarted app gets the saved library back', () async {
    final first = controller(FakePlatform(roots: [root.path]));
    await first.scan();
    final second = controller(FakePlatform());
    await second.load();
    expect(second.songs.length, 2);
  });
}
