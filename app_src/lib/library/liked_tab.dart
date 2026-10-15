import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../audio/track.dart';
import '../catalog/catalog_widgets.dart' show SourceBadge;
import '../shell/queue_menu.dart';
import 'likes_scope.dart';

/// Every liked song in one list, from the device and from Vyro, each with its source.
class LikedTab extends StatelessWidget {
  const LikedTab({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final likes = LikesScope.maybeOf(context);
    final songs = likes?.tracks ?? const <Track>[];
    if (songs.isEmpty) return const Center(child: Text('Tap the heart on a song to keep it here.'));
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, i) {
        final t = songs[i];
        return ListTile(
          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Row(children: [
            SourceBadge(t.source == TrackSource.vyro ? 'Vyro' : 'Local'),
            const SizedBox(width: 6),
            Expanded(child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            LikeButton(track: t, label: t.title),
            QueueMenuButton(playback: playback, label: t.title, track: () => t),
          ]),
          onTap: () => playback.setQueue(songs, startIndex: i, origin: 'library'),
        );
      },
    );
  }
}
