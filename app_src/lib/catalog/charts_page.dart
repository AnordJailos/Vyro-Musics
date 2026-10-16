import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import 'artist_page.dart';
import 'catalog_api.dart';
import 'catalog_models.dart';
import 'catalog_widgets.dart';

/// The most played songs and artists, and the artists on the rise, worldwide or in the person's own country.
class ChartsPage extends StatefulWidget {
  const ChartsPage({super.key, required this.catalog, required this.playback, this.country});

  final CatalogApi catalog;
  final PlaybackController playback;

  /// The person's country (two letters), when known.
  final String? country;

  @override
  State<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<ChartsPage> {
  bool _mine = false;
  late Future<List<CatalogTrack>> _songs;
  late Future<List<ArtistChartEntry>> _top;
  late Future<List<ArtistChartEntry>> _rising;

  String? get _country => _mine ? widget.country : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _songs = widget.catalog.charts(country: _country);
    _top = widget.catalog.artistChart(kind: 'top', country: _country);
    _rising = widget.catalog.artistChart(kind: 'rising', country: _country);
  }

  void _scope(bool mine) => setState(() {
        _mine = mine;
        _load();
      });

  Widget _artists(Future<List<ArtistChartEntry>> future, String Function(ArtistChartEntry) detail, String empty) {
    return FutureBuilder<List<ArtistChartEntry>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: TextButton(onPressed: () => setState(_load), child: const Text('Could not load. Try again')));
        final list = snap.data ?? const <ArtistChartEntry>[];
        if (list.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center)));
        return ListView(children: [
          for (final e in list)
            ListTile(
              leading: SizedBox(width: 32, child: Center(child: Text('${e.rank}', style: Theme.of(context).textTheme.titleMedium))),
              title: Row(children: [Flexible(child: Text(e.artist.stageName, maxLines: 1, overflow: TextOverflow.ellipsis)), if (e.artist.verified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, size: 16))]),
              subtitle: Text(detail(e)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artistId: e.artist.id, catalog: widget.catalog, playback: widget.playback))),
            ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Charts'),
          bottom: const TabBar(tabs: [Tab(text: 'Top songs'), Tab(text: 'Top artists'), Tab(text: 'Rising')]),
        ),
        body: Column(
          children: [
            if (widget.country != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  ChoiceChip(label: const Text('Worldwide'), selected: !_mine, onSelected: (_) => _scope(false)),
                  const SizedBox(width: 8),
                  ChoiceChip(label: Text('My country (${widget.country})'), selected: _mine, onSelected: (_) => _scope(true)),
                ]),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  FutureBuilder<List<CatalogTrack>>(
                    future: _songs,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                      if (snap.hasError) return Center(child: TextButton(onPressed: () => setState(_load), child: const Text('Could not load. Try again')));
                      final list = snap.data ?? const <CatalogTrack>[];
                      if (list.isEmpty) return const Center(child: Text('Nothing has been played yet.'));
                      return ListView(children: [
                        for (var i = 0; i < list.length; i++)
                          CatalogTrackTile(
                            track: list[i],
                            catalog: widget.catalog,
                            playback: widget.playback,
                            onArtistTap: () => openArtist(context, artistId: list[i].artistId, catalog: widget.catalog, playback: widget.playback),
                            onTap: () => widget.playback.setQueue([for (final t in list) t.toPlayable(widget.catalog.streamUri)], startIndex: i, origin: 'chart'),
                          ),
                      ]);
                    },
                  ),
                  _artists(_top, (e) => '${e.plays} plays in the last 28 days', 'No artist has been played yet.'),
                  _artists(_rising, (e) => '${e.plays} plays this week, ${e.change ?? 0} more than the week before', 'No artist is rising right now.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
