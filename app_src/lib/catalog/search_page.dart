import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../library/library_controller.dart';
import '../library/library_index.dart';
import '../library/library_models.dart';
import 'catalog_api.dart';
import 'catalog_models.dart';
import 'catalog_widgets.dart';

/// One search across the Vyro catalog and the music on this device, with each result labelled by where it lives.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.catalog, required this.library, required this.playback});

  final CatalogApi catalog;
  final LibraryController library;
  final PlaybackController playback;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _field = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Future<List<CatalogTrack>>? _vyro;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final q = text.trim();
      setState(() {
        _query = q;
        _vyro = q.isEmpty ? null : widget.catalog.search(q);
      });
    });
  }

  void _playVyro(List<CatalogTrack> list, int i) {
    widget.playback.setQueue([for (final t in list) t.toPlayable(widget.catalog.streamUri)], startIndex: i);
  }

  void _playLocal(List<LibraryTrack> list, int i) {
    widget.playback.setQueue([for (final t in list) t.toPlayable()], startIndex: i);
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
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(hintText: 'Songs and artists, on Vyro and on this device', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
        ),
        Expanded(
          child: _query.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Search Vyro and your own music in one place.', style: text.bodyMedium, textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('On Vyro', style: text.titleMedium),
                    FutureBuilder<List<CatalogTrack>>(
                      future: _vyro,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                        }
                        if (snap.hasError) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Could not search Vyro right now.', style: text.bodySmall));
                        final list = snap.data ?? const <CatalogTrack>[];
                        if (list.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Nothing on Vyro matches.', style: text.bodySmall));
                        return Column(children: [for (var i = 0; i < list.length; i++) CatalogTrackTile(track: list[i], catalog: widget.catalog, onTap: () => _playVyro(list, i))]);
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
