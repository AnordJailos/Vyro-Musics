import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import 'library_controller.dart';
import 'library_index.dart';
import 'library_models.dart';

String _mmss(int ms) {
  if (ms <= 0) return '';
  final d = Duration(milliseconds: ms);
  return '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

/// The listener's own music: Songs, Albums, Artists and Liked, with search.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.library, required this.playback});

  final LibraryController library;
  final PlaybackController playback;

  void _play(List<LibraryTrack> list, int index) {
    playback.setQueue([for (final t in list) t.toPlayable()], startIndex: index);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        return DefaultTabController(
          length: 4,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: library.setQuery,
                        decoration: const InputDecoration(
                          hintText: 'Search your music',
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(tooltip: 'Scan for music', onPressed: library.isScanning ? null : library.scan, icon: const Icon(Icons.refresh_rounded)),
                    IconButton(tooltip: 'Add folder', onPressed: library.addFolder, icon: const Icon(Icons.create_new_folder_outlined)),
                    IconButton(tooltip: 'Add songs', onPressed: library.addSongs, icon: const Icon(Icons.add_rounded)),
                  ],
                ),
              ),
              if (library.isScanning) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Looking for music… ${library.foundSoFar} found', style: text.bodySmall),
                ),
              ] else if (library.message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(alignment: Alignment.centerLeft, child: Text(library.message!, style: text.bodySmall)),
                ),
              const TabBar(tabs: [Tab(text: 'Songs'), Tab(text: 'Albums'), Tab(text: 'Artists'), Tab(text: 'Liked')]),
              Expanded(
                child: library.hasTracks
                    ? TabBarView(
                        children: [
                          _SongList(library: library, songs: library.songs, onPlay: _play),
                          _AlbumList(library: library, albums: library.albums, onPlay: _play),
                          _ArtistList(library: library, artists: library.artists, onPlay: _play),
                          _SongList(library: library, songs: library.likedSongs, onPlay: _play, emptyText: 'Tap the heart on a song to keep it here.'),
                        ],
                      )
                    : _EmptyState(library: library),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.library});

  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_music_outlined, size: 56),
            const SizedBox(height: 12),
            Text('No music yet', style: text.titleLarge),
            const SizedBox(height: 4),
            Text('Scan this device, or pick songs to bring into Vyro.', style: text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: library.isScanning ? null : library.scan, icon: const Icon(Icons.refresh_rounded), label: const Text('Scan this device')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: library.addSongs, icon: const Icon(Icons.add_rounded), label: const Text('Add songs')),
          ],
        ),
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({required this.library, required this.track, required this.onTap});

  final LibraryController library;
  final LibraryTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final liked = library.isLiked(track.id);
    return ListTile(
      leading: const Icon(Icons.music_note_rounded),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${track.artist} · ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_mmss(track.durationMs), style: Theme.of(context).textTheme.bodySmall),
          IconButton(
            tooltip: liked ? 'Remove from liked songs' : 'Like',
            onPressed: () => library.toggleLike(track.id),
            icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
          ),
        ],
      ),
    );
  }
}

typedef _PlayCallback = void Function(List<LibraryTrack> list, int index);

class _SongList extends StatelessWidget {
  const _SongList({required this.library, required this.songs, required this.onPlay, this.emptyText = 'Nothing matches your search.'});

  final LibraryController library;
  final List<LibraryTrack> songs;
  final _PlayCallback onPlay;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return Center(child: Text(emptyText));
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, i) => _SongTile(library: library, track: songs[i], onTap: () => onPlay(songs, i)),
    );
  }
}

class _AlbumList extends StatelessWidget {
  const _AlbumList({required this.library, required this.albums, required this.onPlay});

  final LibraryController library;
  final List<AlbumGroup> albums;
  final _PlayCallback onPlay;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return const Center(child: Text('Nothing matches your search.'));
    return ListView(
      children: [
        for (final a in albums)
          ExpansionTile(
            leading: const Icon(Icons.album_rounded),
            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${a.artist} · ${a.tracks.length} songs'),
            children: [
              for (var i = 0; i < a.tracks.length; i++) _SongTile(library: library, track: a.tracks[i], onTap: () => onPlay(a.tracks, i)),
            ],
          ),
      ],
    );
  }
}

class _ArtistList extends StatelessWidget {
  const _ArtistList({required this.library, required this.artists, required this.onPlay});

  final LibraryController library;
  final List<ArtistGroup> artists;
  final _PlayCallback onPlay;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) return const Center(child: Text('Nothing matches your search.'));
    return ListView(
      children: [
        for (final a in artists)
          ExpansionTile(
            leading: const Icon(Icons.person_rounded),
            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${a.tracks.length} songs'),
            children: [
              for (var i = 0; i < a.tracks.length; i++) _SongTile(library: library, track: a.tracks[i], onTap: () => onPlay(a.tracks, i)),
            ],
          ),
      ],
    );
  }
}
