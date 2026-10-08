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
    this.resolveUri,
    this.loudnessLufs,
  });

  final String id;
  final String title;
  final String artist;
  final Uri uri;
  final TrackSource source;
  final Duration? duration;
  final bool allowMixing;

  /// For songs streamed from Vyro: asks the server for a fresh, short-lived address
  /// just before playing. [uri] is then only an identifier.
  final Future<Uri> Function()? resolveUri;

  /// Measured loudness (EBU R128), used later to even out volume between songs.
  final double? loudnessLufs;

  /// SRC-06 / MIX-08: YouTube items and license-restricted tracks never enter
  /// the mix engine. Any change involving them is a clean cut.
  bool get mixable => allowMixing && source != TrackSource.youtube;
}
