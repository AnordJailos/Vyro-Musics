import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'audio/audio_handler.dart';
import 'audio/just_audio_deck.dart';
import 'audio/playback_controller.dart';
import 'auth/api_client.dart';
import 'auth/api_errors.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'auth/screens/auth_gate.dart';
import 'auth/social_sign_in.dart';
import 'auth/token_store.dart';
import 'catalog/catalog_api.dart';
import 'library/device_library_platform.dart';
import 'library/library_controller.dart';
import 'library/library_models.dart' show TagInfo;
import 'library/library_scanner.dart';
import 'library/library_store.dart';
import 'library/tag_reader.dart';
import 'shell/app_shell.dart';
import 'stats/api_stats_repository.dart';
import 'stats/demo_stats_repository.dart';
import 'stats/models.dart';
import 'studio/file_picker_service.dart';
import 'studio/studio_api.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktopBackend = !kIsWeb && (Platform.isWindows || Platform.isLinux);
  final hasSystemMedia = !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  // Windows (and Linux) play through media_kit; Android, iOS and macOS use
  // just_audio's native players.
  if (desktopBackend) JustAudioMediaKit.ensureInitialized();

  final playback = PlaybackController(
    deckA: JustAudioDeck(),
    deckB: JustAudioDeck(),
    describeError: (e) => e is ApiException ? e.message : 'Could not play that song.',
  );

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
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
  }

  final library = LibraryController(
    store: JsonLibraryStore(),
    scanner: LibraryScanner(readTags: readTagsInIsolate),
    platform: const DeviceLibraryPlatform(),
  );
  await library.load();

  // The server address. Run with --dart-define=API_URL=http://10.0.2.2:3000 on an Android emulator.
  const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');
  final session = ApiSession();
  final client = ApiClient(baseUrl: Uri.parse(apiUrl), session: session);
  final auth = AuthController(
    api: HttpAuthApi(client),
    store: SecureTokenStore(),
    session: session,
    deviceName: kIsWeb ? 'web' : '${Platform.operatingSystem} app',
  );
  unawaited(auth.restore());

  runApp(VyroApp(
    playback: playback,
    library: library,
    auth: auth,
    stats: ApiStatsRepository(client),
    social: const UnconfiguredSocialSignIn(),
    catalog: HttpCatalogApi(client),
    studio: HttpStudioApi(client),
    picker: const DeviceFilePickerService(),
  ));
}

class VyroApp extends StatefulWidget {
  VyroApp({
    super.key,
    required this.playback,
    StatsRepository? stats,
    LibraryController? library,
    AuthController? auth,
    this.social = const UnconfiguredSocialSignIn(),
    this.catalog = const EmptyCatalogApi(),
    this.studio = const OfflineStudioApi(),
    this.picker = const NoFilePickerService(),
  })  : stats = stats ?? DemoStatsRepository(),
        library = library ?? LibraryController(store: MemoryLibraryStore(), scanner: LibraryScanner(readTags: _noTags)),
        auth = auth ?? (AuthController(api: const OfflineAuthApi(), store: MemoryTokenStore())..continueAsGuest());

  final PlaybackController playback;

  /// Statistics shown to signed-in people.
  final StatsRepository stats;
  final LibraryController library;
  final AuthController auth;
  final SocialSignIn social;
  final CatalogApi catalog;
  final StudioApi studio;
  final FilePickerService picker;

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
        home: AuthGate(
          auth: widget.auth,
          social: widget.social,
          appBuilder: (_) => AppShell(
            theme: _theme,
            playback: widget.playback,
            stats: widget.stats,
            library: widget.library,
            auth: widget.auth,
            catalog: widget.catalog,
            studio: widget.studio,
            picker: widget.picker,
          ),
        ),
      ),
    );
  }
}
