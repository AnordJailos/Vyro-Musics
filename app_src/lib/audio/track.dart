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
    this.album,
    this.genre,
    this.countsAsListening = true,
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
  final String? album;
  final String? genre;

  /// False for demo songs and reviewer previews, which must not show up in anyone's listening history.
  final bool countsAsListening;

  /// The same song with another way of finding its address (used when a saved queue is brought back).
  Track withResolveUri(Future<Uri> Function()? resolver) => Track(
        id: id,
        title: title,
        artist: artist,
        uri: uri,
        source: source,
        duration: duration,
        allowMixing: allowMixing,
        resolveUri: resolver,
        loudnessLufs: loudnessLufs,
        album: album,
        genre: genre,
        countsAsListening: countsAsListening,
      );

  /// SRC-06 / MIX-08: YouTube items and license-restricted tracks never enter
  /// the mix engine. Any change involving them is a clean cut.
  bool get mixable => allowMixing && source != TrackSource.youtube;
}
