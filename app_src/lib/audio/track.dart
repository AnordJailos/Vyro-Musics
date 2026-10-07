enum TrackSource { local, vyro, open, youtube }

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.uri,
    this.source = TrackSource.vyro,
    this.duration,
    this.allowMixing = true,
  });

  final String id;
  final String title;
  final String artist;
  final Uri uri;
  final TrackSource source;
  final Duration? duration;
  final bool allowMixing;

  /// SRC-06 / MIX-08: YouTube items and license-restricted tracks never enter
  /// the mix engine. Any change involving them is a clean cut.
  bool get mixable => allowMixing && source != TrackSource.youtube;
}
