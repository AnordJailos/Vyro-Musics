import 'dart:io';

import 'package:flutter/foundation.dart';

import 'library_index.dart';
import 'library_models.dart';
import 'library_platform.dart';
import 'library_scanner.dart';
import 'library_store.dart';

/// The music found on this device: scanning, adding, liking, and the sorted
/// and grouped views the Library screen shows.
class LibraryController extends ChangeNotifier {
  LibraryController({required this.store, required this.scanner, this.platform = const NoopLibraryPlatform(), this.deleteFile = deleteFileFromDisk});

  final LibraryStore store;
  final LibraryScanner scanner;
  final LibraryPlatform platform;

  /// Removes a file from the device. Replaced in tests.
  final Future<void> Function(String path) deleteFile;

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
  List<GenreGroup>? _genresCache;
  List<FolderGroup>? _foldersCache;
  int _minSeconds = 30;

  bool get isScanning => _scanning;
  int get foundSoFar => _found;
  String? get message => _message;
  String get query => _query;
  bool get hasTracks => _tracks.isNotEmpty;

  /// Every song, ignoring the Library tab's own search box.
  List<LibraryTrack> get allTracks => _tracks;
  List<String> get roots => _roots;
  List<String> get excludedFolders => _excluded;
  bool isLiked(String id) => _liked.contains(id);

  List<LibraryTrack> get songs => _songsCache ??= sortedSongs(searchTracks(_tracks, _query));
  List<LibraryTrack> get likedSongs => [for (final t in songs) if (_liked.contains(t.id)) t];
  List<AlbumGroup> get albums => _albumsCache ??= albumsOf(songs);
  List<ArtistGroup> get artists => _artistsCache ??= artistsOf(songs);
  List<GenreGroup> get genres => _genresCache ??= genresOf(songs);
  List<FolderGroup> get folders => _foldersCache ??= foldersOf(songs);

  /// Songs shorter than this many seconds are left out (0 keeps everything).
  int get minSeconds => _minSeconds;

  void _invalidate() {
    _songsCache = null;
    _albumsCache = null;
    _artistsCache = null;
    _genresCache = null;
    _foldersCache = null;
  }

  Future<void> _persist() =>
      store.save(LibrarySnapshot(tracks: _tracks, roots: _roots, excluded: _excluded, liked: _liked, minSeconds: _minSeconds));

  Future<void> load() async {
    final snapshot = await store.load();
    _tracks = snapshot.tracks;
    _roots = snapshot.roots;
    _excluded = snapshot.excluded;
    _liked = {...snapshot.liked};
    _minSeconds = snapshot.minSeconds;
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
        minDuration: Duration(seconds: _minSeconds),
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

  static String _norm(String path) => path.toLowerCase().replaceAll('\\', '/');

  bool _under(String path, String folder) => _norm(path).startsWith('${_norm(folder)}/');

  Future<void> removeFolder(String root) async {
    _roots = [for (final r in _roots) if (r != root) r];
    _tracks = [for (final t in _tracks) if (!_under(t.path, root)) t];
    _invalidate();
    await _persist();
    notifyListeners();
  }

  /// Leaves a folder out of the library (for example a folder of voice notes). Its songs go at once, and stay out
  /// when the device is scanned again.
  Future<void> addExcludedFolder() async {
    final path = await platform.pickFolder();
    if (path == null || path.isEmpty) return;
    if (!_excluded.contains(path)) _excluded = [..._excluded, path];
    _tracks = [for (final t in _tracks) if (!_under(t.path, path)) t];
    _invalidate();
    await _persist();
    notifyListeners();
  }

  /// Takes a folder off the excluded list and looks for its songs again.
  Future<void> removeExcludedFolder(String path) async {
    _excluded = [for (final e in _excluded) if (e != path) e];
    await _persist();
    notifyListeners();
    await scan();
  }

  /// Changes how short a song can be and still be kept. Shorter songs go at once; with a lower limit the device is
  /// scanned again, to bring back what was left out before.
  Future<void> setMinSeconds(int seconds) async {
    if (seconds == _minSeconds) return;
    final lower = seconds < _minSeconds;
    _minSeconds = seconds;
    if (seconds > 0) _tracks = [for (final t in _tracks) if (t.durationMs == 0 || t.durationMs >= seconds * 1000) t];
    _invalidate();
    await _persist();
    notifyListeners();
    if (lower) await scan();
  }

  /// Deletes the file from the device for good, and takes the song out of the library. Returns false (and keeps the
  /// song) when the file cannot be deleted, for example because another app is using it or the system protects it.
  Future<bool> deleteTrack(LibraryTrack track) async {
    try {
      await deleteFile(track.path);
    } catch (_) {
      _message = 'Could not delete "${track.title}". It may be in use or protected.';
      notifyListeners();
      return false;
    }
    _tracks = [for (final t in _tracks) if (t.id != track.id) t];
    _liked.remove(track.id);
    _invalidate();
    _message = 'Deleted "${track.title}".';
    await _persist();
    notifyListeners();
    return true;
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

/// Deletes a file; a file that is already gone counts as deleted.
Future<void> deleteFileFromDisk(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
