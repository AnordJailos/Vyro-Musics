import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../brand/vyro_mark.dart';
import '../theme/vyro_theme.dart';

String _fmt(Duration d) {
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${d.inMinutes}:$seconds';
}

/// Compact player shown above the navigation bar while something is loaded.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller});

  final PlaybackController controller;

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
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => NowPlayingPage(controller: controller),
              ),
            ),
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
                          controller.isTransitioning ? 'Mixing…' : track.artist,
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
                    icon: Icon(controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
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
        );
      },
    );
  }
}

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key, required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Now playing')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final track = controller.current;
          final mixing = controller.mode == PlaybackMode.mixing;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
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
              const SizedBox(height: 24),
              Text(track?.title ?? 'Nothing playing', style: text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(track?.artist ?? '', style: text.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              SizedBox(
                height: 20,
                child: Text(
                  controller.isTransitioning ? 'Mixing into ${controller.mixingInto?.title ?? ''}' : '',
                  style: text.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
                  textAlign: TextAlign.center,
                ),
              ),
              _SeekBar(controller: controller),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Repeat',
                    onPressed: () => controller.setRepeat(
                      RepeatMode.values[(controller.repeat.index + 1) % RepeatMode.values.length],
                    ),
                    icon: Icon(controller.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                        color: controller.repeat == RepeatMode.off ? null : Theme.of(context).colorScheme.primary),
                  ),
                  IconButton(iconSize: 36, tooltip: 'Previous', onPressed: controller.previous, icon: const Icon(Icons.skip_previous_rounded)),
                  IconButton.filled(
                    iconSize: 40,
                    tooltip: controller.isPlaying ? 'Pause' : 'Play',
                    onPressed: controller.togglePlay,
                    icon: Icon(controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                  IconButton(iconSize: 36, tooltip: 'Next', onPressed: controller.next, icon: const Icon(Icons.skip_next_rounded)),
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
