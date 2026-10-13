import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/playback_snapshot.dart';
import 'package:vyro_music/audio/playback_store.dart';
import 'package:vyro_music/audio/track.dart';

import 'fakes.dart';

Track t(String id, {TrackSource source = TrackSource.vyro, Future<Uri> Function()? resolve}) => Track(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      uri: source == TrackSource.local ? Uri.file('/music/$id.mp3') : Uri.parse('https://example.com/$id.mp3'),
      source: source,
      duration: const Duration(seconds: 60),
      resolveUri: resolve,
    );

List<Track> tracks(String ids) => [for (final id in ids.split('')) t(id)];

class Rig {
  Rig({PlaybackMode mode = PlaybackMode.normal, math.Random? random, bool Function(Object)? retry})
      : a = FakeDeck(),
        b = FakeDeck() {
    c = PlaybackController(deckA: a, deckB: b, random: random ?? math.Random(1), isRetryable: retry, describeError: (e) => 'Could not play: $e')..setMode(mode);
  }

  final FakeDeck a;
  final FakeDeck b;
  late final PlaybackController c;

  String get order => r(c.queue);
  static String r(List<Track> list) => list.map((x) => x.id).join();
}

void go(FakeAsync async, Future<void> job) {
  unawaited(job);
  async.flushMicrotasks();
}

void run(void Function(FakeAsync async, Rig r) body, {PlaybackMode mode = PlaybackMode.normal, bool Function(Object)? retry}) {
  fakeAsync((async) {
    final r = Rig(mode: mode, retry: retry);
    body(async, r);
    r.c.dispose();
  });
}

