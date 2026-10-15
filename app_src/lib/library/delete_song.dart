import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../playlists/playlists_scope.dart';
import 'library_controller.dart';
import 'library_models.dart';

/// Asks, then deletes a song from the device for good. The song is taken out of the queue (playback moves on first, so
/// nothing keeps the file open) and out of every playlist. If the file cannot be deleted, it stays in the library.
Future<void> confirmAndDeleteSong(BuildContext context, {required LibraryController library, required PlaybackController playback, required LibraryTrack track}) async {
  final messenger = ScaffoldMessenger.of(context);
  final playlists = PlaylistsScope.maybeOf(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Delete this song?'),
      content: Text('"${track.title}" will be deleted from this device for good. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true) return;
  await playback.dropTrack(track.id);
  final deleted = await library.deleteTrack(track);
  if (deleted) await playlists?.removeTrackEverywhere(track.id);
  messenger.showSnackBar(SnackBar(content: Text(deleted ? 'Deleted "${track.title}".' : 'Could not delete "${track.title}". It may be in use or protected.')));
}
