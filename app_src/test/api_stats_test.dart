import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/stats/api_stats_repository.dart';
import 'package:vyro_music/stats/models.dart';

void main() {
  test('artist statistics from the server become the screen\'s model', () {
    final stats = parseArtistStats({
      'range': '28d',
      'summary': {
        'plays': {'value': 9, 'previous': 1},
        'listeners': {'value': 4, 'previous': 1},
        'newFollowers': {'value': 2, 'previous': 0},
        'saves': {'value': 1, 'previous': 0},
        'followers': 2,
      },
      'daily': [
        {'day': '2026-10-05', 'plays': 3, 'listeners': 2},
        {'day': '2026-10-06', 'plays': 6, 'listeners': 3},
      ],
      'realtime': [
        {'hour': '2026-10-06T10:00:00Z', 'plays': 4},
        {'hour': '2026-10-06T11:00:00Z', 'plays': 5},
      ],
      'audience': {'newListeners': 3, 'returningListeners': 1, 'superListeners': 1},
      'sources': [
        {'source': 'direct', 'plays': 7, 'share': 0.7778},
        {'source': 'recommendation', 'plays': 2, 'share': 0.2222},
      ],
      'countries': [
        {'country': 'KE', 'plays': 6, 'listeners': 3, 'share': 0.6667},
        {'country': 'OTHER', 'plays': 3, 'listeners': 1, 'share': 0.3333},
      ],
      'songs': [
        {'trackId': 't1', 'title': 'Song One', 'plays': 8, 'listeners': 4, 'completionRate': 0.875, 'skipRate': 0.1111, 'saves': 1},
      ],
      'mixedWith': [
        {'track': 'Song Two', 'partner': 'Song One', 'times': 1},
      ],
    }, ArtistRange.d28);

    expect(stats.plays.value, 9);
    expect(stats.plays.previous, 1);
    expect(stats.followers, 2);
    expect(stats.daily.length, 2);
    expect(stats.daily.first.date, DateTime.parse('2026-10-05'));
    expect(stats.realtime, [4, 5]);
    expect(stats.superListeners, 1);
    expect(stats.sources.first.name, 'Direct');
    expect(stats.sources.last.name, 'Recommendations');
    expect(stats.countries.first.name, 'Kenya');
    expect(stats.countries.last.name, 'Other');
    expect(stats.songs.single.completionRate, closeTo(0.875, 1e-9));
    expect(stats.mixedWith.single.partner, 'Song One');
  });

  test('listener statistics from the server become the screen\'s model', () {
    final stats = parseListenerStats({
      'range': 'year',
      'minutes': 18,
      'plays': 6,
      'songsBlended': 1,
      'artistsHeard': 1,
      'newArtists': 1,
      'streakDays': 5,
      'persona': 'night_owl',
      'clock': List<int>.generate(24, (h) => h == 10 ? 18 : 0),
      'topArtists': [
        {'id': 'a1', 'name': 'Stats Star', 'plays': 6, 'minutes': 18},
      ],
      'topTracks': [
        {'trackId': 't1', 'title': 'Song One', 'artist': 'Stats Star', 'plays': 5, 'minutes': 16},
      ],
      'topGenres': [
        {'genre': 'afrobeats', 'minutes': 16},
      ],
    }, ListenerRange.year);

    expect(stats.minutes, 18);
    expect(stats.persona, Persona.nightOwl);
    expect(stats.clock[10], 18);
    expect(stats.topArtists.single.detail, '6 plays');
    expect(stats.topTracks.single.minutes, 5); // for songs the number shown is plays
    expect(stats.topGenres.single.name, 'Afrobeats');
  });

  test('a brand-new listener (all zeros) still gives a complete model', () {
    final stats = parseListenerStats({
      'range': '4w',
      'minutes': 0,
      'plays': 0,
      'songsBlended': 0,
      'artistsHeard': 0,
      'newArtists': 0,
      'streakDays': 0,
      'persona': 'none',
      'clock': List<int>.filled(24, 0),
      'topArtists': <Object>[],
      'topTracks': <Object>[],
      'topGenres': <Object>[],
    }, ListenerRange.fourWeeks);
    expect(stats.persona, Persona.none);
    expect(stats.clock.length, 24);
    expect(stats.topArtists, isEmpty);
  });

  test('the retention curve keeps its 11 points', () {
    final curve = parseRetention({
      'plays': 9,
      'points': [for (var i = 0; i <= 10; i++) {'percent': i * 10, 'share': 1 - i / 20}],
    });
    expect(curve.points.length, 11);
    expect(curve.points.first, 1.0);
  });

  test('ranges are sent to the server in its own short form', () {
    expect([for (final r in ArtistRange.values) r.apiValue], ['7d', '28d', '90d', '365d']);
    expect([for (final r in ListenerRange.values) r.apiValue], ['4w', '6m', 'year', 'all']);
  });
}
