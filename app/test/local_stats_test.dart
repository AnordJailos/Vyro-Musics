import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/history/history_store.dart';
import 'package:vyro_music/history/local_stats.dart';
import 'package:vyro_music/history/play_record.dart';
import 'package:vyro_music/stats/models.dart';

final now = DateTime(2026, 10, 6, 12); // local time, so the tests do not depend on the time zone

PlayRecord rec(int daysAgo, int hour, String artist, String title, int ms, {String source = 'local', String? genre = 'Pop', bool blended = false, int durationMs = 200000}) {
  final at = DateTime(2026, 10, 6 - daysAgo, hour, 15);
  return PlayRecord(
    id: '$daysAgo-$hour-$title-$artist-$source',
    trackId: '$source:$title:$artist',
    source: source,
    title: title,
    artist: artist,
    genre: genre,
    startedAt: at.toUtc(),
    listenedMs: ms,
    durationMs: durationMs,
    mode: 'normal',
    origin: 'library',
    platform: 'android',
    blended: blended,
  );
}

class FakeServerStats implements StatsRepository {
  FakeServerStats(this.listener, {this.fail});

  final ListenerStats listener;
  final Object? fail;

  @override
  Future<ListenerStats> listenerStats(ListenerRange range) async {
    if (fail != null) throw fail!;
    return listener;
  }

  @override
  Future<ArtistStats> artistStats(ArtistRange range) async => throw UnimplementedError();

  @override
  Future<RetentionCurve> retention(String trackId, ArtistRange range) async => throw UnimplementedError();
}

ListenerStats serverStats({List<String> days = const ['2026-10-05'], int minutes = 100, int streak = 1}) => ListenerStats(
      range: ListenerRange.fourWeeks,
      minutes: minutes,
      plays: 20,
      songsBlended: 4,
      artistsHeard: 3,
      newArtists: 1,
      streakDays: streak,
      persona: Persona.daytime,
      clock: List<int>.generate(24, (h) => h == 10 ? minutes : 0),
      topArtists: const [RankedItem('Nova Wave', '12 plays', 60, plays: 12), RankedItem('Kito', '8 plays', 40, plays: 8)],
      topTracks: const [RankedItem('Night Drive', 'Nova Wave', 12, plays: 12)],
      topGenres: const [RankedItem('Afrobeats', '', 90)],
      activeDays: days,
    );

