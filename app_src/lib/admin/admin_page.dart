import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../audio/track.dart';
import '../auth/screens/auth_widgets.dart' show showError, showNotice;
import '../catalog/catalog_widgets.dart' show mmss;
import 'admin_api.dart';
import 'admin_models.dart';

/// For moderators and admins: review new songs, decide copyright notices, manage artists.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.admin, required this.playback});

  final AdminApi admin;
  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin console'),
          bottom: const TabBar(tabs: [Tab(text: 'Review'), Tab(text: 'Copyright'), Tab(text: 'Artists')]),
        ),
        body: TabBarView(children: [
          _ReviewTab(admin: admin, playback: playback),
          _TakedownsTab(admin: admin),
          _ArtistsTab(admin: admin),
        ]),
      ),
    );
  }
}

class _Rejection {
  const _Rejection(this.reason, this.note);
  final String reason;
  final String note;
}

Future<_Rejection?> _askRejection(BuildContext context, {required String title}) {
  var reason = '';
  final note = TextEditingController();
  return showDialog<_Rejection>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose a reason. The artist is told.'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in rejectReasons.entries)
                    ChoiceChip(label: Text(e.value), selected: reason == e.key, onSelected: (_) => setState(() => reason = e.key)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(controller: note, maxLength: 500, decoration: const InputDecoration(labelText: 'Note to the artist (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: reason.isEmpty ? null : () => Navigator.of(d).pop(_Rejection(reason, note.text.trim())), child: const Text('Reject')),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------

class _ReviewTab extends StatefulWidget {
  const _ReviewTab({required this.admin, required this.playback});

  final AdminApi admin;
  final PlaybackController playback;

  @override
  State<_ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<_ReviewTab> {
  String _status = 'in_review';
  late Future<List<ReviewItem>> _future = widget.admin.reviewQueue(status: _status);
  final _selected = <String>{};

  Future<void> _reload() async {
    setState(() {
      _selected.clear();
      _future = widget.admin.reviewQueue(status: _status);
    });
    await _future.catchError((_) => <ReviewItem>[]);
  }

  Future<void> _act(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (done != null && mounted) showNotice(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) await _reload();
  }

  void _preview(ReviewItem item) {
    final track = Track(
      id: 'preview:${item.id}',
      title: item.title,
      artist: item.artistName,
      uri: Uri(scheme: 'vyro', path: item.id),
      source: TrackSource.vyro,
      duration: Duration(milliseconds: item.durationMs),
      allowMixing: false,
      countsAsListening: false,
      resolveUri: () => widget.admin.previewUri(item.id),
    );
    widget.playback.setQueue([track]);
  }

  Future<void> _reject(ReviewItem item) async {
    final r = await _askRejection(context, title: 'Reject "${item.title}"');
    if (r != null) await _act(() => widget.admin.reject(item.id, reason: r.reason, note: r.note), done: 'Rejected. The artist was told.');
  }

  Future<void> _bulkReject() async {
    final r = await _askRejection(context, title: 'Reject ${_selected.length} songs');
    if (r != null) await _act(() => widget.admin.bulk(action: 'reject', ids: _selected.toList(), reason: r.reason), done: 'Rejected.');
  }

  List<Widget> _flags(ReviewItem item) {
    final c = item.checks;
    final out = <Widget>[];
    for (final d in c.duplicates) {
      out.add(Chip(
        avatar: Icon(d.sameArtist ? Icons.copy_rounded : Icons.warning_amber_rounded, size: 18),
        label: Text(d.sameArtist
            ? 'Another version by the same artist: "${d.title}"'
            : 'Sounds like "${d.title}" by ${d.artistName} (${(d.similarity * 100).round()}%)'),
      ));
    }
    if (c.externalStatus == 'matches') {
      for (final m in c.externalMatches) {
        out.add(Chip(avatar: const Icon(Icons.warning_amber_rounded, size: 18), label: Text('Matches released music: "${m.title}"${m.artists.isEmpty ? '' : ' by ${m.artists.join(', ')}'}')));
      }
    }
    if (c.externalStatus == 'unchecked') out.add(const Chip(label: Text('Copyright lookup was unavailable')));
    if (!c.fingerprinted) out.add(const Chip(label: Text('Not fingerprinted')));
    if (item.strikes > 0) out.add(Chip(label: Text('${item.strikes} copyright strike${item.strikes == 1 ? '' : 's'}')));
    if (item.artistVerified) out.add(const Chip(label: Text('Verified artist')));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              ChoiceChip(label: const Text('In review'), selected: _status == 'in_review', onSelected: (_) => setState(() { _status = 'in_review'; _reload(); })),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('On hold'), selected: _status == 'held', onSelected: (_) => setState(() { _status = 'held'; _reload(); })),
            ],
          ),
        ),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text('${_selected.length} selected', style: text.titleSmall),
                const Spacer(),
                TextButton(onPressed: () => _act(() => widget.admin.bulk(action: 'approve', ids: _selected.toList()), done: 'Approved.'), child: const Text('Approve selected')),
                TextButton(onPressed: _bulkReject, child: const Text('Reject selected')),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: FutureBuilder<List<ReviewItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('Could not load the queue. Pull down to try again.'))]);
                final items = snap.data ?? const <ReviewItem>[];
                if (items.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('Nothing is waiting here.'))]);
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final item in items)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: _selected.contains(item.id),
                                    onChanged: (v) => setState(() => v == true ? _selected.add(item.id) : _selected.remove(item.id)),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item.title, style: text.titleMedium),
                                        Text('${item.artistName} · ${item.publishedCount} live', style: text.bodySmall),
                                      ],
                                    ),
                                  ),
                                  IconButton(tooltip: 'Listen to ${item.title}', icon: const Icon(Icons.play_circle_outline_rounded), onPressed: () => _preview(item)),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 12, top: 4),
                                child: Text(
                                  [
                                    mmss(item.durationMs),
                                    item.lossless ? '${item.codec ?? 'lossless'} lossless' : '${item.codec ?? 'audio'}${item.bitrateKbps != null ? ' ${item.bitrateKbps} kbps' : ''}',
                                    if (item.loudnessLufs != null) '${item.loudnessLufs} LUFS',
                                    item.genre,
                                    if (item.explicit) 'explicit',
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: text.bodySmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 4, children: _flags(item)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton(onPressed: () => _reject(item), child: Text('Reject ${item.title}')),
                                  const SizedBox(width: 8),
                                  FilledButton(onPressed: () => _act(() => widget.admin.approve(item.id), done: 'Approved. The artist was told.'), child: Text('Approve ${item.title}')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _TakedownsTab extends StatefulWidget {
  const _TakedownsTab({required this.admin});

  final AdminApi admin;

  @override
  State<_TakedownsTab> createState() => _TakedownsTabState();
}

class _TakedownsTabState extends State<_TakedownsTab> {
  late Future<List<TakedownNotice>> _future = widget.admin.takedowns();

  Future<void> _reload() async {
    setState(() => _future = widget.admin.takedowns());
    await _future.catchError((_) => <TakedownNotice>[]);
  }

  Future<void> _resolve(TakedownNotice n, String decision) async {
    final uphold = decision == 'uphold';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(uphold ? 'Uphold this notice?' : 'Restore this song?'),
        content: Text(uphold
            ? '"${n.trackTitle}" stays removed and ${n.artistName} gets a strike (${n.strikes + 1} of 3). Three strikes suspend the account.'
            : '"${n.trackTitle}" goes back to where it was before the notice.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(uphold ? 'Uphold' : 'Restore')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.admin.resolveTakedown(n.id, decision: decision);
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<TakedownNotice>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('Could not load notices. Pull down to try again.'))]);
          final notices = snap.data ?? const <TakedownNotice>[];
          if (notices.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('No copyright notices are waiting.'))]);
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final n in notices)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('"${n.trackTitle}" by ${n.artistName}', style: text.titleMedium),
                        Text(n.status == 'counter_filed' ? 'The artist sent a counter-notice' : 'Waiting for the artist to respond', style: text.labelMedium),
                        const SizedBox(height: 8),
                        Text('From ${n.claimantName}${n.claimantCompany != null ? ' (${n.claimantCompany})' : ''}, ${n.claimantEmail}', style: text.bodySmall),
                        const SizedBox(height: 4),
                        Text(n.statement),
                        if (n.counterStatement != null) ...[
                          const SizedBox(height: 8),
                          Text('Artist\'s answer', style: text.labelLarge),
                          Text(n.counterStatement!),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(onPressed: () => _resolve(n, 'restore'), child: Text('Restore ${n.trackTitle}')),
                            const SizedBox(width: 8),
                            FilledButton(onPressed: () => _resolve(n, 'uphold'), child: const Text('Uphold notice')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ArtistsTab extends StatefulWidget {
  const _ArtistsTab({required this.admin});

  final AdminApi admin;

  @override
  State<_ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends State<_ArtistsTab> {
  Timer? _debounce;
  String _query = '';
  late Future<List<AdminArtist>> _future = widget.admin.artists('');

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _query = text.trim();
        _future = widget.admin.artists(_query);
      });
    });
  }

  Future<void> _reload() async {
    setState(() => _future = widget.admin.artists(_query));
    await _future.catchError((_) => <AdminArtist>[]);
  }

  Future<void> _do(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) await _reload();
  }

  Future<void> _suspend(AdminArtist a) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Suspend ${a.stageName}?'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (the artist is told)')),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Suspend')),
        ],
      ),
    );
    if (ok == true && reason.text.trim().length >= 3) await _do(() => widget.admin.suspend(a.id, reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(onChanged: _search, decoration: const InputDecoration(hintText: 'Search artists by name or username', prefixIcon: Icon(Icons.search_rounded), isDense: true)),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: FutureBuilder<List<AdminArtist>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('Could not load artists. Pull down to try again.'))]);
                final artists = snap.data ?? const <AdminArtist>[];
                if (artists.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('No artists match.'))]);
                return ListView(
                  children: [
                    for (final a in artists)
                      ListTile(
                        leading: Icon(a.suspended ? Icons.block_rounded : (a.verified ? Icons.verified_rounded : Icons.person_outline_rounded)),
                        title: Text(a.stageName),
                        subtitle: Text('@${a.username} · ${a.trackCount} songs · ${a.strikes} strikes${a.suspended ? ' · Suspended: ${a.suspensionReason ?? ''}' : ''}'),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Options for ${a.stageName}',
                          onSelected: (v) {
                            if (v == 'verify') _do(() => widget.admin.verifyArtist(a.id, !a.verified));
                            if (v == 'suspend') _suspend(a);
                            if (v == 'unsuspend') _do(() => widget.admin.unsuspend(a.id));
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem<String>(value: 'verify', child: Text(a.verified ? 'Remove verified badge' : 'Mark as verified')),
                            if (!a.suspended) const PopupMenuItem<String>(value: 'suspend', child: Text('Suspend')),
                            if (a.suspended) const PopupMenuItem<String>(value: 'unsuspend', child: Text('Restore account')),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
