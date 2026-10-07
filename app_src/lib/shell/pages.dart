import 'package:flutter/material.dart';
import '../audio/demo_tracks.dart';
import '../audio/playback_controller.dart';
import '../brand/vyro_mark.dart';
import '../theme/theme_controller.dart';
import '../theme/vyro_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 8),
        const Center(child: VyroAppIcon(size: 96)),
        const SizedBox(height: 16),
        const Center(child: VyroWordmark(fontSize: 44)),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'PRESS PLAY. KEEP THE FLOW.',
            style: text.labelMedium?.copyWith(letterSpacing: 3, color: VyroColors.mist),
          ),
        ),
        const SizedBox(height: 32),
        Text('Try the mix engine', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Play a demo song, open the player, and switch between Normal and Mixing.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < demoTracks.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.music_note_rounded),
            title: Text(demoTracks[i].title),
            subtitle: Text(demoTracks[i].artist),
            onTap: () => controller.setQueue(demoTracks, startIndex: i),
          ),
      ],
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
