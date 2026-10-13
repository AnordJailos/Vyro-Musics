import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'deck.dart';
import 'track.dart';

/// Deck backed by just_audio (Android, iOS, macOS natively; Windows through
/// just_audio_media_kit, which is initialized in main.dart).
class JustAudioDeck implements Deck {
  JustAudioDeck() {
    // just_audio reports playback failures as errors on this stream.
    _player.playbackEventStream.listen((_) {}, onError: (Object error, StackTrace _) => _errors.add(error));
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  @override
  Future<void> load(Track track) async {
    final resolver = track.resolveUri;
    final uri = resolver != null ? await resolver() : track.uri;
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
  Stream<bool> get bufferingStream => _player.processingStateStream.map((s) => s == ProcessingState.loading || s == ProcessingState.buffering).distinct();

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<void> dispose() async {
    await _errors.close();
    await _player.dispose();
  }
}
