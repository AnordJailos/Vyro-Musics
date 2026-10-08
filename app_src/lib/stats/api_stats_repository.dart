import '../auth/api_client.dart';
import '../auth/countries.dart';
import 'models.dart';

extension ArtistRangeApi on ArtistRange {
  String get apiValue => switch (this) {
        ArtistRange.d7 => '7d',
        ArtistRange.d28 => '28d',
        ArtistRange.d90 => '90d',
        ArtistRange.d365 => '365d',
      };
}

extension ListenerRangeApi on ListenerRange {
  String get apiValue => switch (this) {
        ListenerRange.fourWeeks => '4w',
        ListenerRange.sixMonths => '6m',
        ListenerRange.year => 'year',
        ListenerRange.all => 'all',
      };
}

Map<String, Object?> _m(Object? v) => (v as Map).cast<String, Object?>();
List<Map<String, Object?>> _list(Object? v) => [for (final e in (v as List? ?? const [])) _m(e)];
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

const _sourceNames = {
  'search': 'Search',
  'recommendation': 'Recommendations',
  'playlist': 'Playlists',
  'chart': 'Charts',
  'share': 'Shares',
  'library': 'Listener libraries',
  'direct': 'Direct',
};

/// Turns the server's artist statistics into the model the screen shows.
ArtistStats parseArtistStats(Map<String, Object?> j, ArtistRange range) {
  final summary = _m(j['summary']);
  Delta delta(String key) {
    final m = _m(summary[key]);
    return Delta(_i(m['value']), _i(m['previous']));
  }

  final audience = _m(j['audience']);
  return ArtistStats(
    range: range,
    plays: delta('plays'),
    listeners: delta('listeners'),
    newFollowers: delta('newFollowers'),
    saves: delta('saves'),
    followers: _i(summary['followers']),
    daily: [for (final d in _list(j['daily'])) DailyPoint(DateTime.parse(d['day'] as String), _i(d['plays']), _i(d['listeners']))],
    realtime: [for (final r in _list(j['realtime'])) _i(r['plays'])],
    newListeners: _i(audience['newListeners']),
    returningListeners: _i(audience['returningListeners']),
    superListeners: _i(audience['superListeners']),
    sources: [for (final s in _list(j['sources'])) ShareRow(_sourceNames[s['source']] ?? '${s['source']}', _i(s['plays']), _d(s['share']))],
    countries: [for (final c in _list(j['countries'])) ShareRow(countryName('${c['country']}'), _i(c['plays']), _d(c['share']))],
    songs: [
      for (final s in _list(j['songs']))
        SongStats(
          trackId: s['trackId'] as String,
          title: s['title'] as String,
          plays: _i(s['plays']),
          listeners: _i(s['listeners']),
          completionRate: _d(s['completionRate']),
          skipRate: _d(s['skipRate']),
          saves: _i(s['saves']),
        ),
    ],
    mixedWith: [for (final p in _list(j['mixedWith'])) MixPair(p['track'] as String, p['partner'] as String, _i(p['times']))],
  );
}

RetentionCurve parseRetention(Map<String, Object?> j) => RetentionCurve([for (final p in _list(j['points'])) _d(p['share'])]);

Persona _persona(String? s) => switch (s) {
      'night_owl' => Persona.nightOwl,
      'early_bird' => Persona.earlyBird,
      'daytime' => Persona.daytime,
      'all_day' => Persona.allDay,
      _ => Persona.none,
    };

/// Turns the server's listener statistics into the model the screen shows.
/// For songs the number shown is plays; for artists and genres it is minutes.
ListenerStats parseListenerStats(Map<String, Object?> j, ListenerRange range) {
  final clock = [for (final v in (j['clock'] as List? ?? const [])) _i(v)];
  return ListenerStats(
    range: range,
    minutes: _i(j['minutes']),
    plays: _i(j['plays']),
    songsBlended: _i(j['songsBlended']),
    artistsHeard: _i(j['artistsHeard']),
    newArtists: _i(j['newArtists']),
    streakDays: _i(j['streakDays']),
    persona: _persona(j['persona'] as String?),
    clock: clock.length == 24 ? clock : List<int>.filled(24, 0),
    topArtists: [for (final a in _list(j['topArtists'])) RankedItem(a['name'] as String, '${_i(a['plays'])} plays', _i(a['minutes']))],
    topTracks: [for (final t in _list(j['topTracks'])) RankedItem(t['title'] as String, t['artist'] as String, _i(t['plays']))],
    topGenres: [for (final g in _list(j['topGenres'])) RankedItem(_titleCase(g['genre'] as String), '', _i(g['minutes']))],
  );
}

/// Real statistics from the server (used when someone is signed in).
class ApiStatsRepository implements StatsRepository {
  ApiStatsRepository(this._client);

  final ApiClient _client;

  @override
  Future<ArtistStats> artistStats(ArtistRange range) async =>
      parseArtistStats(_m(await _client.send('GET', '/v1/artists/me/stats', query: {'range': range.apiValue})), range);

  @override
  Future<RetentionCurve> retention(String trackId, ArtistRange range) async =>
      parseRetention(_m(await _client.send('GET', '/v1/artists/me/tracks/$trackId/retention', query: {'range': range.apiValue})));

  @override
  Future<ListenerStats> listenerStats(ListenerRange range) async => parseListenerStats(
        _m(await _client.send('GET', '/v1/me/stats', query: {'range': range.apiValue, 'tzOffsetMinutes': '${DateTime.now().timeZoneOffset.inMinutes}'})),
        range,
      );
}
