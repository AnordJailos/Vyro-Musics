import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'deck.dart';
import 'track.dart';

/// Deck backed by just_audio (Android, iOS, macOS natively; Windows through
/// just_audio_media_kit, which is initialized in main.dart).
class JustAudioDeck implements Deck {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> load(Track track) async {
    final uri = track.uri;
    if (uri.scheme == 'file') {
      await _player.setFilePath(uri.toFilePath());
    } else {
      await _player.setUrl(uri.toString());
    }
  }

  // just_audio's play() only completes when playback stops, so it must not be
  // awaited here.
  @override
  Future<void> play() async {
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<void> get completedStream => _player.processingStateStream
      .where((state) => state == ProcessingState.completed)
      .map((_) {});

  @override
  Future<void> dispose() => _player.dispose();
}
