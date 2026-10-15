import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/library/library_controller.dart';
import 'package:vyro_music/library/library_scanner.dart';
import 'package:vyro_music/library/library_store.dart';
import 'package:vyro_music/library/likes_controller.dart';
import 'package:vyro_music/library/likes_store.dart';

import 'catalog_fakes.dart';
import 'library_fixtures.dart';

void main() {
  late LibraryController library;
  late FakeCatalogApi catalog;
  late MemoryLikesStore store;
  late LikesController likes;
  var signedIn = false;

  Track vyro(String id, String title) => catalogTrack(id, title).toPlayable(catalog.streamUri);
  Track local(String title) => libTrack(title).toPlayable();

  LikesController make({Track Function(Track)? attach}) => LikesController(library: library, store: store, catalog: catalog, canSync: () => signedIn, attach: attach);

  setUp(() async {
    signedIn = false;
    catalog = FakeCatalogApi();
    store = MemoryLikesStore();
    library = LibraryController(store: MemoryLibraryStore(LibrarySnapshot(tracks: [libTrack('Zed'), libTrack('Alpha')])), scanner: LibraryScanner(readTags: FakeTagReader().call));
    await library.load();
    likes = make();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('likes songs on the device through the library, and lists everything liked, by title', () async {
    await likes.toggle(local('Zed'));
    await likes.toggle(vyro('1', 'Night Drive'));
    await likes.toggle(local('Alpha'));
    expect(likes.tracks.map((t) => t.title), ['Alpha', 'Night Drive', 'Zed']);
    expect([likes.isLiked(local('Zed')), likes.isLiked(vyro('1', 'Night Drive')), likes.isLiked(vyro('2', 'Other'))], [true, true, false]);
    expect(library.isLiked(local('Zed').id), isTrue); // device likes live in the library
    await likes.toggle(local('Zed'));
    await likes.toggle(vyro('1', 'Night Drive'));
    expect(likes.tracks.map((t) => t.title), ['Alpha']);
  });

  test('tells listeners when a like changes, including one made through the library', () async {
    var heard = 0;
    likes.addListener(() => heard++);
    await likes.toggle(vyro('1', 'Night Drive'));
    final afterVyro = heard;
    expect(afterVyro, greaterThan(0));
    await library.toggleLike(local('Zed').id);
    expect(heard, greaterThan(afterVyro));
  });

  group('keeping Vyro likes on the server', () {
    test('a like made while signed out waits, and is sent after signing in', () async {
      await likes.toggle(vyro('1', 'Night Drive'));
      await settle();
      expect(catalog.saveCalls, isEmpty);
      signedIn = true;
      await likes.sync();
      expect(catalog.saveCalls, ['save:1']);
      expect(likes.isLiked(vyro('1', 'Night Drive')), isTrue);
      await likes.sync();
      expect(catalog.saveCalls, ['save:1']); // sent once, not again
    });

    test('a like undone before it was ever sent never reaches the server', () async {
      await likes.toggle(vyro('1', 'Night Drive'));
      await likes.toggle(vyro('1', 'Night Drive'));
      signedIn = true;
      await likes.sync();
      expect(catalog.saveCalls, isEmpty);
      expect(likes.tracks, isEmpty);
    });

    test('a burst of likes and unlikes while signed out ends up as one like', () async {
      catalog.saved = [catalogTrack('1', 'Night Drive')];
      signedIn = true;
      await likes.sync();
      await likes.toggle(vyro('1', 'Night Drive')); // unlike: sent straight away while signed in
      await settle();
      expect(catalog.saveCalls, ['unsave:1']);
      signedIn = false;
      await likes.toggle(vyro('1', 'Night Drive')); // like again
      await likes.toggle(vyro('1', 'Night Drive')); // unlike
      await likes.toggle(vyro('1', 'Night Drive')); // like
      signedIn = true;
      await likes.sync();
      expect(catalog.saveCalls, ['unsave:1', 'save:1']);
    });

    test('unliking something already on the server sends the unlike', () async {
      catalog.saved = [catalogTrack('1', 'Night Drive')];
      signedIn = true;
      await likes.sync();
      expect(likes.isLiked(vyro('1', 'Night Drive')), isTrue); // liked on another device
      await likes.toggle(vyro('1', 'Night Drive'));
      await settle();
      expect(catalog.saveCalls, ['unsave:1']);
      expect(likes.isLiked(vyro('1', 'Night Drive')), isFalse);
      expect(catalog.saved, isEmpty);
    });

    test('the server\'s list is the truth: likes from another device appear and removed ones go', () async {
      signedIn = true;
      await likes.toggle(vyro('A', 'Song A'));
      await settle();
      expect(catalog.saveCalls, ['save:A']);
      catalog.saved = [catalogTrack('B', 'Song B')]; // on another device: A unliked, B liked
      await likes.sync();
      expect(likes.tracks.map((t) => t.title), ['Song B']);
    });

    test('a failed send is tried again later, without losing the like', () async {
      signedIn = true;
      catalog.saveFailure = const ApiException(0, 'network');
      await likes.toggle(vyro('1', 'Night Drive'));
      await settle();
      expect(likes.isLiked(vyro('1', 'Night Drive')), isTrue);
      expect(catalog.saveCalls, isEmpty);
      catalog.saveFailure = null;
      await likes.sync();
      expect(catalog.saveCalls, ['save:1']);
    });

    test('a like made while the list is being fetched is not lost', () async {
      signedIn = true;
      final first = likes.sync();
      await likes.toggle(vyro('9', 'Late Like')); // while the first sync is still running
      await first;
      await settle();
      expect(likes.isLiked(vyro('9', 'Late Like')), isTrue);
    });

    test('two syncs at once send each like once', () async {
      signedIn = true;
      await likes.toggle(vyro('1', 'Night Drive'));
      await Future.wait([likes.sync(), likes.sync(), likes.sync()]);
      expect(catalog.saveCalls, ['save:1']);
    });
  });

  group('remembering', () {
    test('likes and the ones still waiting come back after a restart, with a way to find the address', () async {
      await likes.toggle(vyro('1', 'Night Drive'));
      final restarted = make(attach: (t) => t.withResolveUri(() async => Uri.parse('https://example.com/${t.id}')));
      await restarted.load();
      expect(restarted.tracks.single.title, 'Night Drive');
      expect(restarted.tracks.single.resolveUri, isNotNull);
      signedIn = true;
      await restarted.sync();
      expect(catalog.saveCalls, ['save:1']); // the like that was waiting is still sent
    });

    test('on disk', () async {
      final dir = Directory.systemTemp.createTempSync('vyro_likes_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final disk = FileLikesStore(directory: () async => dir);
      await disk.save(LikesSnapshot(tracks: [vyro('1', 'Night Drive')], pendingSave: {'vyro:1'}, pendingUnsave: {'vyro:2'}));
      expect(dir.listSync().map((f) => f.path.split(Platform.pathSeparator).last), ['liked_online.json']);
      final back = await disk.load();
      expect([back.tracks.single.title, back.pendingSave, back.pendingUnsave], ['Night Drive', {'vyro:1'}, {'vyro:2'}]);
      File('${dir.path}/liked_online.json').writeAsStringSync('{ broken');
      expect((await disk.load()).tracks, isEmpty); // a damaged file is ignored
    });
  });
}
