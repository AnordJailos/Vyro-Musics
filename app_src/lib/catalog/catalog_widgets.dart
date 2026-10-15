import '../library/likes_scope.dart';
import '../audio/playback_controller.dart';
import '../shell/queue_menu.dart';
import 'package:flutter/material.dart';

import 'catalog_api.dart';
import 'catalog_models.dart';

/// Tells where a song comes from, so people know what can be blended and downloaded.
class SourceBadge extends StatelessWidget {
  const SourceBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

String mmss(int ms) {
  if (ms <= 0) return '';
  final d = Duration(milliseconds: ms);
  return '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

class CatalogTrackTile extends StatelessWidget {
  const CatalogTrackTile({super.key, required this.track, required this.catalog, required this.onTap, this.playback, this.onNotInterested, this.onHideArtist});

  final CatalogTrack track;
  final CatalogApi catalog;
  final VoidCallback onTap;

  /// When given, the row has a menu to play the song next or add it to the queue.
  final PlaybackController? playback;

  /// Only on suggestions: "Not interested" in this song, or in this artist.
  final VoidCallback? onNotInterested;
  final VoidCallback? onHideArtist;

  @override
  Widget build(BuildContext context) {
    final cover = track.coverPath;
    return ListTile(
      leading: SizedBox(
        width: 44,
        height: 44,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: cover == null
              ? const ColoredBox(color: Color(0x22888888), child: Icon(Icons.music_note_rounded))
              : Image.network(
                  catalog.coverUri(cover).toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x22888888), child: Icon(Icons.music_note_rounded)),
                ),
        ),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${track.explicit ? 'E · ' : ''}${track.artistName}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SourceBadge('Vyro'),
          const SizedBox(width: 8),
          Text(mmss(track.durationMs), style: Theme.of(context).textTheme.bodySmall),
          LikeButton(track: track.toPlayable(catalog.streamUri), label: track.title),
          if (playback != null) QueueMenuButton(playback: playback!, label: track.title, track: () => track.toPlayable(catalog.streamUri), onNotInterested: onNotInterested, onHideArtist: onHideArtist),
        ],
      ),
      onTap: onTap,
    );
  }
}