void main() {
  group('shuffle', () {
    test('plays the current song first and keeps every song, in a random order', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abcde'), startIndex: 2));
        go(async, r.c.setShuffle(true));
        expect(r.c.shuffle, isTrue);
        expect(r.c.queue.first.id, 'c');
        expect(r.c.index, 0);
        expect(r.order.split('').toList()..sort(), ['a', 'b', 'c', 'd', 'e']);
      });
    });

    test('different shuffles come out in different orders', () {
      fakeAsync((async) {
        final orders = <String>{};
        for (var seed = 0; seed < 20; seed++) {
          final r = Rig(random: math.Random(seed));
          go(async, r.c.setQueue(tracks('abcdefghij')));
          go(async, r.c.setShuffle(true));
          orders.add(r.order);
          r.c.dispose();
        }
        expect(orders.length, greaterThan(10));
      });
    });

    test('next and previous follow the shuffled order', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abcde')));
        go(async, r.c.setShuffle(true));
        final second = r.c.queue[1].id;
        go(async, r.c.next());
        expect(r.c.current!.id, second);
        go(async, r.c.previous());
        expect(r.c.current!.id, r.c.queue.first.id);
      });
    });

    test('switching it off puts the queue back in its original order and keeps the song that is playing', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abcde'), startIndex: 1));
        go(async, r.c.setShuffle(true));
        go(async, r.c.next());
        go(async, r.c.next());
        final playing = r.c.current!.id;
        go(async, r.c.setShuffle(false));
        expect(r.c.shuffle, isFalse);
        expect(r.order, 'abcde');
        expect(r.c.current!.id, playing);
        expect(r.c.index, 'abcde'.indexOf(playing));
      });
    });

    test('choosing a song from a list while shuffle is on starts with it and shuffles the rest', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abc')));
        go(async, r.c.setShuffle(true));
        go(async, r.c.setQueue(tracks('vwxyz'), startIndex: 3));
        expect(r.c.queue.first.id, 'y');
        expect(r.order.split('').toList()..sort(), ['v', 'w', 'x', 'y', 'z']);
        go(async, r.c.setShuffle(false));
        expect(r.order, 'vwxyz');
        expect(r.c.current!.id, 'y');
      });
    });

    test('songs added while shuffled go to the right place when shuffle is switched off', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abcd'), startIndex: 1));
        go(async, r.c.setShuffle(true));
        go(async, r.c.playNext(t('x')));
        expect(r.c.queue[1].id, 'x'); // next up
        go(async, r.c.addToQueue(t('y')));
        expect(r.c.queue.last.id, 'y');
        go(async, r.c.setShuffle(false));
        expect(r.order, 'abxcdy'); // x right after b, y at the end
        expect(r.c.current!.id, 'b');
      });
    });

    test('adding to the end while the last song of a shuffled queue is playing still goes to the end', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abc')));
        go(async, r.c.setShuffle(true));
        go(async, r.c.next());
        go(async, r.c.next()); // now on the last song of the shuffled order
        go(async, r.c.addToQueue(t('y')));
        go(async, r.c.setShuffle(false));
        expect(r.order, 'abcy');
      });
    });

    test('a song removed while shuffled is gone after switching off', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abcd')));
        go(async, r.c.setShuffle(true));
        final victim = r.c.queue[2].id;
        go(async, r.c.removeFromQueue(2));
        go(async, r.c.setShuffle(false));
        expect(r.order, 'abcd'.replaceAll(victim, ''));
      });
    });
  });

  group('the queue', () {
    test('play next puts a song right after the current one, add puts it last, and a song can be queued twice', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abc')));
        go(async, r.c.playNext(t('x')));
        expect(r.order, 'axbc');
        expect(r.c.upcoming!.id, 'x');
        go(async, r.c.addToQueue(t('c')));
        expect(r.order, 'axbcc');
        expect(r.c.queueIds.toSet().length, 5); // the two c's are different entries
        expect(r.c.current!.id, 'a'); // nothing changed for the song that is playing
      });
    });

    test('with nothing playing, play next and add start the song', () {
      run((async, r) {
        go(async, r.c.playNext(t('x')));
        expect(r.c.current!.id, 'x');
        expect(r.c.isPlaying, isTrue);
        expect(r.a.loaded!.id, 'x');
      });
    });

    test('removing: the song playing now stays, later songs go, and removing an earlier one keeps the same song playing', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abcd'), startIndex: 2));
        go(async, r.c.removeFromQueue(2));
        expect(r.order, 'abcd'); // cannot remove what is playing
        go(async, r.c.removeFromQueue(3));
        expect(r.order, 'abc');
        go(async, r.c.removeFromQueue(0));
        expect(r.order, 'bc');
        expect([r.c.index, r.c.current!.id], [1, 'c']);
        go(async, r.c.removeFromQueue(9));
        expect(r.order, 'bc');
      });
    });

    test('reordering only moves songs that are still to come', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abcde')));
        go(async, r.c.moveInQueue(1, 3));
        expect(r.order, 'acdbe');
        go(async, r.c.moveInQueue(0, 2)); // the playing song cannot be moved
        go(async, r.c.moveInQueue(2, 0)); // and nothing can be moved before it
        go(async, r.c.moveInQueue(4, 4));
        expect(r.order, 'acdbe');
        expect(r.c.queueIds.toSet().length, 5);
      });
    });

    test('clearing empties what comes after the song that is playing', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abcd'), startIndex: 1));
        go(async, r.c.clearUpcoming());
        expect(r.order, 'ab');
        expect(r.c.current!.id, 'b');
        expect(r.c.upcoming, isNull);
      });
    });

    test('jumping plays that song, remembers where you were, and does nothing for the song already playing', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abcd')));
        go(async, r.c.jumpTo(3));
        expect(r.c.current!.id, 'd');
        expect(Rig.r(r.c.history), 'a');
        go(async, r.c.jumpTo(3));
        expect(Rig.r(r.c.history), 'a');
      });
    });

    test('in Mixing mode, jumping blends into the song', () {
      run(mode: PlaybackMode.mixing, (async, r) {
        go(async, r.c.setQueue(tracks('abcd')));
        go(async, r.c.jumpTo(2));
        expect(r.c.isTransitioning, isTrue);
        expect(r.c.mixingInto!.id, 'c');
        async.elapse(const Duration(milliseconds: 3100));
        expect(r.c.current!.id, 'c');
      });
    });

    test('history lists played songs, most recent first, and a song from it can be played again', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abc')));
        go(async, r.c.next());
        go(async, r.c.next());
        expect(Rig.r(r.c.history), 'ba');
        go(async, r.c.setQueue(tracks('xy')));
        expect(Rig.r(r.c.history), 'cba'); // the song that was playing when the queue was replaced counts too
        go(async, r.c.playNow(t('b')));
        expect(r.c.current!.id, 'b');
        expect(r.order, 'xby');
        expect(r.c.history.first.id, 'x');
      });
    });
  });

  group('picking up where you left off', () {
    PlaybackSnapshot saved(FakeAsync async) {
      final first = Rig();
      go(async, first.c.setQueue(tracks('abcd'), startIndex: 2));
      go(async, first.c.setShuffle(true));
      first.c.setRepeat(RepeatMode.all);
      first.c.setMode(PlaybackMode.mixing);
      first.a.emitPosition(const Duration(seconds: 42));
      async.flushMicrotasks();
      final json = jsonDecode(jsonEncode(first.c.snapshot().toJson())) as Map<String, Object?>;
      first.c.dispose();
      return PlaybackSnapshot.fromJson(json);
    }

    test('brings back the queue, the place in it, the settings and the position, paused and not loaded', () {
      fakeAsync((async) {
        final snap = saved(async);
        final r = Rig();
        go(async, r.c.restore(snap));
        expect(r.c.queue.length, 4);
        expect(r.c.queue.first.id, 'c');
        expect([r.c.index, r.c.shuffle, r.c.repeat, r.c.mode], [0, true, RepeatMode.all, PlaybackMode.mixing]);
        expect(r.c.position.value, const Duration(seconds: 42));
        expect(r.c.duration, const Duration(seconds: 60)); // known from the song, before anything loads
        expect(r.c.isPlaying, isFalse);
        expect(r.a.loads, isEmpty); // no network use just from starting
        r.c.dispose();
      });
    });

    test('pressing play loads the song and jumps to the saved position', () {
      fakeAsync((async) {
        final snap = saved(async);
        final r = Rig();
        go(async, r.c.restore(snap));
        go(async, r.c.play());
        expect(r.a.loads.single.id, 'c');
        expect(r.a.seeks.last, const Duration(seconds: 42));
        expect([r.a.playing, r.c.isPlaying], [true, true]);
        r.c.dispose();
      });
    });

    test('the original order is remembered too, so shuffle can still be switched off', () {
      fakeAsync((async) {
        final snap = saved(async);
        final r = Rig();
        go(async, r.c.restore(snap));
        go(async, r.c.playNext(t('z')));
        expect(r.c.queueIds.toSet().length, 5); // new entries do not clash with restored ones
        go(async, r.c.setShuffle(false));
        expect(r.order, 'abczd'); // z goes right after c, the song that was playing, in the original order
        expect(r.c.current!.id, 'c');
        r.c.dispose();
      });
    });

    test('seeking before anything is loaded changes where playback will start, not the deck', () {
      fakeAsync((async) {
        final snap = saved(async);
        final r = Rig();
        go(async, r.c.restore(snap));
        go(async, r.c.seek(const Duration(seconds: 10)));
        expect(r.c.position.value, const Duration(seconds: 10));
        expect(r.a.seeks, isEmpty);
        expect(r.c.snapshot().position, const Duration(seconds: 10));
        go(async, r.c.play());
        expect(r.a.seeks.last, const Duration(seconds: 10));
        r.c.dispose();
      });
    });

    test('previous after the first seconds restarts the song, even before it is loaded', () {
      fakeAsync((async) {
        final snap = saved(async);
        final r = Rig();
        go(async, r.c.restore(snap));
        go(async, r.c.previous());
        expect([r.c.index, r.c.position.value], [0, Duration.zero]);
        go(async, r.c.play());
        expect(r.a.loads.single.id, 'c');
        expect(r.a.seeks, isEmpty); // starts from the beginning
        r.c.dispose();
      });
    });

    test('never replaces what is already playing, and ignores an empty save', () {
      fakeAsync((async) {
        final snap = saved(async);
        final r = Rig();
        go(async, r.c.setQueue(tracks('xy')));
        go(async, r.c.restore(snap));
        expect(r.order, 'xy');
        final empty = PlaybackSnapshot(queue: const [], ids: const [], originalIds: const [], index: -1, position: Duration.zero, shuffle: false, repeat: RepeatMode.off, mode: PlaybackMode.normal, autoSeconds: 6, manualSeconds: 3, origin: 'direct');
        final fresh = Rig();
        go(async, fresh.c.restore(empty));
        expect(fresh.c.current, isNull);
        r.c.dispose();
        fresh.c.dispose();
      });
    });

    test('a save that does not make sense is refused instead of half-loaded', () {
      expect(() => PlaybackSnapshot.fromJson({'queue': 'nonsense'}), throwsFormatException);
      expect(() => PlaybackSnapshot.fromJson({'queue': [], 'ids': [1], 'index': 0}), throwsFormatException);
      expect(() => PlaybackSnapshot.fromJson({}), throwsFormatException);
    });

    test('songs read back from a save keep what they were, and Vyro songs get a way to find their address again', () {
      final json = trackToJson(Track(id: 'vyro:abc', title: 'T', artist: 'A', uri: Uri.parse('vyro:abc'), source: TrackSource.vyro, duration: const Duration(seconds: 90), loudnessLufs: -13.5, genre: 'Pop', allowMixing: false, countsAsListening: true));
      final snap = PlaybackSnapshot.fromJson({
        'queue': [json],
        'ids': [1],
        'originalIds': [],
        'index': 0,
      }, attach: (x) => x.withResolveUri(() async => Uri.parse('https://example.com/${x.id}')));
      final back = snap.queue.single;
      expect([back.id, back.source, back.duration, back.loudnessLufs, back.genre, back.allowMixing], ['vyro:abc', TrackSource.vyro, const Duration(seconds: 90), -13.5, 'Pop', false]);
      expect(back.resolveUri, isNotNull);
    });

    group('stores', () {
      PlaybackSnapshot snap() => PlaybackSnapshot(
            queue: [t('vyro:a'), t('b', source: TrackSource.local)],
            ids: const [4, 9],
            originalIds: const [],
            index: 1,
            position: const Duration(seconds: 7),
            shuffle: false,
            repeat: RepeatMode.one,
            mode: PlaybackMode.normal,
            autoSeconds: 6,
            manualSeconds: 3,
            origin: 'library',
          );

      test('in memory', () async {
        final store = MemoryPlaybackStore();
        expect(await store.load(), isNull);
        await store.save(snap());
        final back = (await store.load())!;
        expect([back.index, back.repeat, back.position, back.origin, back.ids], [1, RepeatMode.one, const Duration(seconds: 7), 'library', [4, 9]]);
        await store.clear();
        expect(await store.load(), isNull);
      });

      group('on disk', () {
        late Directory dir;
        setUp(() => dir = Directory.systemTemp.createTempSync('vyro_play_'));
        tearDown(() => dir.deleteSync(recursive: true));

        test('saves, reads back (giving Vyro songs their resolver), and leaves no half-written file', () async {
          final store = FilePlaybackStore(directory: () async => dir, attach: (x) => x.id.startsWith('vyro:') ? x.withResolveUri(() async => Uri.parse('https://example.com')) : x);
          await store.save(snap());
          expect(dir.listSync().map((f) => f.path.split(Platform.pathSeparator).last), ['playback_state.json']);
          final back = (await store.load())!;
          expect(back.queue[0].resolveUri, isNotNull);
          expect(back.queue[1].resolveUri, isNull);
          expect(back.queue[1].source, TrackSource.local);
        });

        test('a damaged file is ignored, and clearing removes it', () async {
          final store = FilePlaybackStore(directory: () async => dir);
          File('${dir.path}/playback_state.json').writeAsStringSync('{ broken');
          expect(await store.load(), isNull);
          await store.save(snap());
          await store.clear();
          expect(await store.load(), isNull);
          expect(dir.listSync(), isEmpty);
        });

        test('saves that happen at the same moment all finish, the last one winning', () async {
          final store = FilePlaybackStore(directory: () async => dir);
          await Future.wait([for (var i = 0; i < 20; i++) store.save(snap())]);
          expect(await store.load(), isNotNull);
        });
      });
    });

    testWidgets('the player saves shortly after a change, regularly while playing, and when the app goes to the background', (tester) async {
      final c = PlaybackController(deckA: FakeDeck(), deckB: FakeDeck());
      final store = MemoryPlaybackStore();
      final persistor = PlaybackPersistor(controller: c, store: store)..start();
      unawaited(c.setQueue(tracks('ab')));
      await tester.pump();
      expect(store.saves, 0); // waits a moment, so a burst of changes is one save
      await tester.pump(const Duration(milliseconds: 900));
      expect(store.saves, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(store.saves, 2); // playing: the position is kept fresh
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(store.saves, 3);
      unawaited(c.setQueue([]));
      await tester.pump(const Duration(seconds: 1));
      expect(await store.load(), isNull); // an empty player is not kept
      persistor.dispose();
      c.dispose();
    });
  });

  group('buffering and a lost connection', () {
    test('buffering is shown only while playing', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('ab')));
        r.a.emitBuffering(true);
        async.flushMicrotasks();
        expect(r.c.isBuffering, isTrue);
        r.a.emitBuffering(false);
        async.flushMicrotasks();
        expect(r.c.isBuffering, isFalse);
        r.a.emitBuffering(true);
        async.flushMicrotasks();
        go(async, r.c.pause());
        expect(r.c.isBuffering, isFalse);
      });
    });

    test('a lost connection is retried from where it stopped, loading the song again', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('ab')));
        r.a.emitPosition(const Duration(seconds: 30));
        async.flushMicrotasks();
        final loadsBefore = r.a.loads.length;
        r.a.emitError(Exception('connection reset'));
        async.flushMicrotasks();
        expect(r.c.isRetrying, isTrue);
        expect(r.c.isPlaying, isTrue); // the player does not pretend it stopped

        async.elapse(const Duration(seconds: 1));
        expect(r.a.loads.length, loadsBefore + 1);
        expect(r.a.seeks.last, const Duration(seconds: 30));
        expect([r.c.isRetrying, r.a.playing, r.c.error], [false, true, null]);
      });
    });

    test('after three failed tries it stops, says so, and play continues from the same spot', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('ab')));
        r.a.emitPosition(const Duration(seconds: 30));
        async.flushMicrotasks();
        r.a.failLoads = 3;
        r.a.emitError(Exception('connection reset'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1)); // first try fails, wait 2 s
        expect(r.c.isRetrying, isTrue);
        async.elapse(const Duration(seconds: 2)); // second fails, wait 4 s
        expect(r.c.isRetrying, isTrue);
        async.elapse(const Duration(seconds: 4)); // third fails
        expect(r.c.isRetrying, isFalse);
        expect(r.c.isPlaying, isFalse);
        expect(r.c.error, contains('Lost the connection'));

        go(async, r.c.play());
        expect(r.a.seeks.last, const Duration(seconds: 30));
        expect([r.c.isPlaying, r.a.playing, r.c.error], [true, true, null]);
      });
    });

    test('a song that cannot be loaded at the start stays selected and is tried again', () {
      run((async, r) {
        r.a.failLoads = 1;
        go(async, r.c.setQueue(tracks('ab')));
        expect(r.c.current!.id, 'a');
        expect(r.c.isRetrying, isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(r.a.loads.single.id, 'a');
        expect([r.c.isRetrying, r.a.playing, r.c.isPlaying], [false, true, true]);
      });
    });

    test('songs on the device are not retried: the problem is the file, not the connection', () {
      run((async, r) {
        go(async, r.c.setQueue([t('a', source: TrackSource.local)]));
        r.a.emitError(Exception('file gone'));
        async.flushMicrotasks();
        expect(r.c.isRetrying, isFalse);
        expect(r.c.error, contains('Could not play'));
        expect(r.c.isPlaying, isFalse);
      });
    });

    test('errors that will not get better by waiting fail at once', () {
      run(retry: (e) => false, (async, r) {
        go(async, r.c.setQueue(tracks('ab')));
        r.a.emitError(Exception('explicit_not_allowed'));
        async.flushMicrotasks();
        expect(r.c.isRetrying, isFalse);
        expect(r.c.error, isNotNull);
        expect(r.c.isPlaying, isFalse);
      });
    });

    test('pausing, or choosing another song, cancels the retry', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('abc')));
        r.a.emitError(Exception('connection reset'));
        async.flushMicrotasks();
        final loads = r.a.loads.length;
        go(async, r.c.pause());
        expect(r.c.isRetrying, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(r.a.loads.length, loads); // nothing was tried behind the listener's back

        go(async, r.c.play());
        r.a.emitError(Exception('connection reset'));
        async.flushMicrotasks();
        expect(r.c.isRetrying, isTrue);
        go(async, r.c.next());
        expect(r.c.isRetrying, isFalse);
        expect(r.c.current!.id, 'b');
      });
    });

    test('an error that arrives while another is already being retried does not start a second retry', () {
      run((async, r) {
        go(async, r.c.setQueue(tracks('ab')));
        r.a.emitError(Exception('one'));
        r.a.emitError(Exception('two'));
        async.flushMicrotasks();
        final loads = r.a.loads.length;
        async.elapse(const Duration(seconds: 1));
        expect(r.a.loads.length, loads + 1);
      });
    });
  });
}
