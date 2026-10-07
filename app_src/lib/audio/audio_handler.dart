import 'package:audio_service/audio_service.dart';

import 'playback_controller.dart';

/// Connects the player to the system: notification, lock screen, headset
/// buttons, Bluetooth and car controls, and background playback. It does no
/// audio work of its own; every command goes to [PlaybackController].
class VyroAudioHandler extends BaseAudioHandler with SeekHandler {
  VyroAudioHandler(this._controller) {
    _controller.addListener(_sync);
    _controller.position.addListener(_fillDuration);
    _sync();
  }

  final PlaybackController _controller;
  String? _shownId;

  void _publishItem() {
    final track = _controller.current;
    _shownId = track?.id;
    mediaItem.add(
      track == null
          ? null
          : MediaItem(
              id: track.id,
              title: track.title,
              artist: track.artist,
              duration: _controller.duration ?? track.duration,
            ),
    );
  }

  /// The length of a streamed song is only known once it has loaded.
  void _fillDuration() {
    final item = mediaItem.value;
    final known = _controller.duration;
    if (item != null && item.duration == null && known != null) _publishItem();
  }

  void _sync() {
    final track = _controller.current;
    if (track?.id != _shownId) _publishItem();
    final playing = _controller.isPlaying;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: track == null ? AudioProcessingState.idle : AudioProcessingState.ready,
        playing: playing,
        updatePosition: _controller.position.value,
        speed: 1.0,
        queueIndex: _controller.index < 0 ? null : _controller.index,
      ),
    );
  }

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> stop() async {
    await _controller.pause();
    _sync();
  }

  @override
  Future<void> skipToNext() => _controller.next();

  @override
  Future<void> skipToPrevious() => _controller.previous();

  @override
  Future<void> seek(Duration position) async {
    await _controller.seek(position);
    _sync(); // lets the lock-screen scrubber jump to the new position
  }
}
