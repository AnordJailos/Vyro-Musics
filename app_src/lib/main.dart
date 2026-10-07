import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'audio/just_audio_deck.dart';
import 'audio/playback_controller.dart';
import 'shell/app_shell.dart';
import 'stats/demo_stats_repository.dart';
import 'stats/models.dart';
import 'theme/theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows (and Linux) use the media_kit backend; Android, iOS and macOS use
  // just_audio's native players.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    JustAudioMediaKit.ensureInitialized();
  }
  runApp(
    VyroApp(playback: PlaybackController(deckA: JustAudioDeck(), deckB: JustAudioDeck())),
  );
}

class VyroApp extends StatefulWidget {
  VyroApp({super.key, required this.playback, StatsRepository? stats}) : stats = stats ?? DemoStatsRepository();

  final PlaybackController playback;
  final StatsRepository stats;

  @override
  State<VyroApp> createState() => _VyroAppState();
}

class _VyroAppState extends State<VyroApp> {
  final _theme = ThemeController();

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => MaterialApp(
        title: 'Vyro Music',
        debugShowCheckedModeBanner: false,
        theme: _theme.light,
        darkTheme: _theme.dark,
        themeMode: _theme.themeMode,
        home: AppShell(theme: _theme, playback: widget.playback, stats: widget.stats),
      ),
    );
  }
}
