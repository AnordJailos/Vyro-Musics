import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../auth_models.dart';
import 'auth_widgets.dart';

const tasteGenres = ['Afrobeats', 'Amapiano', 'Hip-Hop', 'R&B', 'Pop', 'Gospel', 'Reggae', 'Dancehall', 'Rock', 'Electronic', 'Jazz', 'Soul', 'Latin', 'Classical', 'Lo-fi', 'Country'];
const tasteMoods = ['Chill', 'Focus', 'Workout', 'Party', 'Night drive', 'Worship', 'Sleep', 'Romance'];

/// Shown once after sign-up: pick genres, moods and artists so the first
/// recommendations make sense. Skippable.
class TastePage extends StatefulWidget {
  const TastePage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<TastePage> createState() => _TastePageState();
}

class _TastePageState extends State<TastePage> with BusyState<TastePage> {
  final _genres = <String>{};
  final _moods = <String>{};
  final _artists = <String>{};
  late final Future<List<SuggestedArtist>> _suggested = widget.auth.suggestedArtists();

  Future<void> _save({required bool skip}) => run(() async {
        await widget.auth.saveTaste(
          genres: skip ? const [] : _genres.toList(),
          moods: skip ? const [] : _moods.toList(),
          artistIds: skip ? const [] : _artists.toList(),
        );
      });

  Widget _chips(List<String> all, Set<String> selected) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final g in all)
            FilterChip(
              label: Text(g),
              selected: selected.contains(g),
              onSelected: (on) => setState(() => on ? selected.add(g) : selected.remove(g)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('What do you like?'),
        actions: [TextButton(onPressed: busy ? null : () => _save(skip: true), child: const Text('Skip for now'))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Pick a few and your first recommendations will fit you. You can change this later.', style: text.bodyMedium),
                const SizedBox(height: 20),
                Text('Genres', style: text.titleMedium),
                const SizedBox(height: 8),
                _chips(tasteGenres, _genres),
                const SizedBox(height: 20),
                Text('Moods', style: text.titleMedium),
                const SizedBox(height: 8),
                _chips(tasteMoods, _moods),
                const SizedBox(height: 20),
                Text('Artists', style: text.titleMedium),
                const SizedBox(height: 4),
                FutureBuilder<List<SuggestedArtist>>(
                  future: _suggested,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                    }
                    final artists = snap.data ?? const <SuggestedArtist>[];
                    if (artists.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Artists will appear here as they join Vyro.', style: text.bodySmall),
                      );
                    }
                    return Column(
                      children: [
                        for (final a in artists)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(a.stageName),
                            subtitle: a.genres.isEmpty ? null : Text(a.genres.join(', ')),
                            value: _artists.contains(a.id),
                            onChanged: (on) => setState(() => on == true ? _artists.add(a.id) : _artists.remove(a.id)),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: SubmitButton(label: 'Continue', busy: busy, onPressed: () => _save(skip: false))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
