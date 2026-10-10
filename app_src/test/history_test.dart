import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/history/history_store.dart';
import 'package:vyro_music/history/history_sync.dart';
import 'package:vyro_music/history/play_recorder.dart';
import 'package:vyro_music/history/play_record.dart';

PlayRecord record(String id, {String source = 'vyro', int listenedMs = 60000, int durationMs = 200000, DateTime? at, String? mixedWith, bool blended = false}) => PlayRecord(
      id: id,
      trackId: source == 'vyro' ? 'track-$id' : 'local:/music/$id.mp3',
      source: source,
      title: 'Song $id',
      artist: 'Artist',
      startedAt: at ?? DateTime.utc(2026, 10, 6, 12),
      listenedMs: listenedMs,
      durationMs: durationMs,
      mode: 'normal',
      origin: 'search',
      platform: 'android',
      blended: blended,
      mixedWithVyroId: mixedWith,
    );

Track vyroTrack(String id) => Track(id: 'vyro:$id', title: 'T$id', artist: 'A', uri: Uri(scheme: 'vyro', path: id), source: TrackSource.vyro, duration: const Duration(minutes: 3));
Track localTrack(String id) => Track(id: 'local:/music/$id.mp3', title: 'T$id', artist: 'A', uri: Uri.file('/music/$id.mp3'), source: TrackSource.local, duration: const Duration(minutes: 3), genre: 'Pop', album: 'Alb');

PlayEnded ended(Track t, {int ms = 60000, Track? into}) =>
    PlayEnded(track: t, startedAt: DateTime.utc(2026, 10, 6, 12), listenedMs: ms, mode: PlaybackMode.normal, origin: 'chart', mixedInto: into);

class FakeHistoryApi implements HistoryApi {
  final uploads = <List<String>>[];
  Object? failWith;
  Set<String> badIds = {};
  Completer<void>? hold;

  @override
  Future<void> uploadPlays(List<PlayRecord> plays) async {
    final gate = hold;
    if (gate != null) await gate.future;
    final e = failWith;
    if (e != null) throw e;
    if (plays.any((p) => badIds.contains(p.id))) throw const ApiException(400, 'invalid_request');
    uploads.add([for (final p in plays) p.id]);
  }
}

class SpySync extends HistorySync {
  SpySync(HistoryStore store) : super(store: store, api: FakeHistoryApi(), canUpload: () => true);
  int scheduled = 0;

  @override
  void schedule({bool immediately = false}) => scheduled++;
}

