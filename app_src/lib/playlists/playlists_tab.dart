import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import 'add_to_playlist.dart';
import 'playlist_page.dart';
import 'playlists_scope.dart';

String songCount(int n) => n == 1 ? '1 song' : '$n songs';

String lengthText(Duration d) {
  if (d.inMinutes < 1) return d.inSeconds == 0 ? '' : '${d.inSeconds} sec';
  if (d.inHours < 1) return '${d.inMinutes} min';
  return '${d.inHours} h ${d.inMinutes % 60} min';
}

/// The Library tab with the person's playlists.
class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key, required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    final controller = PlaylistsScope.maybeOf(context);
    if (controller == null) return const Center(child: Text('Playlists are not available.'));
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: const Text('New playlist'),
          onTap: () async {
            final name = await promptPlaylistName(context);
            if (name == null || !context.mounted) return;
            final playlist = await controller.create(name);
            if (context.mounted) _open(context, playlist.id);
          },
        ),
        if (controller.playlists.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Make a playlist to gather songs from your files and from Vyro in one place.')),
        for (final p in controller.playlists)
          ListTile(
            leading: PlaylistCover(p),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text([songCount(p.entries.length), lengthText(p.totalDuration)].where((x) => x.isNotEmpty).join(' · ')),
            onTap: () => _open(context, p.id),
          ),
      ],
    );
  }

  void _open(BuildContext context, String id) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlistId: id, playback: playback)));
}
