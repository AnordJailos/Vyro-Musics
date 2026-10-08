import 'package:flutter/material.dart';

import '../auth/screens/auth_widgets.dart' show showError;
import '../catalog/catalog_widgets.dart' show mmss;
import 'studio_api.dart';
import 'studio_models.dart';

/// The artist's own songs, with their status, and publish, take offline and delete.
class ReleasesPage extends StatefulWidget {
  const ReleasesPage({super.key, required this.studio});

  final StudioApi studio;

  @override
  State<ReleasesPage> createState() => _ReleasesPageState();
}

class _ReleasesPageState extends State<ReleasesPage> {
  late Future<List<StudioTrack>> _future = widget.studio.myTracks();

  Future<void> _reload() async {
    setState(() => _future = widget.studio.myTracks());
    await _future.catchError((_) => <StudioTrack>[]);
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) await _reload();
  }

  Future<void> _confirmDelete(StudioTrack t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete "${t.title}"?'),
        content: const Text('The song and its files are removed. Past plays still count in your statistics.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _act(() => widget.studio.deleteTrack(t.id));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<StudioTrack>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text('Could not load your songs. Pull down to try again.', style: text.bodyMedium))]);
          }
          final tracks = snap.data ?? const <StudioTrack>[];
          if (tracks.isEmpty) {
            return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text('No songs yet. Upload your first one in the Studio tab.', style: text.bodyMedium))]);
          }
          return ListView(
            children: [
              for (final t in tracks)
                ListTile(
                  leading: Icon(t.isLive ? Icons.public_rounded : Icons.edit_note_rounded),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${t.statusLabel}${t.durationMs > 1000 ? ' · ${mmss(t.durationMs)}' : ''}${t.hasAudio ? '' : ' · no audio yet'}'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Options for ${t.title}',
                    onSelected: (v) {
                      if (v == 'publish') _act(() => widget.studio.publish(t.id));
                      if (v == 'unpublish') _act(() => widget.studio.unpublish(t.id));
                      if (v == 'delete') _confirmDelete(t);
                    },
                    itemBuilder: (_) => [
                      if (!t.isLive && t.hasAudio) const PopupMenuItem<String>(value: 'publish', child: Text('Publish')),
                      if (t.isLive) const PopupMenuItem<String>(value: 'unpublish', child: Text('Take offline')),
                      const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
