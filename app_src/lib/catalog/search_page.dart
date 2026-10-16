import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../library/library_controller.dart';
import '../library/library_index.dart';
import '../library/library_models.dart';
import 'artist_page.dart';
import 'catalog_api.dart';
import 'catalog_models.dart';
import 'catalog_widgets.dart';
import 'charts_page.dart';
import 'genre_page.dart';
import 'recent_searches.dart';

/// One search across the Vyro catalog and the music on this device, with each result labelled by where it lives.
/// With nothing typed, it shows recent searches, genres to browse, and the charts.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.catalog, required this.library, required this.playback, this.country});

  final CatalogApi catalog;
  final LibraryController library;
  final PlaybackController playback;

  /// The person's country, for the charts.
  final String? country;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _field = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<SearchResults>? _vyro;
  Future<List<Suggestion>>? _suggest;
  late final Future<List<GenreCount>> _genres = widget.catalog.genres().catchError((_) => <GenreCount>[]);

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(text));
  }

  void _run(String text) {
    if (!mounted) return;
    final q = text.trim();
    setState(() {
      _query = q;
      _vyro = q.isEmpty ? null : widget.catalog.searchAll(q);
      // Short input has too little to search with, so suggest instead of guessing.
      _suggest = (q.isNotEmpty && q.length <= 2) ? widget.catalog.suggest(q).catchError((_) => <Suggestion>[]) : null;
    });
  }

  void _remember() => RecentSearchesScope.maybeOf(context)?.add(_query);

  void _use(String text) {
    _field.text = text;
    _field.selection = TextSelection.collapsed(offset: text.length);
    _run(text);
  }

  void _playVyro(List<CatalogTrack> list, int i) {
    _remember();
    widget.playback.setQueue([for (final t in list) t.toPlayable(widget.catalog.streamUri)], startIndex: i, origin: 'search');
  }

  void _playLocal(List<LibraryTrack> list, int i) {
    _remember();
    widget.playback.setQueue([for (final t in list) t.toPlayable()], startIndex: i, origin: 'search');
  }

  void _openArtist(String id) {
    _remember();
    openArtist(context, artistId: id, catalog: widget.catalog, playback: widget.playback);
  }

  Widget _browse(TextTheme text) {
    final recents = RecentSearchesScope.maybeOf(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Search Vyro and your own music in one place.', style: text.bodyMedium),
        if (recents != null && recents.items.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Recent searches', style: text.titleMedium)),
            TextButton(onPressed: recents.clear, child: const Text('Clear')),
          ]),
          for (final r in recents.items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded),
              title: Text(r),
              trailing: IconButton(tooltip: 'Remove $r', icon: const Icon(Icons.close_rounded), onPressed: () => recents.remove(r)),
              onTap: () => _use(r),
            ),
        ],
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.leaderboard_rounded),
          title: const Text('Charts'),
          subtitle: const Text('Top songs, top artists and rising artists'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChartsPage(catalog: widget.catalog, playback: widget.playback, country: widget.country))),
        ),
        FutureBuilder<List<GenreCount>>(
          future: _genres,
          builder: (context, snap) {
            final genres = snap.data ?? const <GenreCount>[];
            if (genres.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 16),
              Text('Browse by genre', style: text.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final g in genres)
                  ActionChip(
                    label: Text('${titleCase(g.genre)} (${g.count})'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GenrePage(genre: g.genre, catalog: widget.catalog, playback: widget.playback))),
                  ),
              ]),
            ]);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final local = _query.isEmpty ? const <LibraryTrack>[] : sortedSongs(searchTracks(widget.library.allTracks, _query)).take(20).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _field,
            onChanged: _changed,
            onSubmitted: (v) {
              _debounce?.cancel();
              _run(v);
              _remember();
            },
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Songs and artists, on Vyro and on this device', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
        ),
        Expanded(
          child: _query.isEmpty
              ? _browse(text)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_suggest != null)
                      FutureBuilder<List<Suggestion>>(
                        future: _suggest,
                        builder: (context, snap) {
                          final list = snap.data ?? const <Suggestion>[];
                          if (list.isEmpty) return const SizedBox.shrink();
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Suggestions', style: text.titleMedium),
                            for (final s in list)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(s.isArtist ? Icons.person_rounded : Icons.music_note_rounded),
                                title: Text(s.text),
                                subtitle: Text(s.subtitle),
                                onTap: () => s.isArtist ? _openArtist(s.id) : _use(s.text),
                              ),
                            const SizedBox(height: 8),
                          ]);
                        },
                      ),
                    Text('On Vyro', style: text.titleMedium),
                    FutureBuilder<SearchResults>(
                      future: _vyro,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                        }
                        if (snap.hasError) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Could not search Vyro right now.', style: text.bodySmall));
                        final found = snap.data ?? const SearchResults();
                        if (found.tracks.isEmpty && found.artists.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Nothing on Vyro matches.', style: text.bodySmall));
                        final list = found.tracks;
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final a in found.artists)
                            ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                              title: Row(children: [Flexible(child: Text(a.stageName, maxLines: 1, overflow: TextOverflow.ellipsis)), if (a.verified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, size: 16))]),
                              subtitle: Text('Artist · ${followersText(a.followers)}'),
                              onTap: () => _openArtist(a.id),
                            ),
                          for (var i = 0; i < list.length; i++)
                            CatalogTrackTile(
                              track: list[i],
                              catalog: widget.catalog,
                              playback: widget.playback,
                              onArtistTap: () => _openArtist(list[i].artistId),
                              onTap: () => _playVyro(list, i),
                            ),
                        ]);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('On this device', style: text.titleMedium),
                    if (local.isEmpty)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Nothing on this device matches.', style: text.bodySmall))
                    else
                      for (var i = 0; i < local.length; i++)
                        ListTile(
                          leading: const Icon(Icons.music_note_rounded),
                          title: Text(local[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(local[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: const SourceBadge('On device'),
                          onTap: () => _playLocal(local, i),
                        ),
                  ],
                ),
        ),
      ],
    );
  }
}
