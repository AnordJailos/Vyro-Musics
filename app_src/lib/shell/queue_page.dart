import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../audio/track.dart';

/// What is playing, what comes next (drag to reorder, remove, or clear), and what was played before.
class QueuePage extends StatelessWidget {
  const QueuePage({super.key, required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final current = controller.current;
        final first = controller.index + 1;
        final upcoming = current == null ? const <Track>[] : controller.queue.sublist(first);
        final history = controller.history;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Queue'),
            actions: [TextButton(onPressed: upcoming.isEmpty ? null : controller.clearUpcoming, child: const Text('Clear queue'))],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _Header('Now playing'),
              if (current == null)
                const ListTile(title: Text('Nothing is playing.'))
              else
                ListTile(
                  selected: true,
                  leading: Icon(controller.isPlaying ? Icons.equalizer_rounded : Icons.pause_rounded, color: scheme.primary),
                  title: Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(current.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              _Header(controller.shuffle ? 'Next up (shuffled)' : 'Next up'),
              if (upcoming.isEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text('Nothing is queued after this song.'))
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: upcoming.length,
                  onReorder: (from, to) {
                    final target = to > from ? to - 1 : to; // the list reports the place after removal
                    controller.moveInQueue(first + from, first + target);
                  },
                  itemBuilder: (context, i) {
                    final song = controller.queue[first + i];
                    return ListTile(
                      key: ValueKey(controller.queueIds[first + i]),
                      leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => controller.jumpTo(first + i),
                      trailing: IconButton(tooltip: 'Remove ${song.title}', icon: const Icon(Icons.close_rounded), onPressed: () => controller.removeFromQueue(first + i)),
                    );
                  },
                ),
              const _Header('History'),
              if (history.isEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text('Songs you have played will appear here.'))
              else
                for (final song in history.take(30))
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => controller.playNow(song),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(text, style: Theme.of(context).textTheme.titleSmall));
}