void main() {
  group('play records', () {
    test('make proper random UUIDs', () {
      final re = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(newUuid(), matches(re));
      expect(newUuid(math.Random(1)), matches(re));
      expect({for (var i = 0; i < 200; i++) newUuid()}.length, 200);
    });

    test('a Vyro play keeps the server id, and only names a blend partner the server knows', () {
      final both = PlayRecord.fromEnded(ended(vyroTrack('abc'), into: vyroTrack('def')), id: 'r1', platform: 'ios');
      expect([both.trackId, both.source, both.blended, both.mixedWithVyroId, both.origin, both.platform], ['abc', 'vyro', true, 'def', 'chart', 'ios']);
      final toLocal = PlayRecord.fromEnded(ended(vyroTrack('abc'), into: localTrack('x')), id: 'r2', platform: 'ios');
      expect([toLocal.blended, toLocal.mixedWithVyroId], [true, null]);
      final local = PlayRecord.fromEnded(ended(localTrack('x')), id: 'r3', platform: 'ios');
      expect([local.trackId, local.source, local.genre, local.album], ['local:/music/x.mp3', 'local', 'Pop', 'Alb']);
    });

    test('are sent to the server in its own shape, and survive being saved', () {
      final r = record('r1', mixedWith: 'def', blended: true);
      expect(r.toUpload(), {
        'id': 'r1',
        'trackId': 'track-r1',
        'startedAt': '2026-10-06T12:00:00.000Z',
        'listenedMs': 60000,
        'source': 'search',
        'platform': 'android',
        'mode': 'normal',
        'mixedWithTrackId': 'def',
      });
      expect(record('r2').toUpload().containsKey('mixedWithTrackId'), isFalse);
      final back = PlayRecord.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>);
      expect([back.id, back.listenedMs, back.blended, back.mixedWithVyroId, back.startedAt], [r.id, r.listenedMs, true, 'def', r.startedAt]);
    });

    test('count as a stream after 30 seconds, or half of a very short song', () {
      expect(record('a', listenedMs: 29999).isValidStream, isFalse);
      expect(record('a', listenedMs: 30000).isValidStream, isTrue);
      expect(record('a', listenedMs: 20000, durationMs: 40000).isValidStream, isTrue);
      expect(record('a', listenedMs: 19000, durationMs: 40000).isValidStream, isFalse);
    });
  });

  group('stores', () {
    Future<void> shared(HistoryStore Function() make) async {
      final store = make();
      await store.append(record('a'));
      await store.append(record('b'));
      expect((await store.loadAll()).map((r) => r.id), ['a', 'b']);

      await store.outboxAdd(record('a'));
      await store.outboxAdd(record('b'));
      await store.outboxAdd(record('c'));
      expect((await store.outboxPeek(2)).map((r) => r.id), ['a', 'b']);
      await store.outboxRemove({'a', 'c'});
      expect((await store.outboxPeek(10)).map((r) => r.id), ['b']);

      await store.clearHistory();
      expect(await store.loadAll(), isEmpty);
      expect((await store.outboxPeek(10)).map((r) => r.id), ['b']); // waiting plays are not lost by clearing
    }

    test('in memory', () => shared(MemoryHistoryStore.new));

    group('on disk', () {
      late Directory dir;
      setUp(() => dir = Directory.systemTemp.createTempSync('vyro_hist_'));
      tearDown(() => dir.deleteSync(recursive: true));
      FileHistoryStore make() => FileHistoryStore(directory: () async => dir);

      test('behaves the same, and a new start reads what was saved', () async {
        await shared(make);
        await make().append(record('z'));
        expect((await make().loadAll()).map((r) => r.id), ['z']);
      });

      test('skips a damaged line instead of losing the whole history', () async {
        final store = make();
        await store.append(record('a'));
        File('${dir.path}/plays.jsonl').writeAsStringSync('{ not json\n', mode: FileMode.append);
        await store.append(record('b'));
        expect((await store.loadAll()).map((r) => r.id), ['a', 'b']);
      });

      test('plays that end at the same moment are all kept', () async {
        final store = make();
        await Future.wait([for (var i = 0; i < 40; i++) store.append(record('p$i'))]);
        await Future.wait([for (var i = 0; i < 40; i++) store.outboxAdd(record('o$i'))]);
        expect((await store.loadAll()).length, 40);
        expect((await store.outboxPeek(100)).length, 40);
      });

      test('keeps only the most recent plays once the history is very long', () async {
        final lines = [for (var i = 0; i < maxHistoryRecords + 5; i++) jsonEncode(record('r$i').toJson())].join('\n');
        File('${dir.path}/plays.jsonl').writeAsStringSync('$lines\n');
        final loaded = await make().loadAll();
        expect(loaded.length, maxHistoryRecords);
        expect(loaded.first.id, 'r5');
        expect(loaded.last.id, 'r${maxHistoryRecords + 4}');
      });
    });
  });

  group('recorder', () {
    test('keeps every play in the history, and queues only Vyro plays to be sent', () async {
      final store = MemoryHistoryStore();
      final sync = SpySync(store);
      var n = 0;
      final recorder = PlayRecorder(store: store, sync: sync, newId: () => 'id-${++n}');
      await recorder.record(ended(localTrack('a')));
      expect(sync.scheduled, 0);
      await recorder.record(ended(vyroTrack('v1')));
      expect(sync.scheduled, 1);
      expect((await store.loadAll()).length, 2);
      final box = await store.outboxPeek(10);
      expect(box.map((r) => r.source), ['vyro']);
    });

    test('in a private session the play is not kept in the history, but is still sent', () async {
      final store = MemoryHistoryStore();
      final recorder = PlayRecorder(store: store, isPrivate: () => true);
      await recorder.record(ended(vyroTrack('v1')));
      await recorder.record(ended(localTrack('a')));
      expect(await store.loadAll(), isEmpty);
      expect((await store.outboxPeek(10)).length, 1); // the Vyro play, so the artist still gets counted
    });

    test('ignores a play that lasted under a second', () async {
      final store = MemoryHistoryStore();
      final recorder = PlayRecorder(store: store);
      await recorder.record(ended(localTrack('a'), ms: 900));
      expect(await store.loadAll(), isEmpty);
    });

    test('gives every play its own id', () async {
      final store = MemoryHistoryStore();
      final recorder = PlayRecorder(store: store);
      await Future.wait([for (var i = 0; i < 20; i++) recorder.record(ended(localTrack('a$i')))]);
      expect({for (final r in await store.loadAll()) r.id}.length, 20);
    });
  });

  group('sending plays to the server', () {
    late MemoryHistoryStore store;
    late FakeHistoryApi api;
    var signedIn = true;
    HistorySync make() => HistorySync(store: store, api: api, canUpload: () => signedIn);

    setUp(() {
      store = MemoryHistoryStore();
      api = FakeHistoryApi();
      signedIn = true;
    });

    Future<void> fill(int n) async {
      for (var i = 0; i < n; i++) {
        await store.outboxAdd(record('r$i'));
      }
    }

    test('sends in batches of 100 and empties the outbox', () async {
      await fill(250);
      await make().flush();
      expect(api.uploads.map((u) => u.length), [100, 100, 50]);
      expect(await store.outboxPeek(10), isEmpty);
    });

    test('keeps everything when there is no connection, and sends it all later', () async {
      await fill(5);
      api.failWith = const ApiException(0, 'network');
      await make().flush();
      expect(api.uploads, isEmpty);
      expect((await store.outboxPeek(10)).length, 5);
      api.failWith = null;
      await make().flush();
      expect(api.uploads.single.length, 5);
    });

    test('keeps everything on server trouble or an expired login', () async {
      await fill(3);
      for (final status in [401, 429, 500, 503]) {
        api.failWith = ApiException(status, 'x');
        await make().flush();
        expect((await store.outboxPeek(10)).length, 3, reason: '$status');
      }
    });

    test('sends nothing for a guest, and sends the waiting plays after sign-in', () async {
      await fill(4);
      signedIn = false;
      final sync = make();
      await sync.flush();
      expect(api.uploads, isEmpty);
      signedIn = true;
      await sync.flush();
      expect(api.uploads.single.length, 4);
    });

    test('drops one invalid play without blocking all the others', () async {
      await fill(7);
      api.badIds = {'r3'};
      await make().flush();
      final sent = api.uploads.expand((u) => u).toSet();
      expect(sent, {'r0', 'r1', 'r2', 'r4', 'r5', 'r6'});
      expect(await store.outboxPeek(10), isEmpty); // the bad one was dropped, not retried forever
    });

    test('does not lose a play that ends while a batch is on its way', () async {
      await fill(2);
      api.hold = Completer<void>();
      final sync = make();
      final running = sync.flush();
      await Future<void>.delayed(Duration.zero);
      await store.outboxAdd(record('late'));
      api.hold!.complete();
      await running;
      expect((await store.outboxPeek(10)).map((r) => r.id), isEmpty); // the loop picked the late one up too
      expect(api.uploads.expand((u) => u).toSet(), {'r0', 'r1', 'late'});
    });

    test('two flushes at once do not send the same plays twice', () async {
      await fill(3);
      api.hold = Completer<void>();
      final sync = make();
      final a = sync.flush();
      final b = sync.flush();
      await Future<void>.delayed(Duration.zero);
      api.hold!.complete();
      await Future.wait([a, b]);
      expect(api.uploads.length, 1);
    });
  });
}
