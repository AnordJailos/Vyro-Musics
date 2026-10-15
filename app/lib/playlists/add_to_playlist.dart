import 'dart:io';

import 'package:flutter/material.dart';

import '../audio/track.dart';
import 'playlist_models.dart';
import 'playlists_controller.dart';
import 'playlists_scope.dart';

/// Asks for a playlist name. Null when cancelled.
Future<String?> promptPlaylistName(BuildContext context, {String title = 'New playlist', String initial = '', String action = 'Create'}) {
  return showDialog<String>(context: context, builder: (_) => _NameDialog(title: title, initial: initial, action: action));
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial, required this.action});

  final String title;
  final String initial;
  final String action;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _text.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(controller: _text, autofocus: true, maxLength: maxPlaylistName, decoration: const InputDecoration(labelText: 'Name'), onChanged: (_) => setState(() {}), onSubmitted: (_) => ok ? Navigator.of(context).pop(_text.text.trim()) : null),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: ok ? () => Navigator.of(context).pop(_text.text.trim()) : null, child: Text(widget.action)),
      ],
    );
  }
}

/// A picture for a playlist: the chosen cover, or a plain placeholder.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover(this.playlist, {super.key, this.size = 48});

  final Playlist playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(size / 8)),
      child: Icon(Icons.queue_music_rounded, size: size / 2),
    );
    final path = playlist.coverPath;
    if (path == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 8),
      child: Image.file(File(path), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
    );
  }
}

/// Lets the person pick a playlist (or make a new one) for the given songs.
Future<void> showAddToPlaylist(BuildContext context, List<Track> tracks) async {
  final controller = PlaylistsScope.maybeOf(context);
  if (controller == null || tracks.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  const newPlaylist = '\u0000new';
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheet) => ListenableBuilder(
      listenable: controller,
      builder: (_, __) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('Add to playlist', style: TextStyle(fontWeight: FontWeight.w600))),
          ListTile(leading: const Icon(Icons.add_rounded), title: const Text('New playlist'), onTap: () => Navigator.of(sheet).pop(newPlaylist)),
          for (final p in controller.playlists)
            ListTile(
              leading: PlaylistCover(p),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(p.entries.length == 1 ? '1 song' : '${p.entries.length} songs'),
              trailing: tracks.length == 1 && p.contains(tracks.first.id) ? const Icon(Icons.check_circle_rounded) : null,
              onTap: () => Navigator.of(sheet).pop(p.id),
            ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  late final Playlist target;
  if (choice == newPlaylist) {
    final name = await promptPlaylistName(context);
    if (name == null) return;
    target = await controller.create(name);
  } else {
    target = controller.byId(choice)!;
  }
  final result = await controller.addTracks(target.id, tracks);
  final many = tracks.length > 1;
  if (result.added == 0 && result.duplicates > 0) {
    messenger.showSnackBar(SnackBar(
      content: Text('Already in "${target.name}"'),
      action: SnackBarAction(label: 'Add anyway', onPressed: () => controller.addTracks(target.id, tracks, allowDuplicates: true)),
    ));
    return;
  }
  final what = many ? '${result.added} songs' : 'Song';
  final extra = result.duplicates > 0 ? ' (${result.duplicates} already there)' : '';
  messenger.showSnackBar(SnackBar(content: Text('${many ? 'Added $what' : 'Added'} to "${target.name}"$extra')));
}
