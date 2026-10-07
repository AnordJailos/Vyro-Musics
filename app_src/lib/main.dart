import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'audio/audio_handler.dart';
import 'audio/just_audio_deck.dart';
import 'audio/playback_controller.dart';
import 'library/device_library_platform.dart';
import 'library/library_controller.dart';
import 'library/library_models.dart' show TagInfo;
import 'library/library_scanner.dart';
import 'library/library_store.dart';
import 'library/tag_reader.dart';
import 'shell/app_shell.dart';
import 'stats/demo_stats_repository.dart';
import 'stats/models.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktopBackend = !kIsWeb && (Platform.isWindows || Platform.isLinux);
  final hasSystemMedia = !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  // Windows (and Linux) play through media_kit; Android, iOS and macOS use
  // just_audio's native players.
  if (desktopBackend) JustAudioMediaKit.ensureInitialized();

  final playback = PlaybackController(deckA: JustAudioDeck(), deckB: JustAudioDeck());

  // Background playback, notification, lock screen and headset buttons.
  // (Windows media keys are a separate step.)
  if (hasSystemMedia) {
    await AudioService.init(
      builder: () => VyroAudioHandler(playback),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.vyro.music.playback',
        androidNotificationChannelName: 'Vyro playback',
        androidNotificationOngoing: true,
      ),
    );
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  final library = LibraryController(
    store: JsonLibraryStore(),
    scanner: LibraryScanner(readTags: readTagsInIsolate),
    platform: const DeviceLibraryPlatform(),
  );
  await library.load();

  runApp(VyroApp(playback: playback, library: library));
}

class VyroApp extends StatefulWidget {
  VyroApp({super.key, required this.playback, StatsRepository? stats, LibraryController? library})
      : stats = stats ?? DemoStatsRepository(),
        library = library ?? LibraryController(store: MemoryLibraryStore(), scanner: LibraryScanner(readTags: _noTags));

  final PlaybackController playback;
  final StatsRepository stats;
  final LibraryController library;

  @override
  State<VyroApp> createState() => _VyroAppState();
}

Future<List<TagInfo?>> _noTags(List<String> paths) async => const [];

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
        home: AppShell(theme: _theme, playback: widget.playback, stats: widget.stats, library: widget.library),
      ),
    );
  }
}
