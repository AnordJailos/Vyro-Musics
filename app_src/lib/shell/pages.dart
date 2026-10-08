import 'package:flutter/material.dart';

import '../audio/demo_tracks.dart';
import '../audio/playback_controller.dart';
import '../brand/vyro_mark.dart';
import '../catalog/catalog_api.dart';
import '../catalog/catalog_models.dart';
import '../catalog/catalog_widgets.dart';
import '../theme/theme_controller.dart';
import '../theme/vyro_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller, required this.catalog});

  final PlaybackController controller;
  final CatalogApi catalog;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<CatalogTrack>> _fresh = widget.catalog.newReleases();
  late Future<List<CatalogTrack>> _top = widget.catalog.charts();

  Future<void> _refresh() async {
    setState(() {
      _fresh = widget.catalog.newReleases();
      _top = widget.catalog.charts();
    });
    await Future.wait([_fresh.catchError((_) => <CatalogTrack>[]), _top.catchError((_) => <CatalogTrack>[])]);
  }

  void _play(List<CatalogTrack> list, int index) {
    widget.controller.setQueue([for (final t in list) t.toPlayable(widget.catalog.streamUri)], startIndex: index);
  }

  Widget _section(String title, Future<List<CatalogTrack>> future, String emptyText) {
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
                  CatalogTrackTile(track: shown[i], catalog: widget.catalog, onTap: () => _play(shown, i)),
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
          _section('New on Vyro', _fresh, 'Songs from artists will appear here as they join Vyro.'),
          _section('Top this week', _top, 'The most played songs will appear here.'),
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
