import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../audio/track.dart';
import '../playlists/add_to_playlist.dart';
import '../playlists/playlists_scope.dart';

/// The small "more" menu on a song row: play it next, or add it to the end of the queue.
class QueueMenuButton extends StatelessWidget {
  const QueueMenuButton({super.key, required this.playback, required this.track, required this.label, this.onNotInterested, this.onHideArtist, this.onDelete});

  final PlaybackController playback;

  /// Builds the playable song when the menu is used (for songs on Vyro this asks for nothing yet).
  final Track Function() track;

  /// The song's title, so the button can be told apart from the others on screen.
  final String label;

  /// On suggestions: leave this song out of future suggestions, or leave out the whole artist.
  final VoidCallback? onNotInterested;
  final VoidCallback? onHideArtist;

  /// Only for songs on the device: delete the file.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More options for $label',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) {
        if (value == 'dismiss') {
          onNotInterested?.call();
          return;
        }
        if (value == 'delete') {
          onDelete?.call();
          return;
        }
        if (value == 'hideArtist') {
          onHideArtist?.call();
          return;
        }
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
        if (onNotInterested != null) const PopupMenuItem(value: 'dismiss', child: Text('Not interested')),
        if (onHideArtist != null) const PopupMenuItem(value: 'hideArtist', child: Text("Don't suggest this artist")),
        if (onDelete != null) const PopupMenuItem(value: 'delete', child: Text('Delete from device')),
      ],
    );
  }
}
