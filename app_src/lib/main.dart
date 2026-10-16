import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'audio/audio_handler.dart';
import 'admin/admin_api.dart';
import 'audio/just_audio_deck.dart';
import 'audio/playback_controller.dart';
import 'auth/api_client.dart';
import 'auth/api_errors.dart';
import 'auth/auth_api.dart';
import 'auth/auth_controller.dart';
import 'auth/screens/auth_gate.dart';
import 'auth/social_sign_in.dart';
import 'auth/token_store.dart';
import 'audio/playback_store.dart';
import 'catalog/recent_searches.dart';
import 'library/likes_controller.dart';
import 'library/likes_scope.dart';
import 'library/likes_store.dart';
import 'playlists/playlist_store.dart';
import 'playlists/playlists_controller.dart';
import 'playlists/playlists_scope.dart';
import 'audio/track.dart' show Track, TrackSource;
import 'catalog/catalog_api.dart';
import 'history/history_store.dart';
import 'history/history_sync.dart';
import 'history/local_stats.dart';
import 'history/play_recorder.dart';
import 'lyrics/lyrics_provider.dart' show TextReader;
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

  late final PlayRecorder recorder;
  final playback = PlaybackController(
    deckA: JustAudioDeck(),
    deckB: JustAudioDeck(),
    describeError: (e) => e is ApiException ? e.message : 'Could not play that song.',
    // A lost connection or a busy server is worth trying again; "not allowed" or "not found" is not.
    isRetryable: (e) => e is! ApiException || e.status == 0 || e.status == 408 || e.status == 429 || e.status >= 500,
    onPlayEnded: (play) => unawaited(recorder.record(play)),
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
  // Listening history: kept on the device, and Vyro plays are sent to the server whenever someone is signed in.
  final history = FileHistoryStore();
  final sync = HistorySync(store: history, api: HttpHistoryApi(client), canUpload: () => auth.isSignedIn && !auth.isOffline);
  recorder = PlayRecorder(
    store: history,
    sync: sync,
    isPrivate: () => auth.user?.settings.privateSession ?? false,
    platform: kIsWeb ? 'web' : Platform.operatingSystem,
  );
  auth.addListener(() {
    if (auth.isSignedIn) sync.schedule(immediately: true); // sends anything waiting from before signing in
  });
  unawaited(auth.restore());

  // Bring back the queue and the place in the song from last time, paused and ready. Nothing is loaded until
  // play is pressed, so starting the app does not need the network.
  final catalog = HttpCatalogApi(client);
  // Songs read back from a save need a way to ask for a fresh stream address.
  Track attach(Track t) => t.source == TrackSource.vyro && t.id.startsWith('vyro:') ? t.withResolveUri(() => catalog.streamUri(t.id.substring(5))) : t;
  final playbackStore = FilePlaybackStore(attach: attach);
  final playlists = PlaylistsController(store: FilePlaylistStore(), attach: attach);
  await playlists.load();
  final likes = LikesController(library: library, store: FileLikesStore(), catalog: catalog, canSync: () => auth.isSignedIn && !auth.isOffline, attach: attach);
  await likes.load();
  final recents = RecentSearches(store: FileRecentSearchStore());
  await recents.load();
  auth.addListener(() {
    if (auth.isSignedIn) unawaited(likes.sync()); // sends likes made before signing in, and fetches the ones made elsewhere
  });
  final saved = await playbackStore.load();
  if (saved != null) await playback.restore(saved);
  PlaybackPersistor(controller: playback, store: playbackStore).start();

  runApp(VyroApp(
    playback: playback,
    library: library,
    auth: auth,
    stats: MergedStatsRepository(server: ApiStatsRepository(client), store: history),
    social: const UnconfiguredSocialSignIn(),
    catalog: catalog,
    studio: HttpStudioApi(client),
    picker: const DeviceFilePickerService(),
    admin: HttpAdminApi(client),
    history: history,
    embeddedLyrics: readEmbeddedLyrics,
    playlists: playlists,
    likes: likes,
    recentSearches: recents,
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
    this.admin = const OfflineAdminApi(),
    HistoryStore? history,
    this.embeddedLyrics,
    PlaylistsController? playlists,
    this.likes,
    this.recentSearches,
  })  : stats = stats ?? DemoStatsRepository(),
        library = library ?? LibraryController(store: MemoryLibraryStore(), scanner: LibraryScanner(readTags: _noTags)),
        history = history ?? MemoryHistoryStore(),
        playlists = playlists ?? PlaylistsController(store: MemoryPlaylistStore()),
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
  final AdminApi admin;
  final HistoryStore history;
  final TextReader? embeddedLyrics;
  final PlaylistsController playlists;

  /// Likes for songs on the device and on Vyro. Made from the library when not given.
  final LikesController? likes;

  /// Recent searches. Kept in memory when not given.
  final RecentSearches? recentSearches;

  @override
  State<VyroApp> createState() => _VyroAppState();
}

Future<List<TagInfo?>> _noTags(List<String> paths) async => const [];

class _VyroAppState extends State<VyroApp> {
  final _theme = ThemeController();
  late final RecentSearches _recents = widget.recentSearches ?? RecentSearches(store: MemoryRecentSearchStore());
  late final LikesController _likes = widget.likes ?? LikesController(library: widget.library, store: MemoryLikesStore(), catalog: widget.catalog);

  @override
  void dispose() {
    if (widget.likes == null) _likes.dispose();
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RecentSearchesScope(
      controller: _recents,
      child: LikesScope(
      controller: _likes,
      child: PlaylistsScope(
      controller: widget.playlists,
      picker: widget.picker,
      child: ListenableBuilder(
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
            admin: widget.admin,
            history: widget.history,
            embeddedLyrics: widget.embeddedLyrics,
          ),
        ),
      ),
    ),
    ),
    ),
    );
  }
}
