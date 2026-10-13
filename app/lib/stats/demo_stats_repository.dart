import 'dart:math' as math;

import 'models.dart';

/// Sample numbers with a believable shape, so both screens can be seen and
/// tried before the server connection exists.
class DemoStatsRepository implements StatsRepository {
  static final DateTime _today = DateTime.utc(2026, 10, 6);

  @override
  Future<ArtistStats> artistStats(ArtistRange range) async {
    final days = range.days;
    final daily = <DailyPoint>[
      for (var i = 0; i < days; i++)
        () {
          final plays = (120 + 60 * math.sin(i / 3) + i * 1.5 + (i % 7 == 5 ? 80 : 0)).round();
          return DailyPoint(_today.subtract(Duration(days: days - 1 - i)), plays, (plays * 0.62).round());
        }(),
    ];
    final plays = daily.fold<int>(0, (a, d) => a + d.plays);
    final listeners = (plays * 0.55).round();

    ShareRow row(String name, double share) => ShareRow(name, (plays * share).round(), share);

    return ArtistStats(
      range: range,
      plays: Delta(plays, (plays * 0.86).round()),
      listeners: Delta(listeners, (listeners * 0.92).round()),
      newFollowers: Delta((plays * 0.012).round(), (plays * 0.014).round()),
      saves: Delta((plays * 0.05).round(), (plays * 0.04).round()),
      followers: 3240,
      daily: daily,
      realtime: [for (var h = 0; h < 48; h++) (8 + 6 * math.sin(h / 4) + (h > 40 ? 10 : 0)).round()],
      newListeners: (listeners * 0.58).round(),
      returningListeners: (listeners * 0.42).round(),
      superListeners: (listeners * 0.06).round(),
      sources: [
        row('Recommendations', 0.31),
        row('Playlists', 0.24),
        row('Search', 0.22),
        row('Charts', 0.09),
        row('Shares', 0.08),
        row('Listener libraries', 0.06),
      ],
      countries: [
        row('Nigeria', 0.34),
        row('Kenya', 0.22),
        row('South Africa', 0.14),
        row('Ghana', 0.10),
        row('United Kingdom', 0.07),
        row('Other', 0.13),
      ],
      songs: const [
        SongStats(trackId: 's1', title: 'Midnight Drive', plays: 5120, listeners: 3010, completionRate: 0.71, skipRate: 0.12, saves: 410),
        SongStats(trackId: 's2', title: 'Golden Hour', plays: 3890, listeners: 2480, completionRate: 0.66, skipRate: 0.17, saves: 296),
        SongStats(trackId: 's3', title: 'Skyline', plays: 2210, listeners: 1530, completionRate: 0.58, skipRate: 0.24, saves: 140),
        SongStats(trackId: 's4', title: 'Run It Back', plays: 1480, listeners: 990, completionRate: 0.49, skipRate: 0.31, saves: 77),
        SongStats(trackId: 's5', title: 'Slow Burn', plays: 920, listeners: 640, completionRate: 0.74, skipRate: 0.09, saves: 88),
      ],
      mixedWith: const [
        MixPair('Midnight Drive', 'Golden Hour', 84),
        MixPair('Skyline', 'Run It Back', 51),
        MixPair('Slow Burn', 'Midnight Drive', 33),
      ],
    );
  }

  @override
  Future<RetentionCurve> retention(String trackId, ArtistRange range) async {
    // Starts at 100%, drops fastest in the first seconds, then levels out.
    return RetentionCurve([for (var i = 0; i <= 10; i++) i == 0 ? 1.0 : (0.93 * math.exp(-0.16 * i) + 0.1).clamp(0.0, 1.0).toDouble()]);
  }

  @override
  Future<ListenerStats> listenerStats(ListenerRange range) async {
    final scale = switch (range) {
      ListenerRange.fourWeeks => 1.0,
      ListenerRange.sixMonths => 6.8,
      ListenerRange.year => 13.5,
      ListenerRange.all => 18.8,
    };
    int s(num v) => (v * scale).round();
    return ListenerStats(
      range: range,
      minutes: s(2184),
      plays: s(612),
      songsBlended: s(238),
      artistsHeard: s(74),
      newArtists: s(19),
      streakDays: 12,
      persona: Persona.nightOwl,
      clock: [for (var h = 0; h < 24; h++) s(h >= 22 || h <= 2 ? 150 - (h % 12) * 4 : 20 + h * 3)],
      topArtists: [
        RankedItem('Nova Wave', '${s(131)} plays', s(412)),
        RankedItem('Kito', '${s(96)} plays', s(301)),
        RankedItem('Amara Sol', '${s(88)} plays', s(266)),
        RankedItem('The Drift', '${s(61)} plays', s(190)),
        RankedItem('Zuri', '${s(44)} plays', s(144)),
      ],
      topTracks: [
        RankedItem('Midnight Drive', 'Nova Wave', s(58)),
        RankedItem('Golden Hour', 'Kito', s(51)),
        RankedItem('Skyline', 'Amara Sol', s(47)),
        RankedItem('Slow Burn', 'The Drift', s(39)),
        RankedItem('Run It Back', 'Zuri', s(33)),
      ],
      topGenres: [
        RankedItem('Afrobeats', '', s(780)),
        RankedItem('Hip-Hop', '', s(520)),
        RankedItem('Amapiano', '', s(410)),
        RankedItem('R&B', '', s(260)),
        RankedItem('Gospel', '', s(120)),
      ],
    );
  }
}
