import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'widgets.dart';

/// The artist's private dashboard. Best ideas gathered from the apps we are
/// inspired by:
///  - period picker with a comparison against the previous period (Apple, Spotify)
///  - "right now" last-48-hours view (Spotify)
///  - new / returning / super listeners (Spotify)
///  - where listeners are and where plays come from (Apple, Spotify)
///  - per-song retention curve (YouTube Studio)
///  - which songs get mixed with yours (only possible in Vyro)
class ArtistStatsPage extends StatefulWidget {
  const ArtistStatsPage({super.key, required this.repository});

  final StatsRepository repository;

  @override
  State<ArtistStatsPage> createState() => _ArtistStatsPageState();
}

class _ArtistStatsPageState extends State<ArtistStatsPage> {
  ArtistRange _range = ArtistRange.d28;
  late Future<ArtistStats> _future = widget.repository.artistStats(_range);

  void _select(ArtistRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _future = widget.repository.artistStats(range);
    });
  }

  void _openSong(SongStats song) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SongSheet(song: song, retention: widget.repository.retention(song.trackId, _range)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ArtistStats>(
      future: _future,
      builder: (context, snap) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in ArtistRange.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(r.label), selected: r == _range, onSelected: (_) => _select(r)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (snap.hasError)
              const Text('Could not load your statistics. Please try again.')
            else if (!snap.hasData)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else
              ..._sections(context, snap.data!),
          ],
        );
      },
    );
  }

  List<Widget> _sections(BuildContext context, ArtistStats s) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final last48 = s.realtime.fold<int>(0, (a, b) => a + b);
    final audienceTotal = s.newListeners + s.returningListeners;

    return [
      SectionCard(
        title: 'Right now',
        subtitle: 'Plays in the last 48 hours',
        child: Row(
          children: [
            Text(compact(last48), style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            Expanded(child: TrendChart(primary: s.realtime, height: 56, showAxes: false)),
          ],
        ),
      ),
      Row(
        children: [
          Expanded(child: StatCard(label: 'Plays', value: s.plays.value, previous: s.plays.previous)),
          const SizedBox(width: 12),
          Expanded(child: StatCard(label: 'Listeners', value: s.listeners.value, previous: s.listeners.previous)),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: StatCard(label: 'New followers', value: s.newFollowers.value, previous: s.newFollowers.previous)),
          const SizedBox(width: 12),
          Expanded(child: StatCard(label: 'Saves', value: s.saves.value, previous: s.saves.previous)),
        ],
      ),
      const SizedBox(height: 12),
      SectionCard(
        title: 'Plays and listeners',
        subtitle: s.daily.isEmpty ? null : '${monthDay(s.daily.first.date)} to ${monthDay(s.daily.last.date)}',
        child: Column(
          children: [
            TrendChart(
              primary: [for (final d in s.daily) d.plays],
              secondary: [for (final d in s.daily) d.listeners],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                LegendDot(color: scheme.primary, label: 'Plays'),
                const SizedBox(width: 16),
                LegendDot(color: scheme.tertiary, label: 'Listeners'),
              ],
            ),
          ],
        ),
      ),
      SectionCard(
        title: 'Your audience',
        subtitle: '${compact(audienceTotal)} listeners in this period',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    Expanded(flex: math.max(1, s.newListeners), child: ColoredBox(color: scheme.primary)),
                    Expanded(flex: math.max(1, s.returningListeners), child: ColoredBox(color: scheme.tertiary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                LegendDot(color: scheme.primary, label: 'New ${compact(s.newListeners)}'),
                const SizedBox(width: 16),
                LegendDot(color: scheme.tertiary, label: 'Returning ${compact(s.returningListeners)}'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.star_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${compact(s.superListeners)} super listeners (5 or more plays)', style: text.bodyMedium),
                ),
              ],
            ),
          ],
        ),
      ),
      SectionCard(
        title: 'Where listeners are',
        subtitle: 'Places with very few listeners are grouped under Other to protect them.',
        child: BarList(rows: [for (final c in s.countries) BarRow(c.name, c.share, '${pct(c.share)} · ${compact(c.plays)} plays')]),
      ),
      SectionCard(
        title: 'Where plays come from',
        child: BarList(rows: [for (final r in s.sources) BarRow(r.name, r.share, '${pct(r.share)} · ${compact(r.plays)} plays')]),
      ),
      SectionCard(
        title: 'Your songs',
        subtitle: 'Tap a song to see how far listeners get.',
        child: Column(
          children: [
            for (var i = 0; i < s.songs.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(width: 24, child: Center(child: Text('${i + 1}', style: text.titleMedium))),
                title: Text(s.songs[i].title),
                subtitle: Text(
                  '${compact(s.songs[i].plays)} plays · ${pct(s.songs[i].completionRate)} finish · ${pct(s.songs[i].skipRate)} skip',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openSong(s.songs[i]),
              ),
          ],
        ),
      ),
      if (s.mixedWith.isNotEmpty)
        SectionCard(
          title: 'Your songs in the mix',
          subtitle: 'Songs that listeners blend yours with',
          child: Column(
            children: [
              for (final m in s.mixedWith)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.merge_type_rounded),
                  title: Text('${m.track}  →  ${m.partner}'),
                  trailing: Text('${m.times}×', style: text.titleSmall),
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 24),
        child: Text(
          'A play counts as a stream after 30 seconds. Every number is compared with the period just before it.',
          style: text.bodySmall,
        ),
      ),
    ];
  }
}

class _SongSheet extends StatelessWidget {
  const _SongSheet({required this.song, required this.retention});

  final SongStats song;
  final Future<RetentionCurve> retention;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(song.title, style: text.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '${compact(song.plays)} plays · ${compact(song.listeners)} listeners · ${compact(song.saves)} saves',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('How far listeners get', style: text.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<RetentionCurve>(
            future: retention,
            builder: (context, snap) => snap.hasData
                ? RetentionChart(points: snap.data!.points)
                : const SizedBox(height: 170, child: Center(child: CircularProgressIndicator())),
          ),
          const SizedBox(height: 8),
          Text(
            '${pct(song.completionRate)} of streams reach the end. ${pct(song.skipRate)} of starts end before 30 seconds.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
