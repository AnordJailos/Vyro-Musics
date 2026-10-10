import '../auth/api_errors.dart';
import '../auth/validators.dart' show formatDate;
import '../stats/models.dart';
import 'history_store.dart';
import 'play_record.dart';

/// Which listening personality the hours of the day point to (same rule as the server).
Persona personaFromClock(List<int> clock) {
  final total = clock.fold<int>(0, (a, b) => a + b);
  if (total == 0) return Persona.none;
  double share(List<int> hours) => hours.fold<int>(0, (a, h) => a + (h < clock.length ? clock[h] : 0)) / total;
  if (share(const [22, 23, 0, 1, 2, 3, 4]) >= 0.4) return Persona.nightOwl;
  if (share(const [4, 5, 6, 7, 8]) >= 0.4) return Persona.earlyBird;
  if (share(const [9, 10, 11, 12, 13, 14, 15, 16, 17]) >= 0.6) return Persona.daytime;
  return Persona.allDay;
}

int _dayNumber(String day) {
  final p = day.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])).millisecondsSinceEpoch ~/ 86400000;
}

/// Days in a row with listening, ending today or yesterday. [days] are YYYY-MM-DD, newest first.
int streakFrom(List<String> days, String today) {
  if (days.isEmpty) return 0;
  final gap = _dayNumber(today) - _dayNumber(days.first);
  if (gap != 0 && gap != 1) return 0;
  var streak = 1;
  for (var i = 1; i < days.length; i++) {
    if (_dayNumber(days[i - 1]) - _dayNumber(days[i]) != 1) break;
    streak++;
  }
  return streak;
}

String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Listening statistics worked out from the history kept on the device.
ListenerStats computeListenerStats(List<PlayRecord> records, ListenerRange range, {required DateTime now, bool includeVyro = true}) {
  final span = switch (range) {
    ListenerRange.fourWeeks => 28,
    ListenerRange.sixMonths => 182,
    ListenerRange.year => 365,
    ListenerRange.all => null,
  };
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final start = span == null ? null : DateTime(tomorrow.year, tomorrow.month, tomorrow.day - span);
  bool inWindow(DateTime t) => (start == null || !t.isBefore(start)) && t.isBefore(tomorrow);

  final usable = [for (final r in records) if (includeVyro || r.source != 'vyro') r];
  final windowed = [for (final r in usable) if (inWindow(r.startedAt.toLocal())) r];

  final clockMs = List<int>.filled(24, 0);
  final artists = <String, _Tally>{};
  final tracks = <String, _Tally>{};
  final genres = <String, int>{};
  var totalMs = 0;
  var plays = 0;
  var blends = 0;
  for (final r in windowed) {
    totalMs += r.listenedMs;
    clockMs[r.startedAt.toLocal().hour] += r.listenedMs;
    if (r.blended) blends++;
    if (!r.isValidStream) continue;
    plays++;
    artists.putIfAbsent(r.artist.toLowerCase(), () => _Tally(r.artist, ''))
      ..plays += 1
      ..ms += r.listenedMs;
    tracks.putIfAbsent(r.trackId, () => _Tally(r.title, r.artist))
      ..plays += 1
      ..ms += r.listenedMs;
  }
  for (final r in windowed) {
    final g = r.genre;
    if (g == null || g.isEmpty || g.toLowerCase() == 'unknown genre' || g.toLowerCase() == 'other') continue;
    genres[g.toLowerCase()] = (genres[g.toLowerCase()] ?? 0) + r.listenedMs;
  }

  // An artist is "new" when their first valid play, ever, falls inside the period.
  final firstHeard = <String, DateTime>{};
  for (final r in usable.where((r) => r.isValidStream)) {
    final key = r.artist.toLowerCase();
    final t = r.startedAt.toLocal();
    final seen = firstHeard[key];
    if (seen == null || t.isBefore(seen)) firstHeard[key] = t;
  }
  final newArtists = firstHeard.values.where(inWindow).length;

  final days = {for (final r in usable) formatDate(r.startedAt.toLocal())}.toList()..sort((a, b) => b.compareTo(a));
  final clock = [for (final ms in clockMs) ms ~/ 60000];
  final topArtists = artists.values.toList()..sort((a, b) => b.ms != a.ms ? b.ms.compareTo(a.ms) : b.plays.compareTo(a.plays));
  final topTracks = tracks.values.toList()..sort((a, b) => b.plays != a.plays ? b.plays.compareTo(a.plays) : b.ms.compareTo(a.ms));
  final topGenres = genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  return ListenerStats(
    range: range,
    minutes: totalMs ~/ 60000,
    plays: plays,
    songsBlended: blends,
    artistsHeard: artists.length,
    newArtists: newArtists,
    streakDays: streakFrom(days, formatDate(now)),
    persona: personaFromClock(clock),
    clock: clock,
    topArtists: [for (final t in topArtists.take(5)) RankedItem(t.name, '${t.plays} plays', t.ms ~/ 60000, plays: t.plays)],
    topTracks: [for (final t in topTracks.take(5)) RankedItem(t.name, t.detail, t.plays, plays: t.plays)],
    topGenres: [for (final g in topGenres.take(5)) RankedItem(_titleCase(g.key), '', g.value ~/ 60000)],
    activeDays: days,
  );
}

