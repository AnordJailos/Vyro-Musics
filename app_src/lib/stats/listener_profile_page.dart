import 'package:flutter/material.dart';

import 'models.dart';
import 'widgets.dart';

/// The listener's profile and statistics. Best ideas gathered from:
///  - period picker: 4 weeks, 6 months, year, all time (stats.fm, Last.fm)
///  - big minutes-listened number, top artists, songs and genres (Apple Replay, Spotify Wrapped)
///  - listening streak and a listening personality (Spotify, Last.fm)
///  - listening clock: which hours you listen (stats.fm)
///  - songs blended and new artists found (only possible in Vyro)
///  - a switch to keep it private (Spotify)
class ListenerProfilePage extends StatefulWidget {
  const ListenerProfilePage({
    super.key,
    required this.repository,
    this.displayName = 'You',
    this.username = 'you',
  });

  final StatsRepository repository;
  final String displayName;
  final String username;

  @override
  State<ListenerProfilePage> createState() => _ListenerProfilePageState();
}

class _ListenerProfilePageState extends State<ListenerProfilePage> {
  ListenerRange _range = ListenerRange.fourWeeks;
  late Future<ListenerStats> _future = widget.repository.listenerStats(_range);
  bool _public = true;

  void _select(ListenerRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _future = widget.repository.listenerStats(range);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<ListenerStats>(
      future: _future,
      builder: (context, snap) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  child: Text(widget.displayName.isEmpty ? '?' : widget.displayName[0].toUpperCase(), style: text.headlineSmall),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.displayName, style: text.titleLarge),
                      Text('@${widget.username}', style: text.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in ListenerRange.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(r.label), selected: r == _range, onSelected: (_) => _select(r)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (snap.hasError)
              const Text('Could not load your listening. Please try again.')
            else if (!snap.hasData)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else
              ..._sections(context, snap.data!),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show my listening on my profile'),
              subtitle: const Text('When this is off, only you can see these numbers.'),
              value: _public,
              onChanged: (v) => setState(() => _public = v),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  List<Widget> _sections(BuildContext context, ListenerStats s) {
    final text = Theme.of(context).textTheme;
    final topGenre = s.topGenres.isEmpty ? 1 : (s.topGenres.first.minutes == 0 ? 1 : s.topGenres.first.minutes);

    Widget mini(IconData icon, String value, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 4),
              Text(value, style: text.titleMedium),
              Text(label, style: text.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        );

    Widget ranked(List<RankedItem> items, String unitSuffix) => Column(
          children: [
            for (var i = 0; i < items.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(width: 24, child: Center(child: Text('${i + 1}', style: text.titleMedium))),
                title: Text(items[i].name),
                subtitle: items[i].detail.isEmpty ? null : Text(items[i].detail),
                trailing: Text('${thousands(items[i].minutes)} $unitSuffix', style: text.bodySmall),
              ),
          ],
        );

    return [
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text('Minutes listened', style: text.labelLarge),
              const SizedBox(height: 6),
              Text(thousands(s.minutes), style: text.displayMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('about ${thousands((s.minutes / 60).round())} hours', style: text.bodyMedium),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  mini(Icons.local_fire_department_rounded, '${s.streakDays}', 'day streak'),
                  mini(Icons.merge_type_rounded, thousands(s.songsBlended), 'songs blended'),
                  mini(Icons.explore_rounded, thousands(s.newArtists), 'new artists found'),
                ],
              ),
            ],
          ),
        ),
      ),
      SectionCard(
        title: s.persona.title,
        subtitle: s.persona.blurb,
        child: ClockChart(values: s.clock),
      ),
      SectionCard(title: 'Top artists', child: ranked(s.topArtists, 'min')),
      SectionCard(title: 'Top songs', child: ranked(s.topTracks, 'plays')),
      SectionCard(
        title: 'Top genres',
        child: BarList(rows: [for (final g in s.topGenres) BarRow(g.name, g.minutes / topGenre, '${thousands(g.minutes)} min')]),
      ),
      const SectionCard(
        title: 'Your year in music',
        subtitle: 'A look back at your favorite songs, artists and moments arrives in December.',
        child: Row(
          children: [
            Icon(Icons.auto_awesome_rounded),
            SizedBox(width: 12),
            Expanded(child: Text('Keep listening and mixing. Your year builds as you go.')),
          ],
        ),
      ),
    ];
  }
}
