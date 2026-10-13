import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'library_models.dart';

class LibrarySnapshot {
  const LibrarySnapshot({
    this.tracks = const [],
    this.roots = const [],
    this.excluded = const [],
    this.liked = const <String>{},
  });

  final List<LibraryTrack> tracks;
  final List<String> roots;
  final List<String> excluded;
  final Set<String> liked;

  Map<String, Object?> toJson() => {
        'version': 1,
        'roots': roots,
        'excluded': excluded,
        'liked': liked.toList(),
        'tracks': [for (final t in tracks) t.toJson()],
      };

  factory LibrarySnapshot.fromJson(Map<String, Object?> json) => LibrarySnapshot(
        roots: [for (final r in (json['roots'] as List? ?? const [])) r as String],
        excluded: [for (final r in (json['excluded'] as List? ?? const [])) r as String],
        liked: {for (final l in (json['liked'] as List? ?? const [])) l as String},
        tracks: [
          for (final t in (json['tracks'] as List? ?? const [])) LibraryTrack.fromJson((t as Map).cast<String, Object?>()),
        ],
      );
}

abstract class LibraryStore {
  Future<LibrarySnapshot> load();
  Future<void> save(LibrarySnapshot snapshot);
}

class MemoryLibraryStore implements LibraryStore {
  MemoryLibraryStore([this.snapshot = const LibrarySnapshot()]);

  LibrarySnapshot snapshot;

  @override
  Future<LibrarySnapshot> load() async => snapshot;

  @override
  Future<void> save(LibrarySnapshot snapshot) async => this.snapshot = snapshot;
}

/// Keeps the library in one JSON file in the app's private folder.
class JsonLibraryStore implements LibraryStore {
  JsonLibraryStore({Future<Directory> Function()? directory}) : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}library.json');
  }

  @override
  Future<LibrarySnapshot> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const LibrarySnapshot();
      final decoded = jsonDecode(await file.readAsString());
      return LibrarySnapshot.fromJson((decoded as Map).cast<String, Object?>());
    } catch (_) {
      return const LibrarySnapshot(); // damaged file: start fresh, a rescan rebuilds it
    }
  }

  @override
  Future<void> save(LibrarySnapshot snapshot) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(snapshot.toJson()));
    await temp.rename(file.path); // write then rename, so a crash never leaves half a file
  }
}