void main() {
  group('helpers', () {
    test('listening personalities by the hours people listen', () {
      List<int> at(int hour, int minutes) => List<int>.generate(24, (h) => h == hour ? minutes : 0);
      expect(personaFromClock(at(23, 100)), Persona.nightOwl);
      expect(personaFromClock(at(6, 100)), Persona.earlyBird);
      expect(personaFromClock(at(14, 100)), Persona.daytime);
      expect(personaFromClock(at(19, 100)), Persona.allDay);
      expect(personaFromClock(at(1, 0)), Persona.none);
    });

    test('streaks end today or yesterday and break at the first gap', () {
      expect(streakFrom(['2026-10-06', '2026-10-05', '2026-10-03'], '2026-10-06'), 2);
      expect(streakFrom(['2026-10-05', '2026-10-04'], '2026-10-06'), 2);
      expect(streakFrom(['2026-10-03'], '2026-10-06'), 0);
      expect(streakFrom(const [], '2026-10-06'), 0);
      expect(streakFrom(['2026-03-01', '2026-02-28'], '2026-03-01'), 2); // across a month end
    });
  });

  group('from the history on the device', () {
    final history = [
      rec(1, 10, 'Ann', 'Alpha', 200000, genre: 'Pop'),
      rec(1, 10, 'Ann', 'Alpha', 200000, genre: 'Pop', blended: true),
      rec(2, 10, 'Ann', 'Beta', 200000, genre: 'pop'),
      rec(3, 10, 'Bob', 'Gamma', 120000, genre: 'Jazz'),
      rec(3, 11, 'Bob', 'Skipped', 10000, genre: 'Jazz'), // under 30 seconds: heard, but not a play
    ];

    test('minutes, plays, blends, artists, and the favorites lists', () {
      final s = computeListenerStats(history, ListenerRange.fourWeeks, now: now);
      expect(s.minutes, (200000 * 3 + 120000 + 10000) ~/ 60000);
      expect(s.plays, 4);
      expect(s.songsBlended, 1);
      expect(s.artistsHeard, 2);
      expect(s.topArtists.first.name, 'Ann');
      expect(s.topArtists.first.plays, 3);
      expect(s.topTracks.first.name, 'Alpha');
      expect(s.topTracks.first.minutes, 2); // for songs the number is plays
      expect(s.topTracks.any((t) => t.name == 'Skipped'), isFalse);
      expect(s.topGenres.map((g) => g.name), ['Pop', 'Jazz']); // "Pop" and "pop" are one genre
    });

    test('the listening clock, personality and streak', () {
      final s = computeListenerStats(history, ListenerRange.fourWeeks, now: now);
      expect(s.clock[10], (200000 * 3 + 120000) ~/ 60000);
      expect(s.clock[11], 0);
      expect(s.persona, Persona.daytime);
      expect(s.streakDays, 3); // Oct 5, 4 and 3; none today yet
      expect(s.activeDays, ['2026-10-05', '2026-10-04', '2026-10-03']);
    });

    test('only counts plays inside the period, and knows who is new in it', () {
      final long = [...history, rec(40, 10, 'Old Friend', 'Ancient', 200000), rec(1, 12, 'Old Friend', 'Recent', 200000)];
      final month = computeListenerStats(long, ListenerRange.fourWeeks, now: now);
      final half = computeListenerStats(long, ListenerRange.sixMonths, now: now);
      expect(month.plays, 5);
      expect(half.plays, 6);
      expect(month.newArtists, 2); // Ann and Bob; Old Friend was first heard 40 days ago
      expect(half.newArtists, 3);
    });

    test('leaves out Vyro plays when the server already counts them', () {
      final mixed = [...history, rec(1, 9, 'Nova Wave', 'Night Drive', 200000, source: 'vyro')];
      expect(computeListenerStats(mixed, ListenerRange.fourWeeks, now: now).plays, 5);
      final local = computeListenerStats(mixed, ListenerRange.fourWeeks, now: now, includeVyro: false);
      expect(local.plays, 4);
      expect(local.topArtists.any((a) => a.name == 'Nova Wave'), isFalse);
    });

    test('an empty history gives a complete set of zeros', () {
      final s = computeListenerStats(const [], ListenerRange.all, now: now);
      expect([s.minutes, s.plays, s.streakDays, s.persona], [0, 0, 0, Persona.none]);
      expect(s.clock.length, 24);
      expect(s.topArtists, isEmpty);
    });
  });

  group('adding Vyro and device listening together', () {
    test('adds the numbers, the clock and the favorites, and works the streak out from both lists of days', () {
      final server = serverStats(days: ['2026-10-05', '2026-10-04'], streak: 2);
      final local = computeListenerStats([rec(3, 10, 'Ann', 'Alpha', 200000), rec(4, 10, 'Ann', 'Alpha', 200000)], ListenerRange.fourWeeks, now: now);
      final merged = mergeListenerStats(server, local, now: now);
      expect(merged.minutes, 100 + 6);
      expect(merged.plays, 22);
      expect(merged.songsBlended, 4);
      expect(merged.clock[10], 100 + 6);
      expect(merged.activeDays, ['2026-10-05', '2026-10-04', '2026-10-03', '2026-10-02']);
      expect(merged.streakDays, 4); // neither list alone gives 4
      expect(merged.topArtists.map((a) => a.name), ['Nova Wave', 'Kito', 'Ann']);
      expect(merged.topTracks.map((t) => t.name), ['Night Drive', 'Alpha']);
      expect(merged.topGenres.map((g) => g.name), ['Afrobeats', 'Pop']);
    });

    test('joins the same artist and song from both sources', () {
      final local = computeListenerStats([rec(1, 10, 'Nova Wave', 'Night Drive', 200000)], ListenerRange.fourWeeks, now: now);
      final merged = mergeListenerStats(serverStats(), local, now: now);
      final nova = merged.topArtists.firstWhere((a) => a.name == 'Nova Wave');
      expect([nova.plays, nova.minutes], [13, 63]);
      expect(merged.topTracks.single.minutes, 13);
      expect(merged.topTracks.single.name, 'Night Drive');
    });

    test('uses the better streak when a source has no list of days', () {
      final merged = mergeListenerStats(serverStats(days: const [], streak: 7), computeListenerStats(const [], ListenerRange.fourWeeks, now: now), now: now);
      expect(merged.streakDays, 7);
    });
  });

  group('the signed-in profile', () {
    test('combines the server with music on the device', () async {
      final store = MemoryHistoryStore();
      await store.append(rec(1, 10, 'Ann', 'Alpha', 200000));
      await store.append(rec(1, 10, 'Nova Wave', 'Night Drive', 200000, source: 'vyro')); // already counted by the server
      final repo = MergedStatsRepository(server: FakeServerStats(serverStats()), store: store, clock: () => now);
      final s = await repo.listenerStats(ListenerRange.fourWeeks);
      expect(s.plays, 21); // 20 from the server and 1 from the device
    });

    test('falls back to the history on the device when the server cannot be reached', () async {
      final store = MemoryHistoryStore();
      await store.append(rec(1, 10, 'Ann', 'Alpha', 200000));
      await store.append(rec(1, 10, 'Nova Wave', 'Night Drive', 200000, source: 'vyro'));
      final repo = MergedStatsRepository(server: FakeServerStats(serverStats(), fail: const ApiException(0, 'network')), store: store, clock: () => now);
      final s = await repo.listenerStats(ListenerRange.fourWeeks);
      expect(s.plays, 2); // here the Vyro play counts too, because nothing else is counting it
    });

    test('leaves artist statistics to the server', () async {
      final repo = MergedStatsRepository(server: FakeServerStats(serverStats()), store: MemoryHistoryStore());
      await expectLater(repo.artistStats(ArtistRange.d28), throwsA(isA<UnimplementedError>()));
    });
  });
}
