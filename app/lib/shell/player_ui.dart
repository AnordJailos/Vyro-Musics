import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../brand/vyro_mark.dart';
import '../lyrics/lyrics_provider.dart';
import '../lyrics/lyrics_view.dart';
import '../theme/vyro_theme.dart';
import '../playlists/add_to_playlist.dart';
import '../playlists/playlists_scope.dart';
import 'queue_page.dart';

/// A quick flick sideways skips: left for the next song, right for the previous one.
void _swipeToSkip(PlaybackController controller, DragEndDetails details) {
  final v = details.primaryVelocity ?? 0;
  if (v < -300) {
    controller.next();
  } else if (v > 300) {
    controller.previous();
  }
}

Widget _busyOr(PlaybackController controller, Widget icon, {double size = 24}) =>
    controller.isBuffering ? SizedBox(width: size, height: size, child: const CircularProgressIndicator(strokeWidth: 2.5)) : icon;

String _fmt(Duration d) {
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${d.inMinutes}:$seconds';
}

/// Compact player shown above the navigation bar while something is loaded.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller, this.lyrics});

  final PlaybackController controller;
  final LyricsProvider? lyrics;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final track = controller.current;
        if (track == null) return const SizedBox.shrink();
        final text = Theme.of(context).textTheme;
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (d) => _swipeToSkip(controller, d),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -300) _open(context);
            },
            child: InkWell(
            onTap: () => _open(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                        Text(
                          controller.isRetrying ? 'Reconnecting…' : (controller.isTransitioning ? 'Mixing…' : track.artist),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: controller.isPlaying ? 'Pause' : 'Play',
                    onPressed: controller.togglePlay,
                    icon: _busyOr(controller, Icon(controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: controller.next,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  void _open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => NowPlayingPage(controller: controller, lyrics: lyrics),
        ),
      );
}

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key, required this.controller, this.lyrics});

  final PlaybackController controller;

  /// Where lyrics come from. Without it there is no lyrics button.
  final LyricsProvider? lyrics;

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  bool _showLyrics = false;

  PlaybackController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lyrics = widget.lyrics;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now playing'),
        actions: [
          if (PlaylistsScope.maybeOf(context) != null)
            IconButton(
              tooltip: 'Add to playlist',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () {
                final song = controller.current;
                if (song != null) showAddToPlaylist(context, [song]);
              },
            ),
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => QueuePage(controller: controller))),
          ),
          if (lyrics != null)
            IconButton(
              tooltip: _showLyrics ? 'Hide lyrics' : 'Show lyrics',
              isSelected: _showLyrics,
              icon: const Icon(Icons.lyrics_outlined),
              selectedIcon: const Icon(Icons.lyrics_rounded),
              onPressed: () => setState(() => _showLyrics = !_showLyrics),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final track = controller.current;
          final mixing = controller.mode == PlaybackMode.mixing;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_showLyrics && lyrics != null)
                SizedBox(height: 320, child: LyricsView(controller: controller, provider: lyrics))
              else
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (d) => _swipeToSkip(controller, d),
                  child: Center(
                    child: Container(
                      width: 240,
                      height: 240,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: VyroColors.panel,
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: VyroColors.panelBorder),
                      ),
                      child: const VyroMark(size: 150),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(track?.title ?? 'Nothing playing', style: text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(track?.artist ?? '', style: text.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              SizedBox(
                height: 20,
                child: Text(
                  controller.isRetrying ? 'Reconnecting…' : (controller.isTransitioning ? 'Mixing into ${controller.mixingInto?.title ?? ''}' : ''),
                  style: text.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
                  textAlign: TextAlign.center,
                ),
              ),
              _SeekBar(controller: controller),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Shuffle',
                    onPressed: () => controller.setShuffle(!controller.shuffle),
                    icon: Icon(Icons.shuffle_rounded, color: controller.shuffle ? Theme.of(context).colorScheme.primary : null),
                  ),
                  IconButton(iconSize: 36, tooltip: 'Previous', onPressed: controller.previous, icon: const Icon(Icons.skip_previous_rounded)),
                  IconButton.filled(
                    iconSize: 40,
                    tooltip: controller.isPlaying ? 'Pause' : 'Play',
                    onPressed: controller.togglePlay,
                    icon: _busyOr(controller, Icon(controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded), size: 32),
                  ),
                  IconButton(iconSize: 36, tooltip: 'Next', onPressed: controller.next, icon: const Icon(Icons.skip_next_rounded)),
                  IconButton(
                    tooltip: 'Repeat',
                    onPressed: () => controller.setRepeat(
                      RepeatMode.values[(controller.repeat.index + 1) % RepeatMode.values.length],
                    ),
                    icon: Icon(controller.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                        color: controller.repeat == RepeatMode.off ? null : Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Playback mode', style: text.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<PlaybackMode>(
                segments: const [
                  ButtonSegment(value: PlaybackMode.normal, icon: Icon(Icons.skip_next_rounded), label: Text('Normal')),
                  ButtonSegment(value: PlaybackMode.mixing, icon: Icon(Icons.merge_type_rounded), label: Text('Mixing')),
                ],
                selected: {controller.mode},
                onSelectionChanged: (s) => controller.setMode(s.first),
              ),
              const SizedBox(height: 8),
              Text(
                mixing
                    ? 'Songs blend into each other: at the end of every song, and when you press next or back.'
                    : 'Songs change one after another, with no overlap.',
                style: text.bodySmall,
              ),
              if (mixing) ...[
                const SizedBox(height: 16),
                _SecondsSlider(label: 'Blend at end of song', value: controller.autoSeconds, onChanged: controller.setAutoSeconds),
                _SecondsSlider(label: 'Blend on next / back', value: controller.manualSeconds, onChanged: controller.setManualSeconds),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SecondsSlider extends StatelessWidget {
  const _SecondsSlider({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 4, child: Text(label)),
        Expanded(
          flex: 5,
          child: Slider(
            value: value,
            min: PlaybackController.minSeconds,
            max: PlaybackController.maxSeconds,
            divisions: 11,
            label: '${value.round()} s',
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 36, child: Text('${value.round()} s')),
      ],
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.controller});

  final PlaybackController controller;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.controller.position,
      builder: (context, pos, _) {
        final total = widget.controller.duration;
        final maxMs = (total?.inMilliseconds ?? 0).toDouble();
        final seekable = maxMs > 0;
        final value = seekable ? math.min(_drag ?? pos.inMilliseconds.toDouble(), maxMs) : 0.0;
        return Column(
          children: [
            Slider(
              value: value,
              max: seekable ? maxMs : 1,
              onChanged: seekable ? (v) => setState(() => _drag = v) : null,
              onChangeEnd: (v) {
                widget.controller.seek(Duration(milliseconds: v.round()));
                setState(() => _drag = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(Duration(milliseconds: value.round()))),
                  Text(_fmt(total ?? Duration.zero)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
