import 'track.dart';

/// Free demo songs from soundhelix.com, used to try the player and the mix
/// engine before real catalog and local files arrive.
final List<Track> demoTracks = [
  for (var i = 1; i <= 4; i++)
    Track(
      id: 'demo-$i',
      title: 'Demo song $i',
      artist: 'SoundHelix',
      uri: Uri.parse('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-$i.mp3'),
      source: TrackSource.open,
    ),
];
