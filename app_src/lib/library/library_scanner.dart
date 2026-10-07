import 'dart:io';
import 'dart:math' as math;

import 'library_models.dart';

/// Reads tags for several files at once (runs off the main thread in the app).
typedef TagBatchReader = Future<List<TagInfo?>> Function(List<String> paths);

const supportedAudioExtensions = <String>{'.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.aif', '.aiff'};

class ScanResult {
  const ScanResult({
    required this.tracks,
    required this.added,
    required this.updated,
    required this.removed,
    required this.skippedShort,
  });

  final List<LibraryTrack> tracks;
  final int added;
  final int updated;
  final int removed;
  final int skippedShort;
}

class _Candidate {
  _Candidate(this.path, this.size, this.modifiedMs);
  final String path;
  final int size;
  final int modifiedMs;
}

/// Finds audio files and turns them into [LibraryTrack]s.
///
/// Rescans are incremental (LIB-01): a file whose size and modified time did
/// not change is not read again.
class LibraryScanner {
  LibraryScanner({
    required this.readTags,
    this.minDuration = const Duration(seconds: 30),
    this.batchSize = 40,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TagBatchReader readTags;

  /// Clips shorter than this (voice notes, ringtones) are left out (LIB-05).
  final Duration minDuration;
  final int batchSize;
  final DateTime Function() _clock;

  /// Walks [roots] recursively. Hidden folders and [excluded] folders are skipped.
  Future<ScanResult> scan({
    required List<String> roots,
    List<String> excluded = const [],
    List<LibraryTrack> existing = const [],
    void Function(int found)? onProgress,
  }) async {
    final candidates = <_Candidate>[];
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      final stream = dir.list(recursive: true, followLinks: false).handleError(
            (Object _) {},
            test: (e) => e is FileSystemException,
          );
      await for (final entity in stream) {
        if (entity is! File) continue;
        final path = entity.path;
        if (!_isAudio(path) || _isHidden(path, root) || _isUnder(path, excluded)) continue;
        try {
          final stat = await entity.stat();
          candidates.add(_Candidate(path, stat.size, stat.modified.millisecondsSinceEpoch));
        } on FileSystemException {
          continue;
        }
        if (candidates.length % 25 == 0) onProgress?.call(candidates.length);
      }
    }
    onProgress?.call(candidates.length);
    return _build(candidates, existing, roots);
  }

  /// Adds individual files (for example songs the user picked).
  Future<ScanResult> indexFiles(List<String> paths, {List<LibraryTrack> existing = const []}) async {
    final candidates = <_Candidate>[];
    for (final path in paths) {
      final file = File(path);
      if (!_isAudio(path) || !await file.exists()) continue;
      final stat = await file.stat();
      candidates.add(_Candidate(path, stat.size, stat.modified.millisecondsSinceEpoch));
    }
    return _build(candidates, existing, const []);
  }

  Future<ScanResult> _build(List<_Candidate> candidates, List<LibraryTrack> existing, List<String> roots) async {
    final byPath = {for (final t in existing) t.path: t};
    final unique = {for (final c in candidates) c.path: c}.values.toList();

    final kept = <String, LibraryTrack>{};
    final toRead = <_Candidate>[];
    for (final c in unique) {
      final old = byPath[c.path];
      if (old != null && old.sizeBytes == c.size && old.modifiedMs == c.modifiedMs) {
        kept[c.path] = old;
      } else {
        toRead.add(c);
      }
    }

    var added = 0;
    var updated = 0;
    var skipped = 0;
    for (var i = 0; i < toRead.length; i += batchSize) {
      final chunk = toRead.sublist(i, math.min(i + batchSize, toRead.length));
      List<TagInfo?> tags;
      try {
        tags = await readTags([for (final c in chunk) c.path]);
      } catch (_) {
        tags = List<TagInfo?>.filled(chunk.length, null);
      }
      for (var j = 0; j < chunk.length; j++) {
        final c = chunk[j];
        final tag = j < tags.length ? tags[j] : null;
        final duration = tag?.duration;
        if (duration != null && duration < minDuration) {
          skipped++;
          continue;
        }
        final old = byPath[c.path];
        kept[c.path] = _toTrack(c, tag, addedMs: old?.addedMs ?? _clock().millisecondsSinceEpoch);
        if (old == null) {
          added++;
        } else {
          updated++;
        }
      }
    }

    // Songs we knew before but did not see now: gone if they sit inside a scanned
    // folder; songs added one by one are kept as long as their file still exists.
    var removed = 0;
    for (final old in existing) {
      if (kept.containsKey(old.path)) continue;
      if (!_isUnder(old.path, roots) && await File(old.path).exists()) {
        kept[old.path] = old;
      } else {
        removed++;
      }
    }

    return ScanResult(tracks: kept.values.toList(), added: added, updated: updated, removed: removed, skippedShort: skipped);
  }

  LibraryTrack _toTrack(_Candidate c, TagInfo? tag, {required int addedMs}) {
    final file = c.path.split(RegExp(r'[\\/]')).last;
    return LibraryTrack(
      id: 'local:${c.path}',
      path: c.path,
      title: tag?.title ?? _titleFromFile(file),
      artist: tag?.artist ?? 'Unknown artist',
      album: tag?.album ?? 'Unknown album',
      genre: tag?.genre ?? 'Unknown genre',
      durationMs: tag?.duration?.inMilliseconds ?? 0,
      trackNumber: tag?.trackNumber ?? 0,
      year: tag?.year ?? 0,
      sizeBytes: c.size,
      modifiedMs: c.modifiedMs,
      addedMs: addedMs,
    );
  }

  static bool _isAudio(String path) {
    final dot = path.lastIndexOf('.');
    return dot >= 0 && supportedAudioExtensions.contains(path.substring(dot).toLowerCase());
  }

  /// A folder or file whose name starts with a dot (for example .thumbnails, .trash).
  static bool _isHidden(String path, String root) {
    final relative = path.startsWith(root) ? path.substring(root.length) : path;
    return relative.split(RegExp(r'[\\/]')).any((s) => s.length > 1 && s.startsWith('.'));
  }

  static String _norm(String p) => p.toLowerCase().replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');

  static bool _isUnder(String path, List<String> folders) {
    final p = _norm(path);
    for (final f in folders) {
      final r = _norm(f);
      if (r.isNotEmpty && (p == r || p.startsWith('$r/'))) return true;
    }
    return false;
  }

  /// "01 - Song_Name.mp3" becomes "Song Name".
  static String _titleFromFile(String file) {
    final dot = file.lastIndexOf('.');
    var name = dot > 0 ? file.substring(0, dot) : file;
    name = name.replaceFirst(RegExp(r'^\d{1,3}\s*[-._]\s*'), '').replaceAll('_', ' ').trim();
    return name.isEmpty ? file : name;
  }
}
