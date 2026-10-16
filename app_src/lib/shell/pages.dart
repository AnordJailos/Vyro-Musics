import 'package:flutter/material.dart';

import '../audio/track.dart';
import '../catalog/artist_page.dart';
import '../catalog/charts_page.dart';
import '../history/history_store.dart';
import '../history/recent_tracks.dart';

import '../audio/demo_tracks.dart';
import '../audio/playback_controller.dart';
import '../brand/vyro_mark.dart';
import '../catalog/catalog_api.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_widgets.dart';
import '../theme/theme_controller.dart';
import '../theme/vyro_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller, required this.catalog, this.history, this.country});

  final PlaybackController controller;
  final CatalogApi catalog;

  /// Where plays are kept, for "Continue listening".
  final HistoryStore? history;

  /// The person's country, for the charts.
  final String? country;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<CatalogTrack>> _fresh = widget.catalog.newReleases();
  late Future<List<CatalogTrack>> _top = widget.catalog.charts();
  late Future<List<RecSection>> _recs = _loadRecs();
  late Future<List<Track>> _recent = _loadRecent();
  final Set<String> _hiddenTracks = {};
  final Set<String> _hiddenArtists = {};

  // Suggestions are a bonus: if they cannot be loaded, the rest of Home still works.
  Future<List<Track>> _loadRecent() async {
    final h = widget.history;
    if (h == null) return const [];
    try {
      return await recentTracks(await h.loadAll(), streamUri: widget.catalog.streamUri);
    } catch (_) {
      return const [];
    }
  }

  Widget _continueListening() {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<List<Track>>(
      future: _recent,
      builder: (context, snap) {
        final list = snap.data ?? const <Track>[];
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text('Continue listening', style: text.titleMedium),
            for (var i = 0; i < list.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_rounded),
                title: Text(list[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Row(children: [SourceBadge(list[i].source == TrackSource.vyro ? 'Vyro' : 'Local'), const SizedBox(width: 6), Expanded(child: Text(list[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis))]),
                onTap: () => widget.controller.setQueue(list, startIndex: i, origin: 'direct'),
              ),
          ],
        );
      },
    );
  }

  Future<List<RecSection>> _loadRecs() => widget.catalog.recommendations().catchError((_) => <RecSection>[]);

  Future<void> _refresh() async {
    setState(() {
      _fresh = widget.catalog.newReleases();
      _top = widget.catalog.charts();
      _recs = _loadRecs();
      _recent = _loadRecent();
      _hiddenTracks.clear();
      _hiddenArtists.clear();
    });
    await Future.wait([_fresh.catchError((_) => <CatalogTrack>[]), _top.catchError((_) => <CatalogTrack>[]), _recs]);
  }

  void _play(List<CatalogTrack> list, int index, String origin) {
    widget.controller.setQueue([for (final t in list) t.toPlayable(widget.catalog.streamUri)], startIndex: index, origin: origin);
  }

  Future<void> _dismiss(CatalogTrack track, {required bool artist}) async {
    setState(() => artist ? _hiddenArtists.add(track.artistId) : _hiddenTracks.add(track.id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 3), content: Text(artist ? "OK, we won't suggest ${track.artistName}." : 'OK, we will suggest fewer songs like this.')));
    try {
      await widget.catalog.notInterested(kind: artist ? 'artist' : 'track', id: artist ? track.artistId : track.id);
    } catch (_) {
      // The song is hidden for now either way; it will come back on refresh if the choice could not be saved.
    }
  }

  Widget _recommendations() {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<List<RecSection>>(
      future: _recs,
      builder: (context, snap) {
        final blocks = <Widget>[];
        for (final s in snap.data ?? const <RecSection>[]) {
          final shown = [for (final t in s.tracks) if (!_hiddenTracks.contains(t.id) && !_hiddenArtists.contains(t.artistId)) t].take(10).toList();
          if (shown.isEmpty) continue;
          final origin = s.kind == 'popular' ? 'chart' : 'recommendation';
          blocks.add(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(s.title, style: text.titleMedium),
              if (s.reason.isNotEmpty) Text(s.reason, style: text.bodySmall),
              for (var i = 0; i < shown.length; i++)
                CatalogTrackTile(
                  track: shown[i],
                  catalog: widget.catalog,
                  playback: widget.controller,
                  onArtistTap: () => openArtist(context, artistId: shown[i].artistId, catalog: widget.catalog, playback: widget.controller),
                  onTap: () => _play(shown, i, origin),
                  onNotInterested: () => _dismiss(shown[i], artist: false),
                  onHideArtist: () => _dismiss(shown[i], artist: true),
                ),
            ],
          ));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
      },
    );
  }

  Widget _section(String title, Future<List<CatalogTrack>> future, String emptyText, String origin) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(title, style: text.titleMedium),
        FutureBuilder<List<CatalogTrack>>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Could not load. Pull down to try again.', style: text.bodySmall));
            }
            final list = snap.data ?? const <CatalogTrack>[];
            if (list.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(emptyText, style: text.bodySmall));
            final shown = list.take(10).toList();
            return Column(
              children: [
                for (var i = 0; i < shown.length; i++)
                  CatalogTrackTile(track: shown[i], catalog: widget.catalog, playback: widget.controller, onArtistTap: () => openArtist(context, artistId: shown[i].artistId, catalog: widget.catalog, playback: widget.controller), onTap: () => _play(shown, i, origin)),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 8),
          const Center(child: VyroAppIcon(size: 88)),
          const SizedBox(height: 12),
          const Center(child: VyroWordmark(fontSize: 40)),
          const SizedBox(height: 8),
          Center(
            child: Text('PRESS PLAY. KEEP THE FLOW.', style: text.labelMedium?.copyWith(letterSpacing: 3, color: VyroColors.mist)),
          ),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChartsPage(catalog: widget.catalog, playback: widget.controller, country: widget.country))),
              icon: const Icon(Icons.leaderboard_rounded),
              label: const Text('Charts'),
            ),
          ),
          _continueListening(),
          _recommendations(),
          _section('New on Vyro', _fresh, 'Songs from artists will appear here as they join Vyro.', 'direct'),
          _section('Top this week', _top, 'The most played songs will appear here.', 'chart'),
          const SizedBox(height: 20),
          Text('Try the mix engine', style: text.titleMedium),
          const SizedBox(height: 4),
          Text('Play a demo song, open the player, and switch between Normal and Mixing.', style: text.bodySmall),
          const SizedBox(height: 8),
          for (var i = 0; i < demoTracks.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note_rounded),
              title: Text(demoTracks[i].title),
              subtitle: Text(demoTracks[i].artist),
              onTap: () => widget.controller.setQueue(demoTracks, startIndex: i),
            ),
        ],
      ),
    );
  }
}

class ComingNextPage extends StatelessWidget {
  const ComingNextPage({super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(title, style: text.titleLarge),
          const SizedBox(height: 4),
          Text('Arrives in an upcoming build', style: text.bodyMedium),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Theme', style: text.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in VyroThemeMode.values)
                ChoiceChip(
                  label: Text(mode.label),
                  selected: theme.mode == mode,
                  onSelected: (_) => theme.setMode(mode),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Text('Accent', style: text.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final accent in VyroAccent.values)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: accent.seed, radius: 8),
                  label: Text(accent.label),
                  selected: theme.accent == accent,
                  onSelected: (_) => theme.setAccent(accent),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
