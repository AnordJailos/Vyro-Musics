import 'package:flutter/material.dart';

import '../playlists/playlists_tab.dart';
import 'delete_song.dart';
import 'liked_tab.dart';
import 'library_settings_page.dart';
import 'likes_scope.dart';
import '../shell/queue_menu.dart';

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
    playback.setQueue([for (final t in list) t.toPlayable()], startIndex: index, origin: 'library');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        return DefaultTabController(
          length: 7,
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
                    IconButton(
                      tooltip: 'Library settings',
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LibrarySettingsPage(library: library))),
                      icon: const Icon(Icons.tune_rounded),
                    ),
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
              const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Songs'), Tab(text: 'Albums'), Tab(text: 'Artists'), Tab(text: 'Genres'), Tab(text: 'Folders'), Tab(text: 'Liked'), Tab(text: 'Playlists')]),
              Expanded(
                child: TabBarView(
                  children: [
                    library.hasTracks ? _SongList(library: library, playback: playback, songs: library.songs, onPlay: _play) : _EmptyState(library: library),
                    library.hasTracks ? _AlbumList(library: library, playback: playback, albums: library.albums, onPlay: _play) : _EmptyState(library: library),
                    library.hasTracks ? _ArtistList(library: library, playback: playback, artists: library.artists, onPlay: _play) : _EmptyState(library: library),
                    library.hasTracks
                        ? _GroupList(library: library, playback: playback, onPlay: _play, groups: [for (final g in library.genres) _Group(g.name, '${g.tracks.length} songs', g.tracks, Icons.category_rounded)])
                        : _EmptyState(library: library),
                    library.hasTracks
                        ? _GroupList(library: library, playback: playback, onPlay: _play, groups: [for (final f in library.folders) _Group(f.name, '${f.path} · ${f.tracks.length} songs', f.tracks, Icons.folder_rounded)])
                        : _EmptyState(library: library),
                    LikesScope.maybeOf(context) != null
                        ? LikedTab(playback: playback)
                        : (library.hasTracks
                            ? _SongList(library: library, playback: playback, songs: library.likedSongs, onPlay: _play, emptyText: 'Tap the heart on a song to keep it here.')
                            : _EmptyState(library: library)),
                    PlaylistsTab(playback: playback),
                  ],
                ),
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
  const _SongTile({required this.library, required this.playback, required this.track, required this.onTap});

  final LibraryController library;
  final PlaybackController playback;
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
          QueueMenuButton(playback: playback, label: track.title, track: track.toPlayable, onDelete: () => confirmAndDeleteSong(context, library: library, playback: playback, track: track)),
        ],
      ),
    );
  }
}

typedef _PlayCallback = void Function(List<LibraryTrack> list, int index);

class _SongList extends StatelessWidget {
  const _SongList({required this.library, required this.playback, required this.songs, required this.onPlay, this.emptyText = 'Nothing matches your search.'});

  final LibraryController library;
  final PlaybackController playback;
  final List<LibraryTrack> songs;
  final _PlayCallback onPlay;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return Center(child: Text(emptyText));
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, i) => _SongTile(library: library, playback: playback, track: songs[i], onTap: () => onPlay(songs, i)),
    );
  }
}

class _AlbumList extends StatelessWidget {
  const _AlbumList({required this.library, required this.playback, required this.albums, required this.onPlay});

  final LibraryController library;
  final PlaybackController playback;
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
              for (var i = 0; i < a.tracks.length; i++) _SongTile(library: library, playback: playback, track: a.tracks[i], onTap: () => onPlay(a.tracks, i)),
            ],
          ),
      ],
    );
  }
}

class _ArtistList extends StatelessWidget {
  const _ArtistList({required this.library, required this.playback, required this.artists, required this.onPlay});

  final LibraryController library;
  final PlaybackController playback;
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
              for (var i = 0; i < a.tracks.length; i++) _SongTile(library: library, playback: playback, track: a.tracks[i], onTap: () => onPlay(a.tracks, i)),
            ],
          ),
      ],
    );
  }
}

class _Group {
  const _Group(this.title, this.subtitle, this.tracks, this.icon);
  final String title;
  final String subtitle;
  final List<LibraryTrack> tracks;
  final IconData icon;
}

/// Genres and folders: tap one to see its songs.
class _GroupList extends StatelessWidget {
  const _GroupList({required this.library, required this.playback, required this.groups, required this.onPlay});

  final LibraryController library;
  final PlaybackController playback;
  final List<_Group> groups;
  final _PlayCallback onPlay;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const Center(child: Text('Nothing matches your search.'));
    return ListView(
      children: [
        for (final g in groups)
          ExpansionTile(
            leading: Icon(g.icon),
            title: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(g.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            children: [
              for (var i = 0; i < g.tracks.length; i++) _SongTile(library: library, playback: playback, track: g.tracks[i], onTap: () => onPlay(g.tracks, i)),
            ],
          ),
      ],
    );
  }
}
