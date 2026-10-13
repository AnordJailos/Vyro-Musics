import 'package:flutter/material.dart';

import '../auth/screens/auth_widgets.dart' show showError, showNotice;
import '../catalog/catalog_widgets.dart' show mmss;
import 'file_picker_service.dart';
import 'lyrics_editor_page.dart';
import 'studio_api.dart';
import 'studio_models.dart';

/// The artist's own songs, with their status, and publish, take offline and delete.
class ReleasesPage extends StatefulWidget {
  const ReleasesPage({super.key, required this.studio, this.picker = const NoFilePickerService()});

  final StudioApi studio;
  final FilePickerService picker;

  @override
  State<ReleasesPage> createState() => _ReleasesPageState();
}

class _ReleasesPageState extends State<ReleasesPage> {
  late Future<List<StudioTrack>> _future = widget.studio.myTracks();

  Future<void> _reload() async {
    setState(() { _future = widget.studio.myTracks(); });
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

  Future<void> _editLyrics(StudioTrack t) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => LyricsEditorPage(studio: widget.studio, picker: widget.picker, track: t)));
    if (changed == true && mounted) await _reload();
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

  Future<void> _counterNotice(StudioTrack t) async {
    final notices = await widget.studio.takedowns();
    final open = notices.where((n) => n.trackId == t.id && n.status == 'open').toList();
    if (open.isEmpty) {
      if (mounted) showNotice(context, 'There is nothing to answer for this song right now.');
      return;
    }
    final statement = TextEditingController();
    final signature = TextEditingController();
    var agreed = false;
    if (!mounted) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Send a counter-notice'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${open.first.claimantName} says: "${open.first.statement}"'),
                const SizedBox(height: 12),
                TextField(controller: statement, maxLines: 4, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Why the notice is a mistake (at least 30 characters)')),
                const SizedBox(height: 8),
                TextField(controller: signature, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Your full name, as a signature')),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: agreed,
                  onChanged: (v) => setState(() => agreed = v ?? false),
                  title: const Text('I state in good faith that this song was removed by mistake, and I accept that this may be decided by a court.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: agreed && statement.text.trim().length >= 30 && signature.text.trim().length >= 2 ? () => Navigator.of(d).pop(true) : null, child: const Text('Send')),
          ],
        ),
      ),
    );
    if (send == true) {
      await _act(() => widget.studio.counterNotice(open.first.id, statement: statement.text.trim(), signature: signature.text.trim()));
      if (mounted) showNotice(context, 'Your counter-notice was sent. A reviewer will decide.');
    }
  }

  String _subtitle(StudioTrack t) {
    final parts = <String>[t.statusLabel];
    if (t.status == 'rejected') parts.add('Because ${rejectReasonText(t.rejectReason)}');
    if (t.durationMs > 1000) parts.add(mmss(t.durationMs));
    if (!t.hasAudio) parts.add('no audio yet');
    return parts.join(' · ');
  }

  IconData _icon(StudioTrack t) {
    if (t.isLive) return Icons.public_rounded;
    if (t.isWaiting) return Icons.hourglass_top_rounded;
    if (t.isTakenDown) return Icons.gavel_rounded;
    if (t.status == 'rejected') return Icons.block_rounded;
    return Icons.edit_note_rounded;
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
                  leading: Icon(_icon(t)),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_subtitle(t)),
                  isThreeLine: t.status == 'rejected',
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Options for ${t.title}',
                    onSelected: (v) {
                      if (v == 'publish') _act(() => widget.studio.publish(t.id));
                      if (v == 'unpublish') _act(() => widget.studio.unpublish(t.id));
                      if (v == 'delete') _confirmDelete(t);
                      if (v == 'counter') _counterNotice(t);
                      if (v == 'lyrics') _editLyrics(t);
                    },
                    itemBuilder: (_) => [
                      if (t.canSubmit) PopupMenuItem<String>(value: 'publish', child: Text(t.status == 'rejected' ? 'Fix and submit again' : 'Submit for release')),
                      if (t.isLive || t.isWaiting) PopupMenuItem<String>(value: 'unpublish', child: Text(t.isLive ? 'Take offline' : 'Withdraw from review')),
                      PopupMenuItem<String>(value: 'lyrics', child: Text(t.hasLyrics ? 'Edit lyrics' : 'Add lyrics')),
                      if (t.isTakenDown) const PopupMenuItem<String>(value: 'counter', child: Text('Send a counter-notice')),
                      if (!t.isTakenDown) const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
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
