import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/audio_handler.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/track.dart';

import 'fakes.dart';

Track _t(String id) => Track(id: id, title: 'Song $id', artist: 'Artist', uri: Uri.parse('https://example.com/$id.mp3'), duration: const Duration(minutes: 3));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tells the system what is playing and forwards the system buttons to the player', () async {
    final controller = PlaybackController(deckA: FakeDeck(), deckB: FakeDeck());
    final handler = VyroAudioHandler(controller);
    expect(handler.mediaItem.value, isNull);

    await controller.setQueue([_t('a'), _t('b')]);
    expect(handler.mediaItem.value?.id, 'a');
    expect(handler.mediaItem.value?.title, 'Song a');
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.controls, contains(MediaControl.pause));

    await handler.skipToNext();
    expect(handler.mediaItem.value?.id, 'b');

    await handler.pause();
    expect(handler.playbackState.value.playing, isFalse);
    expect(handler.playbackState.value.controls, contains(MediaControl.play));

    await handler.play();
    expect(handler.playbackState.value.playing, isTrue);

    await handler.skipToPrevious();
    expect(handler.mediaItem.value?.id, 'a');
  });

  test('shows the new song when a blend passes its midpoint', () async {
    final a = FakeDeck();
    final b = FakeDeck();
    final controller = PlaybackController(deckA: a, deckB: b, tickInterval: const Duration(milliseconds: 5))..setMode(PlaybackMode.mixing);
    controller.setManualSeconds(1);
    final handler = VyroAudioHandler(controller);
    await controller.setQueue([_t('a'), _t('b')]);
    await controller.next();
    expect(controller.isTransitioning, isTrue);
    for (var i = 0; i < 100 && controller.isTransitioning; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50)); // wait for the blend to finish
    }
    expect(controller.isTransitioning, isFalse);
    expect(handler.mediaItem.value?.id, 'b');
  });
}
