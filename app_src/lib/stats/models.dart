enum ArtistRange {
  d7(7, '7 days'),
  d28(28, '28 days'),
  d90(90, '90 days'),
  d365(365, '12 months');

  const ArtistRange(this.days, this.label);
  final int days;
  final String label;
}

enum ListenerRange {
  fourWeeks('4 weeks'),
  sixMonths('6 months'),
  year('This year'),
  all('All time');

  const ListenerRange(this.label);
  final String label;
}

enum Persona {
  nightOwl('Night owl', 'Most of your listening happens late at night.'),
  earlyBird('Early bird', 'You start the day with music.'),
  daytime('Daytime listener', 'Your music fills the working day.'),
  allDay('All-day listener', 'You listen at every hour.'),
  none('Not enough listening yet', 'Play a few songs and your listening personality appears here.');

  const Persona(this.title, this.blurb);
  final String title;
  final String blurb;
}

/// A number for this period together with the same number for the period before it.
class Delta {
  const Delta(this.value, this.previous);
  final int value;
  final int previous;
}

class DailyPoint {
  const DailyPoint(this.date, this.plays, this.listeners);
  final DateTime date;
  final int plays;
  final int listeners;
}

class ShareRow {
  const ShareRow(this.name, this.plays, this.share);
  final String name;
  final int plays;
  final double share; // 0..1
}

class SongStats {
  const SongStats({
    required this.trackId,
    required this.title,
    required this.plays,
    required this.listeners,
    required this.completionRate,
    required this.skipRate,
    required this.saves,
  });

  final String trackId;
  final String title;
  final int plays;
  final int listeners;
  final double completionRate; // streams that reached 90% of the song
  final double skipRate; // starts that ended before a valid stream
  final int saves;
}

class MixPair {
  const MixPair(this.track, this.partner, this.times);
  final String track;
  final String partner;
  final int times;
}

class ArtistStats {
  const ArtistStats({
    required this.range,
    required this.plays,
    required this.listeners,
    required this.newFollowers,
    required this.saves,
    required this.followers,
    required this.daily,
    required this.realtime,
    required this.newListeners,
    required this.returningListeners,
    required this.superListeners,
    required this.sources,
    required this.countries,
    required this.songs,
    required this.mixedWith,
  });

  final ArtistRange range;
  final Delta plays;
  final Delta listeners;
  final Delta newFollowers;
  final Delta saves;
  final int followers;
  final List<DailyPoint> daily;
  final List<int> realtime; // plays per hour, last 48 hours
  final int newListeners;
  final int returningListeners;
  final int superListeners;
  final List<ShareRow> sources;
  final List<ShareRow> countries;
  final List<SongStats> songs;
  final List<MixPair> mixedWith;
}

/// Share of plays still going at every 10% of the song: 11 values from 0% to 100%.
class RetentionCurve {
  const RetentionCurve(this.points);
  final List<double> points;
}

class RankedItem {
  const RankedItem(this.name, this.detail, this.minutes);
  final String name;
  final String detail;
  final int minutes;
}

class ListenerStats {
  const ListenerStats({
    required this.range,
    required this.minutes,
    required this.plays,
    required this.songsBlended,
    required this.artistsHeard,
    required this.newArtists,
    required this.streakDays,
    required this.persona,
    required this.clock,
    required this.topArtists,
    required this.topTracks,
    required this.topGenres,
  });

  final ListenerRange range;
  final int minutes;
  final int plays;
  final int songsBlended;
  final int artistsHeard;
  final int newArtists;
  final int streakDays;
  final Persona persona;
  final List<int> clock; // minutes per hour of the day, 24 values
  final List<RankedItem> topArtists;
  final List<RankedItem> topTracks;
  final List<RankedItem> topGenres;
}

/// Where the statistics come from. The demo implementation below feeds the
/// screens until the app is connected to the server.
abstract class StatsRepository {
  Future<ArtistStats> artistStats(ArtistRange range);
  Future<RetentionCurve> retention(String trackId, ArtistRange range);
  Future<ListenerStats> listenerStats(ListenerRange range);
}
