import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../audio/track.dart';
import 'playlist_models.dart';

/// Where playlists are kept on the device.
abstract class PlaylistStore {
  Future<List<Playlist>> load({Track Function(Track)? attach});
  Future<void> save(List<Playlist> playlists);

  /// Keeps a cover picture and returns where it is.
  Future<String> saveCover(String playlistId, List<int> bytes, String extension);
  Future<void> deleteCover(String path);
}

class MemoryPlaylistStore implements PlaylistStore {
  String? _json;
  final Map<String, List<int>> covers = {};
  int saves = 0;

  @override
  Future<List<Playlist>> load({Track Function(Track)? attach}) async {
    if (_json == null) return [];
    return [for (final p in (jsonDecode(_json!) as List)) Playlist.fromJson((p as Map).cast<String, Object?>(), attach: attach)];
  }

  @override
  Future<void> save(List<Playlist> playlists) async {
    saves++;
    _json = jsonEncode([for (final p in playlists) p.toJson()]);
  }

  @override
  Future<String> saveCover(String playlistId, List<int> bytes, String extension) async {
    final path = 'memory://covers/$playlistId-${covers.length}.$extension';
    covers[path] = bytes;
    return path;
  }

  @override
  Future<void> deleteCover(String path) async => covers.remove(path);
}

class FilePlaylistStore implements PlaylistStore {
  FilePlaylistStore({Future<Directory> Function()? directory}) : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}playlists.json');
  }

  @override
  Future<List<Playlist>> load({Track Function(Track)? attach}) async {
    final f = await _file();
    if (!await f.exists()) return [];
    try {
      return [for (final p in (jsonDecode(await f.readAsString()) as List)) Playlist.fromJson((p as Map).cast<String, Object?>(), attach: attach)];
    } catch (_) {
      return []; // a damaged file is ignored rather than stopping the app
    }
  }

  @override
  Future<void> save(List<Playlist> playlists) async {
    final f = await _file();
    final temp = File('${f.path}.tmp');
    await temp.writeAsString(jsonEncode([for (final p in playlists) p.toJson()]));
    await temp.rename(f.path); // write then rename, so a crash never leaves half a file
  }

  @override
  Future<String> saveCover(String playlistId, List<int> bytes, String extension) async {
    final dir = Directory('${(await _directory()).path}${Platform.pathSeparator}playlist_covers');
    await dir.create(recursive: true);
    // A new name each time, so a changed cover is not shown from the picture cache.
    final file = File('${dir.path}${Platform.pathSeparator}$playlistId-${DateTime.now().microsecondsSinceEpoch}.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> deleteCover(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
