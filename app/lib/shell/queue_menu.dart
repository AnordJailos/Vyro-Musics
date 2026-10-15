import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../audio/track.dart';
import '../playlists/add_to_playlist.dart';
import '../playlists/playlists_scope.dart';

/// The small "more" menu on a song row: play it next, or add it to the end of the queue.
class QueueMenuButton extends StatelessWidget {
  const QueueMenuButton({super.key, required this.playback, required this.track, required this.label});

  final PlaybackController playback;

  /// Builds the playable song when the menu is used (for songs on Vyro this asks for nothing yet).
  final Track Function() track;

  /// The song's title, so the button can be told apart from the others on screen.
  final String label;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More options for $label',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) {
        final song = track();
        if (value == 'playlist') {
          showAddToPlaylist(context, [song]);
          return;
        }
        if (value == 'next') {
          playback.playNext(song);
        } else {
          playback.addToQueue(song);
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 2), content: Text(value == 'next' ? 'Playing next' : 'Added to queue')));
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'next', child: Text('Play next')),
        const PopupMenuItem(value: 'add', child: Text('Add to queue')),
        if (PlaylistsScope.maybeOf(context) != null) const PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
      ],
    );
  }
}
