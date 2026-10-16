import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import 'catalog_api.dart';
import 'artist_page.dart' show openArtist;
import 'catalog_models.dart';
import 'catalog_widgets.dart';

String titleCase(String text) => text.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

/// The songs of one genre, newest or most played.
class GenrePage extends StatefulWidget {
  const GenrePage({super.key, required this.genre, required this.catalog, required this.playback});

  final String genre;
  final CatalogApi catalog;
  final PlaybackController playback;

  @override
  State<GenrePage> createState() => _GenrePageState();
}

class _GenrePageState extends State<GenrePage> {
  String _sort = 'new';
  late Future<List<CatalogTrack>> _songs = widget.catalog.genreTracks(widget.genre, sort: _sort);

  void _choose(String sort) => setState(() {
        _sort = sort;
        _songs = widget.catalog.genreTracks(widget.genre, sort: sort);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titleCase(widget.genre))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'new', label: Text('Newest')), ButtonSegment(value: 'popular', label: Text('Most played'))],
              selected: {_sort},
              onSelectionChanged: (s) => _choose(s.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CatalogTrack>>(
              future: _songs,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) return Center(child: TextButton(onPressed: () => _choose(_sort), child: const Text('Could not load. Try again')));
                final list = snap.data ?? const <CatalogTrack>[];
                if (list.isEmpty) return const Center(child: Text('No songs in this genre yet.'));
                return ListView(children: [
                  for (var i = 0; i < list.length; i++)
                    CatalogTrackTile(
                      track: list[i],
                      catalog: widget.catalog,
                      playback: widget.playback,
                      onArtistTap: () => openArtist(context, artistId: list[i].artistId, catalog: widget.catalog, playback: widget.playback),
                      onTap: () => widget.playback.setQueue([for (final t in list) t.toPlayable(widget.catalog.streamUri)], startIndex: i, origin: 'search'),
                    ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
