import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/track.dart';

import 'fakes.dart';

Track t(String id, {bool counts = true, Duration duration = const Duration(seconds: 60)}) =>
    Track(id: id, title: id, artist: 'artist', uri: Uri.parse('https://example.com/$id.mp3'), duration: duration, countsAsListening: counts);

class Rig {
  Rig(PlaybackMode mode) : a = FakeDeck(), b = FakeDeck() {
    c = PlaybackController(deckA: a, deckB: b, onPlayEnded: events.add, clock: () => DateTime.utc(2026, 10, 6, 12))..setMode(mode);
  }

  final FakeDeck a;
  final FakeDeck b;
  late final PlaybackController c;
  final events = <PlayEnded>[];
}

void scenario(PlaybackMode mode, void Function(FakeAsync async, Rig r) body) {
  fakeAsync((async) {
    final r = Rig(mode);
    body(async, r);
    r.c.dispose();
  });
}

/// The song plays on [deck] from second [from] to second [to], one reading per second.
void listen(FakeAsync async, FakeDeck deck, int from, int to) {
  for (var s = from; s <= to; s++) {
    deck.emitPosition(Duration(seconds: s));
    async.flushMicrotasks();
  }
}

void main() {
  test('reports how long a song was heard when the next one starts, and where it was started from', () {
    scenario(PlaybackMode.normal, (async, r) {
      unawaited(r.c.setQueue([t('a'), t('b')], origin: 'search'));
      async.flushMicrotasks();
      listen(async, r.a, 0, 40);
      unawaited(r.c.next());
      async.flushMicrotasks();
      expect(r.events.length, 1);
      final e = r.events.single;
      expect([e.track.id, e.listenedMs, e.origin, e.mode, e.mixedInto], ['a', 40000, 'search', PlaybackMode.normal, null]);
      expect(e.startedAt, DateTime.utc(2026, 10, 6, 12));
    });
  });

  test('a jump forward (a seek) adds nothing to the listening time', () {
    scenario(PlaybackMode.normal, (async, r) {
      unawaited(r.c.setQueue([t('a'), t('b')]));
      async.flushMicrotasks();
      listen(async, r.a, 0, 2); // 2 seconds
      listen(async, r.a, 100, 101); // jumped to 100: only the second after the jump counts
      unawaited(r.c.next());
      async.flushMicrotasks();
      expect(r.events.single.listenedMs, 3000);
    });
  });

  test('pausing does not end a play; the rest after resuming is added to it', () {
    scenario(PlaybackMode.normal, (async, r) {
      unawaited(r.c.setQueue([t('a'), t('b')]));
      async.flushMicrotasks();
      listen(async, r.a, 0, 5);
      unawaited(r.c.pause());
      async.flushMicrotasks();
      expect(r.events, isEmpty);
      unawaited(r.c.play());
      async.flushMicrotasks();
      listen(async, r.a, 6, 10);
      unawaited(r.c.next());
      async.flushMicrotasks();
      expect(r.events.single.listenedMs, 10000);
    });
  });

  test('time passing while paused is not counted', () {
    scenario(PlaybackMode.normal, (async, r) {
      unawaited(r.c.setQueue([t('a'), t('b')]));
      async.flushMicrotasks();
      listen(async, r.a, 0, 4);
      unawaited(r.c.pause());
      async.flushMicrotasks();
      listen(async, r.a, 5, 8); // readings that arrive while paused
      unawaited(r.c.next());
      async.flushMicrotasks();
      expect(r.events.single.listenedMs, 4000);
    });
  });

  test('a play shorter than a second is not reported', () {
    scenario(PlaybackMode.normal, (async, r) {
      unawaited(r.c.setQueue([t('a'), t('b')]));
      async.flushMicrotasks();
      r.a.emitPosition(Duration.zero);
      async.flushMicrotasks();
      r.a.emitPosition(const Duration(milliseconds: 500));
      async.flushMicrotasks();
      unawaited(r.c.next());
      async.flushMicrotasks();
      expect(r.events, isEmpty);
    });
  });

  test('listening is never more than the length of the song', () {
    scenario(PlaybackMode.normal, (async, r) {
      unawaited(r.c.setQueue([t('short', duration: const Duration(seconds: 10)), t('b')]));
      async.flushMicrotasks();
      listen(async, r.a, 0, 14);
      unawaited(r.c.next());
      async.flushMicrotasks();
      expect(r.events.single.listenedMs, 10000);
    });
  });

  test('a blend reports the song that ends with the one it blended into, and the new song keeps counting', () {
    scenario(PlaybackMode.mixing, (async, r) {
      unawaited(r.c.setQueue([t('a'), t('b'), t('c')]));
      async.flushMicrotasks();
      listen(async, r.a, 0, 20);
      unawaited(r.c.next());
      async.flushMicrotasks();
      expect(r.c.isTransitioning, isTrue);
      r.a.emitPosition(const Duration(seconds: 21)); // both songs are heard during the blend
      r.b.emitPosition(Duration.zero);
      async.flushMicrotasks();
      r.a.emitPosition(const Duration(seconds: 22));
      r.b.emitPosition(const Duration(seconds: 1));
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 3100));
      expect(r.c.isTransitioning, isFalse);
      expect(r.events.length, 1);
      expect([r.events[0].track.id, r.events[0].listenedMs, r.events[0].mixedInto?.id], ['a', 22000, 'b']);

      listen(async, r.b, 2, 8);
      unawaited(r.c.next());
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 3100));
      expect(r.events.length, 2);
      expect([r.events[1].track.id, r.events[1].listenedMs, r.events[1].mixedInto?.id], ['b', 8000, 'c']);
    });
  });

  test('demo songs and reviewer previews are not reported', () {
    scenario(PlaybackMode.normal, (async, r) {
      unawaited(r.c.setQueue([t('demo', counts: false), t('b')]));
      async.flushMicrotasks();
      listen(async, r.a, 0, 30);
      unawaited(r.c.next());
      async.flushMicrotasks();
      expect(r.events, isEmpty);
    });
  });

  test('playing a song again with repeat-one is a second play', () {
    scenario(PlaybackMode.normal, (async, r) {
      unawaited(r.c.setQueue([t('a'), t('b')]));
      async.flushMicrotasks();
      r.c.setRepeat(RepeatMode.one);
      listen(async, r.a, 0, 35);
      r.a.finish();
      async.flushMicrotasks();
      expect(r.events.length, 1);
      expect(r.events[0].listenedMs, 35000);

      listen(async, r.a, 0, 5);
      unawaited(r.c.next());
      async.flushMicrotasks();
      expect(r.events.length, 2);
      expect([r.events[1].track.id, r.events[1].listenedMs], ['a', 5000]);
    });
  });

  test('the last song of the queue is reported when it ends, and replacing the queue ends the current play', () {
    scenario(PlaybackMode.normal, (async, r) {
      unawaited(r.c.setQueue([t('only')]));
      async.flushMicrotasks();
      listen(async, r.a, 0, 40);
      r.a.finish();
      async.flushMicrotasks();
      expect(r.events.map((e) => [e.track.id, e.listenedMs]), [['only', 40000]]);

      unawaited(r.c.setQueue([t('x'), t('y')]));
      async.flushMicrotasks();
      listen(async, r.a, 0, 12);
      unawaited(r.c.setQueue([t('z')]));
      async.flushMicrotasks();
      expect(r.events.last.track.id, 'x');
      expect(r.events.last.listenedMs, 12000);
    });
  });
}
