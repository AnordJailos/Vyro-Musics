import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../auth/auth_controller.dart';
import '../auth/screens/account_banners.dart';
import '../auth/screens/account_page.dart';
import '../auth/screens/artist_upgrade_page.dart';
import '../auth/screens/guest_prompt.dart';
import '../brand/vyro_mark.dart';
import '../library/library_controller.dart';
import '../library/library_page.dart';
import '../stats/artist_stats_page.dart';
import '../stats/demo_stats_repository.dart';
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

/// ART-02: one account, two modes. The top-bar button flips between the
/// listener tabs and the artist tabs; for someone who is not an artist yet it
/// opens "Become an artist", and for a guest it asks them to sign in.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.theme,
    required this.playback,
    required this.stats,
    required this.library,
    required this.auth,
  });

  final ThemeController theme;
  final PlaybackController playback;

  /// Statistics for signed-in people. Guests see demo numbers.
  final StatsRepository stats;
  final LibraryController library;
  final AuthController auth;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _artistMode = false;
  final StatsRepository _demoStats = DemoStatsRepository();

  AuthController get _auth => widget.auth;
  StatsRepository get _stats => _auth.isSignedIn ? widget.stats : _demoStats;

  void _openAccount() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AccountPage(auth: _auth)));
  }

  Widget _page(_Tab tab) {
    final user = _auth.user;
    switch (tab.label) {
      case 'Home':
        return HomePage(controller: widget.playback);
      case 'Library':
        return LibraryPage(library: widget.library, playback: widget.playback);
      case 'Profile':
        if (!_auth.isSignedIn || user == null) return GuestPrompt(auth: _auth);
        return ListenerProfilePage(
          repository: _stats,
          displayName: user.displayName,
          username: user.username,
          shareListening: user.settings.shareListening,
          onShareChanged: (v) => _auth.updateSettings(shareListening: v),
          onOpenAccount: _openAccount,
        );
      case 'Stats':
        return ArtistStatsPage(repository: _stats);
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

  Future<void> _asksToSignIn(String reason) {
    return showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Create an account'),
        content: Text(reason),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Not now')),
          FilledButton(
            onPressed: () {
              Navigator.of(d).pop();
              _auth.leaveGuest();
            },
            child: const Text('Create account or log in'),
          ),
        ],
      ),
    );
  }

  Future<void> _onModePressed() async {
    final user = _auth.user;
    if (!_auth.isSignedIn || user == null) {
      await _asksToSignIn('The Artist Studio is for people with an account. Create one to share your music.');
      return;
    }
    if (!user.isArtist) {
      final became = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => ArtistUpgradePage(auth: _auth)));
      if (became == true && mounted) {
        setState(() {
          _artistMode = true;
          _index = 0;
        });
      }
      return;
    }
    setState(() {
      _artistMode = !_artistMode;
      _index = 0;
    });
  }

  String get _modeTooltip {
    final user = _auth.user;
    if (!_auth.isSignedIn || user == null) return 'Sign in to become an artist';
    if (!user.isArtist) return 'Become an artist';
    return _artistMode ? 'Switch to Listener' : 'Switch to Artist Studio';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) {
        final tabs = _artistMode ? _artistTabs : _listenerTabs;
        final signedIn = _auth.isSignedIn;
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [VyroMark(size: 28), SizedBox(width: 8), VyroWordmark(fontSize: 24)],
            ),
            actions: [
              IconButton(
                tooltip: _modeTooltip,
                icon: Icon(_artistMode ? Icons.headphones_rounded : Icons.mic_external_on_rounded),
                onPressed: _onModePressed,
              ),
              IconButton(
                tooltip: signedIn ? 'Account' : 'Log in',
                icon: Icon(signedIn ? Icons.account_circle_outlined : Icons.login_rounded),
                onPressed: signedIn ? _openAccount : _auth.leaveGuest,
              ),
              IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
            ],
          ),
          body: Column(
            children: [
              AccountBanners(auth: _auth),
              Expanded(child: _page(tabs[_index])),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MiniPlayer(controller: widget.playback),
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final t in tabs)
                    NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
