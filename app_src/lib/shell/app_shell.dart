import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../brand/vyro_mark.dart';
import '../stats/artist_stats_page.dart';
import '../stats/listener_profile_page.dart';
import '../stats/models.dart';
import '../theme/theme_controller.dart';
import 'pages.dart';
import 'player_ui.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _listenerTabs = [
  _Tab('Home', Icons.home_outlined, Icons.home_rounded),
  _Tab('Search', Icons.search_rounded, Icons.search_rounded),
  _Tab('Library', Icons.library_music_outlined, Icons.library_music_rounded),
  _Tab('Profile', Icons.person_outline_rounded, Icons.person_rounded),
];

const _artistTabs = [
  _Tab('Studio', Icons.graphic_eq_rounded, Icons.graphic_eq_rounded),
  _Tab('Releases', Icons.album_outlined, Icons.album_rounded),
  _Tab('Stats', Icons.insights_outlined, Icons.insights_rounded),
];

/// ART-02: one account, two modes. The switch in the top bar flips between
/// the listener tabs and the artist tabs.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.theme, required this.playback, required this.stats});

  final ThemeController theme;
  final PlaybackController playback;
  final StatsRepository stats;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _artistMode = false;

  Widget _page(_Tab tab) {
    switch (tab.label) {
      case 'Home':
        return HomePage(controller: widget.playback);
      case 'Profile':
        return ListenerProfilePage(repository: widget.stats);
      case 'Stats':
        return ArtistStatsPage(repository: widget.stats);
      default:
        return ComingNextPage(title: tab.label, icon: tab.selectedIcon);
    }
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: SettingsPage(theme: widget.theme),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _artistMode ? _artistTabs : _listenerTabs;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [VyroMark(size: 28), SizedBox(width: 8), VyroWordmark(fontSize: 24)],
        ),
        actions: [
          IconButton(
            tooltip: _artistMode ? 'Switch to Listener' : 'Switch to Artist Studio',
            icon: Icon(_artistMode ? Icons.headphones_rounded : Icons.mic_external_on_rounded),
            onPressed: () => setState(() {
              _artistMode = !_artistMode;
              _index = 0;
            }),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _page(tabs[_index]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(controller: widget.playback),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final t in tabs)
                NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: t.label,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
