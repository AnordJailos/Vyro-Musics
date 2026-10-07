import 'package:flutter/foundation.dart';

import 'library_index.dart';
import 'library_models.dart';
import 'library_platform.dart';
import 'library_scanner.dart';
import 'library_store.dart';

/// The music found on this device: scanning, adding, liking, and the sorted
/// and grouped views the Library screen shows.
class LibraryController extends ChangeNotifier {
  LibraryController({required this.store, required this.scanner, this.platform = const NoopLibraryPlatform()});

  final LibraryStore store;
  final LibraryScanner scanner;
  final LibraryPlatform platform;

  List<LibraryTrack> _tracks = const [];
  List<String> _roots = const [];
  List<String> _excluded = const [];
  Set<String> _liked = <String>{};
  String _query = '';
  bool _scanning = false;
  int _found = 0;
  String? _message;

  List<LibraryTrack>? _songsCache;
  List<AlbumGroup>? _albumsCache;
  List<ArtistGroup>? _artistsCache;

  bool get isScanning => _scanning;
  int get foundSoFar => _found;
  String? get message => _message;
  String get query => _query;
  bool get hasTracks => _tracks.isNotEmpty;
  List<String> get roots => _roots;
  List<String> get excludedFolders => _excluded;
  bool isLiked(String id) => _liked.contains(id);

  List<LibraryTrack> get songs => _songsCache ??= sortedSongs(searchTracks(_tracks, _query));
  List<LibraryTrack> get likedSongs => [for (final t in songs) if (_liked.contains(t.id)) t];
  List<AlbumGroup> get albums => _albumsCache ??= albumsOf(songs);
  List<ArtistGroup> get artists => _artistsCache ??= artistsOf(songs);

  void _invalidate() {
    _songsCache = null;
    _albumsCache = null;
    _artistsCache = null;
  }

  Future<void> _persist() =>
      store.save(LibrarySnapshot(tracks: _tracks, roots: _roots, excluded: _excluded, liked: _liked));

  Future<void> load() async {
    final snapshot = await store.load();
    _tracks = snapshot.tracks;
    _roots = snapshot.roots;
    _excluded = snapshot.excluded;
    _liked = {...snapshot.liked};
    _invalidate();
    notifyListeners();
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _invalidate();
    notifyListeners();
  }

  /// Looks for new, changed and removed songs in the chosen folders (or the
  /// device's usual music folders when none were chosen).
  Future<void> scan() async {
    if (_scanning) return;
    _scanning = true;
    _found = 0;
    _message = null;
    notifyListeners();
    try {
      if (!await platform.requestAccess()) {
        _message = 'Allow access to your music to scan this device.';
        return;
      }
      final roots = _roots.isNotEmpty ? _roots : await platform.defaultRoots();
      if (roots.isEmpty) {
        _message = 'Use "Add songs" to bring music into Vyro.';
        return;
      }
      final result = await scanner.scan(
        roots: roots,
        excluded: _excluded,
        existing: _tracks,
        onProgress: (n) {
          _found = n;
          notifyListeners();
        },
      );
      _apply(result);
      await _persist();
    } catch (e) {
      _message = 'Scanning stopped: $e';
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> addFolder() async {
    final path = await platform.pickFolder();
    if (path == null || path.isEmpty) return;
    if (!_roots.contains(path)) _roots = [..._roots, path];
    await _persist();
    await scan();
  }

  Future<void> addSongs() async {
    final picked = await platform.pickSongs();
    if (picked.isEmpty) return;
    final result = await scanner.indexFiles(picked, existing: _tracks);
    _apply(result);
    await _persist();
    notifyListeners();
  }

  Future<void> removeFolder(String root) async {
    _roots = [for (final r in _roots) if (r != root) r];
    final prefix = root.toLowerCase().replaceAll('\\', '/');
    _tracks = [
      for (final t in _tracks)
        if (!t.path.toLowerCase().replaceAll('\\', '/').startsWith('$prefix/')) t,
    ];
    _invalidate();
    await _persist();
    notifyListeners();
  }

  Future<void> toggleLike(String id) async {
    if (!_liked.remove(id)) _liked.add(id);
    await _persist();
    notifyListeners();
  }

  void _apply(ScanResult result) {
    _tracks = result.tracks;
    _invalidate();
    final n = result.tracks.length;
    if (n == 0) {
      _message = 'No music found. Add a folder or songs.';
    } else {
      final extra = result.added > 0 ? ', ${result.added} new' : '';
      _message = '$n songs$extra';
    }
  }
}
