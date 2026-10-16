import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../auth/api_errors.dart';
import '../auth/screens/auth_widgets.dart' show showNotice;
import 'catalog_api.dart';
import 'catalog_models.dart';
import 'catalog_widgets.dart';
import 'genre_page.dart' show titleCase;

/// Opens an artist's page.
void openArtist(BuildContext context, {required String artistId, required CatalogApi catalog, required PlaybackController playback}) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artistId: artistId, catalog: catalog, playback: playback)));
}

String followersText(int n) => n == 1 ? '1 follower' : '$n followers';

/// An artist: popular songs, all their songs, about, and similar artists, with a follow button.
class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.artistId, required this.catalog, required this.playback});

  final String artistId;
  final CatalogApi catalog;
  final PlaybackController playback;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  late Future<ArtistPageData> _page = widget.catalog.artistPage(widget.artistId);
  ArtistPageData? _data;
  bool _busy = false;

  void _reload() => setState(() {
        _data = null;
        _page = widget.catalog.artistPage(widget.artistId);
      });

  Future<void> _toggleFollow(ArtistPageData d) async {
    if (_busy) return;
    final want = !d.following;
    setState(() {
      _busy = true;
      _data = d.withFollowing(want);
    });
    try {
      want ? await widget.catalog.followArtist(d.artist.id) : await widget.catalog.unfollowArtist(d.artist.id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _data = d); // put it back
        showNotice(context, e.status == 401 ? 'Sign in to follow artists.' : 'Could not do that right now.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _play(List<CatalogTrack> list, int i) => widget.playback.setQueue([for (final t in list) t.toPlayable(widget.catalog.streamUri)], startIndex: i, origin: 'search');

  Future<void> _shuffle(List<CatalogTrack> list) async {
    await widget.playback.setShuffle(true);
    await widget.playback.setQueue([for (final t in list) t.toPlayable(widget.catalog.streamUri)], startIndex: DateTime.now().microsecondsSinceEpoch % list.length, origin: 'search');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<ArtistPageData>(
        future: _page,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            final gone = snap.error is ApiException && (snap.error as ApiException).status == 404;
            return Center(child: gone ? const Text('This artist is not available.') : Column(mainAxisSize: MainAxisSize.min, children: [const Text('Could not load this artist.'), TextButton(onPressed: _reload, child: const Text('Try again'))]));
          }
          final d = _data ?? snap.data!;
          final text = Theme.of(context).textTheme;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(child: Text(d.artist.stageName, style: text.headlineSmall)),
                      if (d.artist.verified) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified_rounded, size: 22, semanticLabel: 'Verified')),
                    ]),
                    const SizedBox(height: 4),
                    Text('${followersText(d.artist.followers)} · ${d.monthlyListeners} monthly listeners', style: text.bodySmall),
                    if (d.genres.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, children: [for (final g in d.genres) Chip(label: Text(titleCase(g)), visualDensity: VisualDensity.compact)])),
                    const SizedBox(height: 12),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      FilledButton.icon(onPressed: d.discography.isEmpty ? null : () => _play(d.topTracks.isNotEmpty ? d.topTracks : d.discography, 0), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play')),
                      OutlinedButton.icon(onPressed: d.discography.isEmpty ? null : () => _shuffle(d.discography), icon: const Icon(Icons.shuffle_rounded), label: const Text('Shuffle')),
                      d.following
                          ? FilledButton.tonal(onPressed: _busy ? null : () => _toggleFollow(d), child: const Text('Following'))
                          : OutlinedButton(onPressed: _busy ? null : () => _toggleFollow(d), child: const Text('Follow')),
                    ]),
                  ],
                ),
              ),
              if (d.topTracks.isNotEmpty) ...[
                _Header('Popular'),
                for (var i = 0; i < d.topTracks.length; i++) CatalogTrackTile(track: d.topTracks[i], catalog: widget.catalog, playback: widget.playback, onTap: () => _play(d.topTracks, i)),
              ],
              _Header('Songs'),
              if (d.discography.isEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text('No songs yet.'))
              else
                for (var i = 0; i < d.discography.length; i++) CatalogTrackTile(track: d.discography[i], catalog: widget.catalog, playback: widget.playback, onTap: () => _play(d.discography, i)),
              if (d.bio.isNotEmpty || d.links.isNotEmpty) ...[
                _Header('About'),
                if (d.bio.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(d.bio)),
                for (final l in d.links) Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 0), child: SelectableText(l.label.isEmpty ? l.url : '${l.label}: ${l.url}')),
              ],
              if (d.similar.isNotEmpty) ...[
                _Header('Similar artists'),
                for (final a in d.similar)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                    title: Text(a.stageName),
                    subtitle: Text(followersText(a.followers)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artistId: a.id, catalog: widget.catalog, playback: widget.playback))),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(text, style: Theme.of(context).textTheme.titleMedium));
}