class _Tally {
  _Tally(this.name, this.detail);
  final String name;
  final String detail;
  int plays = 0;
  int ms = 0;
}

/// Adds two sets of statistics together, for example Vyro listening from the server and listening to music on the device.
ListenerStats mergeListenerStats(ListenerStats a, ListenerStats b, {required DateTime now}) {
  List<RankedItem> top(List<RankedItem> x, List<RankedItem> y, String Function(RankedItem) key, {bool byPlays = false}) {
    final merged = <String, RankedItem>{};
    for (final item in [...x, ...y]) {
      final k = key(item);
      final seen = merged[k];
      merged[k] = seen == null
          ? item
          : RankedItem(seen.name, byPlays ? seen.detail : '${seen.plays + item.plays} plays', seen.minutes + item.minutes, plays: seen.plays + item.plays);
    }
    final list = merged.values.toList()..sort((p, q) => q.minutes != p.minutes ? q.minutes.compareTo(p.minutes) : q.plays.compareTo(p.plays));
    return list.take(5).toList();
  }

  final clock = [for (var h = 0; h < 24; h++) (h < a.clock.length ? a.clock[h] : 0) + (h < b.clock.length ? b.clock[h] : 0)];
  final days = {...a.activeDays, ...b.activeDays}.toList()..sort((p, q) => q.compareTo(p));
  return ListenerStats(
    range: a.range,
    minutes: a.minutes + b.minutes,
    plays: a.plays + b.plays,
    songsBlended: a.songsBlended + b.songsBlended,
    artistsHeard: a.artistsHeard + b.artistsHeard,
    newArtists: a.newArtists + b.newArtists,
    // With both lists of days the streak is exact; without them, the better of the two is the best available.
    streakDays: days.isEmpty ? (a.streakDays > b.streakDays ? a.streakDays : b.streakDays) : streakFrom(days, formatDate(now)),
    persona: personaFromClock(clock),
    clock: clock,
    topArtists: top(a.topArtists, b.topArtists, (i) => i.name.toLowerCase()),
    topTracks: top(a.topTracks, b.topTracks, (i) => '${i.name.toLowerCase()}|${i.detail.toLowerCase()}', byPlays: true),
    topGenres: top(a.topGenres, b.topGenres, (i) => i.name.toLowerCase()),
    activeDays: days,
  );
}

/// Statistics for a signed-in listener: Vyro listening from the server, plus music played from the device. With no
/// connection, everything comes from the history on the device.
class MergedStatsRepository implements StatsRepository {
  MergedStatsRepository({required this.server, required this.store, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final StatsRepository server;
  final HistoryStore store;
  final DateTime Function() _clock;

  @override
  Future<ArtistStats> artistStats(ArtistRange range) => server.artistStats(range);

  @override
  Future<RetentionCurve> retention(String trackId, ArtistRange range) => server.retention(trackId, range);

  @override
  Future<ListenerStats> listenerStats(ListenerRange range) async {
    final history = await store.loadAll();
    final now = _clock();
    try {
      final fromServer = await server.listenerStats(range);
      // Vyro plays are already counted by the server, so only music from the device is added.
      return mergeListenerStats(fromServer, computeListenerStats(history, range, now: now, includeVyro: false), now: now);
    } on ApiException {
      return computeListenerStats(history, range, now: now);
    }
  }
}
