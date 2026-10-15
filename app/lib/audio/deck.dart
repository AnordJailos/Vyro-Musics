import 'track.dart';

/// One audio output "deck". The mix engine uses two of them: while one fades
/// out, the other fades in.
abstract class Deck {
  Future<void> load(Track track);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  Duration get position;
  Duration? get duration;
  Stream<Duration> get positionStream;

  /// Fires once when the loaded track plays to its natural end.
  Stream<void> get completedStream;

  /// True while the deck is loading or waiting for more data.
  Stream<bool> get bufferingStream;

  /// Playback errors, such as a lost connection in the middle of a song.
  Stream<Object> get errorStream;

  Future<void> dispose();
}
