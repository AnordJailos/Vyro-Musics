import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../auth/screens/auth_widgets.dart' show showError, showNotice;
import '../audio/track.dart';
import '../catalog/catalog_widgets.dart' show SourceBadge;
import '../studio/file_picker_service.dart';
import 'add_to_playlist.dart';
import 'playlist_models.dart';
import 'playlists_controller.dart';
import 'playlists_scope.dart';
import 'playlists_tab.dart' show lengthText, songCount;

String _mmss(Duration? d) {
  if (d == null) return '';
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// One playlist: play it, shuffle it, change the order, sort it, select songs, take out duplicates, edit its details.
class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key, required this.playlistId, required this.playback});

  final String playlistId;
  final PlaybackController playback;

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  bool _selecting = false;
  final Set<String> _selected = {};

  PlaylistsController get _c => PlaylistsScope.of(context);

  void _toggle(String entryId) => setState(() {
        if (!_selected.remove(entryId)) _selected.add(entryId);
        if (_selected.isEmpty) _selecting = false;
      });

  void _stopSelecting() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  Future<void> _play(Playlist p, int index) => widget.playback.setQueue(p.tracks, startIndex: index, origin: 'playlist');

  Future<void> _shufflePlay(Playlist p) async {
    await widget.playback.setShuffle(true);
    await widget.playback.setQueue(p.tracks, startIndex: DateTime.now().microsecondsSinceEpoch % p.entries.length, origin: 'playlist');
  }

  Future<void> _guard(Future<void> Function() job) async {
    try {
      await job();
    } on FormatException catch (e) {
      if (mounted) showNotice(context, e.message);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _removeSelected(Playlist p) async {
    final ids = Set<String>.of(_selected);
    _stopSelecting();
    await _c.removeEntries(p.id, ids);
  }

  Future<void> _addSelectedToQueue(Playlist p) async {
    final chosen = [for (final e in p.entries) if (_selected.contains(e.id)) e.track];
    _stopSelecting();
    for (final t in chosen) {
      await widget.playback.addToQueue(t);
    }
    if (mounted) showNotice(context, 'Added to queue');
  }

  Future<void> _edit(Playlist p) async {
    final result = await showDialog<(String, String)>(context: context, builder: (_) => _EditDialog(playlistId: p.id, controller: _c, picker: PlaylistsScope.pickerOf(context)));
    if (result == null) return;
    await _guard(() => _c.update(p.id, name: result.$1, description: result.$2));
  }

  Future<void> _delete(Playlist p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete this playlist?'),
        content: Text('"${p.name}" will be deleted. The songs themselves are not touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await _c.delete(p.id);
    navigator.pop();
  }

  Future<void> _removeDuplicates(Playlist p) async {
    final n = await _c.removeDuplicates(p.id);
    if (mounted) showNotice(context, n == 0 ? 'There are no duplicates.' : (n == 1 ? 'Removed 1 duplicate.' : 'Removed $n duplicates.'));
  }

  void _menu(Playlist p, String value) {
    switch (value) {
      case 'edit':
        _edit(p);
      case 'dups':
        _removeDuplicates(p);
      case 'delete':
        _delete(p);
      default:
        final key = PlaylistSort.values.firstWhere((s) => 'sort:${s.name}' == value);
        _c.sortBy(p.id, key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _c;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final p = controller.byId(widget.playlistId);
        if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This playlist no longer exists.')));
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: _selecting
              ? AppBar(
                  leading: IconButton(tooltip: 'Cancel selection', icon: const Icon(Icons.close_rounded), onPressed: _stopSelecting),
                  title: Text('${_selected.length} selected'),
                  actions: [
                    IconButton(tooltip: 'Select all', icon: const Icon(Icons.select_all_rounded), onPressed: () => setState(() => _selected.addAll(p.entries.map((e) => e.id)))),
                    IconButton(tooltip: 'Add selected to queue', icon: const Icon(Icons.queue_rounded), onPressed: () => _addSelectedToQueue(p)),
                    IconButton(
                      tooltip: 'Add selected to a playlist',
                      icon: const Icon(Icons.playlist_add_rounded),
                      onPressed: () => showAddToPlaylist(context, [for (final e in p.entries) if (_selected.contains(e.id)) e.track]),
                    ),
                    IconButton(tooltip: 'Remove selected', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _removeSelected(p)),
                  ],
                )
              : AppBar(
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  actions: [
                    IconButton(tooltip: 'Select songs', icon: const Icon(Icons.checklist_rounded), onPressed: p.entries.isEmpty ? null : () => setState(() => _selecting = true)),
                    PopupMenuButton<String>(
                      tooltip: 'Playlist options',
                      onSelected: (v) => _menu(p, v),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit details')),
                        PopupMenuItem(value: 'sort:title', child: Text('Sort by title')),
                        PopupMenuItem(value: 'sort:artist', child: Text('Sort by artist')),
                        PopupMenuItem(value: 'sort:dateAdded', child: Text('Sort by date added')),
                        PopupMenuItem(value: 'sort:duration', child: Text('Sort by length')),
                        PopupMenuItem(value: 'dups', child: Text('Remove duplicates')),
                        PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                      ],
                    ),
                  ],
                ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PlaylistCover(p, size: 112),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: text.titleLarge),
                          if (p.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(p.description)),
                          Padding(padding: const EdgeInsets.only(top: 8), child: Text([songCount(p.entries.length), lengthText(p.totalDuration)].where((x) => x.isNotEmpty).join(' · '), style: text.bodySmall)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FilledButton.icon(onPressed: p.entries.isEmpty ? null : () => _play(p, 0), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play')),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(onPressed: p.entries.isEmpty ? null : () => _shufflePlay(p), icon: const Icon(Icons.shuffle_rounded), label: const Text('Shuffle')),
                  ],
                ),
              ),
              if (p.entries.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('No songs yet. Use the menu on any song and choose "Add to playlist".'))
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: p.entries.length,
                  onReorder: (from, to) {
                    if (_selecting) return;
                    _c.moveEntry(p.id, from, to > from ? to - 1 : to); // the list reports the place after removal
                  },
                  itemBuilder: (context, i) {
                    final e = p.entries[i];
                    final picked = _selected.contains(e.id);
                    return ListTile(
                      key: ValueKey(e.id),
                      selected: picked,
                      leading: _selecting
                          ? Checkbox(value: picked, onChanged: (_) => _toggle(e.id))
                          : ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                      title: Text(e.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Row(children: [
                        SourceBadge(e.track.source == TrackSource.vyro ? 'Vyro' : 'Local'),
                        const SizedBox(width: 6),
                        Expanded(child: Text(e.track.artist, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      trailing: _selecting
                          ? Text(_mmss(e.track.duration))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(_mmss(e.track.duration)),
                              PopupMenuButton<String>(
                                tooltip: 'Options for ${e.track.title}',
                                onSelected: (v) {
                                  if (v == 'next') {
                                    widget.playback.playNext(e.track);
                                  } else if (v == 'queue') {
                                    widget.playback.addToQueue(e.track);
                                  } else {
                                    _c.removeEntries(p.id, {e.id});
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'next', child: Text('Play next')),
                                  PopupMenuItem(value: 'queue', child: Text('Add to queue')),
                                  PopupMenuItem(value: 'remove', child: Text('Remove from playlist')),
                                ],
                              ),
                            ]),
                      onTap: () => _selecting ? _toggle(e.id) : _play(p, i),
                      onLongPress: _selecting
                          ? null
                          : () => setState(() {
                                _selecting = true;
                                _selected.add(e.id);
                              }),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.playlistId, required this.controller, required this.picker});

  final String playlistId;
  final PlaylistsController controller;
  final FilePickerService picker;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.controller.byId(widget.playlistId)!.name);
  late final TextEditingController _description = TextEditingController(text: widget.controller.byId(widget.playlistId)!.description);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _chooseCover() async {
    try {
      final file = await widget.picker.pickImage();
      if (file == null) return;
      await widget.controller.setCover(widget.playlistId, file);
    } on FormatException catch (e) {
      if (mounted) showNotice(context, e.message);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final p = widget.controller.byId(widget.playlistId);
        return AlertDialog(
          title: const Text('Edit playlist'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p != null) PlaylistCover(p, size: 96),
                Wrap(spacing: 8, children: [
                  TextButton(onPressed: _chooseCover, child: const Text('Choose cover picture')),
                  if (p?.coverPath != null) TextButton(onPressed: () => widget.controller.removeCover(widget.playlistId), child: const Text('Remove cover')),
                ]),
                TextField(controller: _name, maxLength: maxPlaylistName, decoration: const InputDecoration(labelText: 'Name'), onChanged: (_) => setState(() {})),
                TextField(controller: _description, maxLength: maxPlaylistDescription, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: _name.text.trim().isEmpty ? null : () => Navigator.of(context).pop((_name.text.trim(), _description.text.trim())), child: const Text('Save')),
          ],
        );
      },
    );
  }
}
