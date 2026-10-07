import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/track.dart';

import 'fakes.dart';

Track t(String id, {TrackSource source = TrackSource.vyro}) => Track(
      id: id,
      title: id,
      artist: 'artist',
      uri: Uri.parse('https://example.com/$id.mp3'),
      source: source,
      duration: const Duration(seconds: 60),
    );

class Rig {
  Rig(PlaybackMode mode) : a = FakeDeck(), b = FakeDeck() {
    c = PlaybackController(deckA: a, deckB: b)..setMode(mode);
  }

  final FakeDeck a;
  final FakeDeck b;
  late final PlaybackController c;
}

void scenario(PlaybackMode mode, void Function(FakeAsync async, Rig r) body) {
  fakeAsync((async) {
    final r = Rig(mode);
    body(async, r);
    r.c.dispose();
  });
}

void main() {
  group('mixing mode', () {
    test('next blends: both decks fade, the screen follows at the midpoint, then it settles', () {
      scenario(PlaybackMode.mixing, (async, r) {
        unawaited(r.c.setQueue([t('a'), t('b'), t('c')]));
        async.flushMicrotasks();
        expect(r.c.current!.id, 'a');
        expect(r.a.playing, isTrue);

        unawaited(r.c.next());
        async.flushMicrotasks();
        expect(r.c.isTransitioning, isTrue);
        expect(r.b.loaded!.id, 'b');
        expect(r.b.playing, isTrue);

        async.elapse(const Duration(milliseconds: 1500)); // half of the 3 s skip blend
        expect(r.a.volume, closeTo(0.707, 0.06));
        expect(r.b.volume, closeTo(0.707, 0.06));
        expect(r.c.current!.id, 'b');

        async.elapse(const Duration(milliseconds: 1600));
        expect(r.c.isTransitioning, isFalse);
        expect(r.a.playing, isFalse);
        expect(r.b.volume, 1.0);
      });
    });

    test('a song entering its last seconds blends into the next one by itself', () {
      scenario(PlaybackMode.mixing, (async, r) {
        unawaited(r.c.setQueue([t('a'), t('b')]));
        async.flushMicrotasks();

        r.a.emitPosition(const Duration(seconds: 53)); // 7 s left, blend is 6 s
        async.flushMicrotasks();
        expect(r.c.isTransitioning, isFalse);

        r.a.emitPosition(const Duration(milliseconds: 54500));
        async.flushMicrotasks();
        expect(r.c.isTransitioning, isTrue);
        expect(r.b.loaded!.id, 'b');
      });
    });

    test('previous blends back to the earlier song', () {
      scenario(PlaybackMode.mixing, (async, r) {
        unawaited(r.c.setQueue([t('a'), t('b')], startIndex: 1));
        async.flushMicrotasks();
        r.a.emitPosition(const Duration(seconds: 2));
        unawaited(r.c.previous());
        async.flushMicrotasks();
        expect(r.c.isTransitioning, isTrue);
        expect(r.b.loaded!.id, 'a');
      });
    });

    test('previous after 3 seconds restarts the current song instead', () {
      scenario(PlaybackMode.mixing, (async, r) {
        unawaited(r.c.setQueue([t('a'), t('b')], startIndex: 1));
        async.flushMicrotasks();
        r.a.emitPosition(const Duration(seconds: 10));
        unawaited(r.c.previous());
        async.flushMicrotasks();
        expect(r.c.isTransitioning, isFalse);
        expect(r.c.current!.id, 'b');
        expect(r.a.seeks.last, Duration.zero);
      });
    });

    test('tracks that cannot be mixed (YouTube) change with a clean cut', () {
      scenario(PlaybackMode.mixing, (async, r) {
        unawaited(r.c.setQueue([t('a'), t('yt', source: TrackSource.youtube)]));
        async.flushMicrotasks();
        unawaited(r.c.next());
        async.flushMicrotasks();
        expect(r.c.isTransitioning, isFalse);
        expect(r.c.current!.id, 'yt');
        expect(r.b.loaded, isNull);
      });
    });

    test('pressing next twice quickly ends on the third song with one deck playing', () {
      scenario(PlaybackMode.mixing, (async, r) {
        unawaited(r.c.setQueue([t('a'), t('b'), t('c'), t('d')]));
        async.flushMicrotasks();
        unawaited(r.c.next());
        unawaited(r.c.next());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(r.c.isTransitioning, isFalse);
        expect(r.c.current!.id, 'c');
        expect(r.a.loaded!.id, 'c');
        expect(r.a.playing, isTrue);
        expect(r.b.playing, isFalse);
      });
    });

    test('repeat one restarts the same song at its end instead of blending', () {
      scenario(PlaybackMode.mixing, (async, r) {
        unawaited(r.c.setQueue([t('a'), t('b')]));
        async.flushMicrotasks();
        r.c.setRepeat(RepeatMode.one);
        r.a.finish();
        async.flushMicrotasks();
        expect(r.c.current!.id, 'a');
        expect(r.c.isTransitioning, isFalse);
        expect(r.a.seeks.last, Duration.zero);
        expect(r.a.playing, isTrue);
      });
    });
  });

  group('normal mode', () {
    test('next is a plain change on the same deck, with no overlap', () {
      scenario(PlaybackMode.normal, (async, r) {
        unawaited(r.c.setQueue([t('a'), t('b')]));
        async.flushMicrotasks();
        unawaited(r.c.next());
        async.flushMicrotasks();
        expect(r.c.isTransitioning, isFalse);
        expect(r.c.current!.id, 'b');
        expect(r.a.loaded!.id, 'b');
        expect(r.b.loaded, isNull);
        expect(r.a.volume, 1.0);
      });
    });

    test('a song that ends moves to the next one normally', () {
      scenario(PlaybackMode.normal, (async, r) {
        unawaited(r.c.setQueue([t('a'), t('b')]));
        async.flushMicrotasks();
        r.a.emitPosition(const Duration(milliseconds: 59000)); // no early blend in normal mode
        async.flushMicrotasks();
        expect(r.c.isTransitioning, isFalse);
        r.a.finish();
        async.flushMicrotasks();
        expect(r.c.current!.id, 'b');
        expect(r.c.isTransitioning, isFalse);
        expect(r.a.playing, isTrue);
      });
    });

    test('at the end of the queue playback stops and rewinds', () {
      scenario(PlaybackMode.normal, (async, r) {
        unawaited(r.c.setQueue([t('a')]));
        async.flushMicrotasks();
        r.a.finish();
        async.flushMicrotasks();
        expect(r.c.isPlaying, isFalse);
        expect(r.a.playing, isFalse);
      });
    });
  });
}
