import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../audio/playback_snapshot.dart' show trackFromJson, trackToJson;
import '../audio/track.dart';

/// Liked songs from Vyro, kept on the device, with the likes and unlikes that still have to reach the server.
class LikesSnapshot {
  const LikesSnapshot({this.tracks = const [], this.pendingSave = const {}, this.pendingUnsave = const {}});

  final List<Track> tracks;
  final Set<String> pendingSave;
  final Set<String> pendingUnsave;

  Map<String, Object?> toJson() => {
        'version': 1,
        'tracks': [for (final t in tracks) trackToJson(t)],
        'pendingSave': pendingSave.toList(),
        'pendingUnsave': pendingUnsave.toList(),
      };

  factory LikesSnapshot.fromJson(Map<String, Object?> j, {Track Function(Track)? attach}) => LikesSnapshot(
        tracks: [
          for (final t in (j['tracks'] as List? ?? const [])) () {
            final track = trackFromJson((t as Map).cast<String, Object?>());
            return attach == null ? track : attach(track);
          }(),
        ],
        pendingSave: {for (final i in (j['pendingSave'] as List? ?? const [])) i as String},
        pendingUnsave: {for (final i in (j['pendingUnsave'] as List? ?? const [])) i as String},
      );
}

abstract class LikesStore {
  Future<LikesSnapshot> load({Track Function(Track)? attach});
  Future<void> save(LikesSnapshot snapshot);
}

class MemoryLikesStore implements LikesStore {
  String? _json;
  int saves = 0;

  @override
  Future<LikesSnapshot> load({Track Function(Track)? attach}) async => _json == null ? const LikesSnapshot() : LikesSnapshot.fromJson((jsonDecode(_json!) as Map).cast<String, Object?>(), attach: attach);

  @override
  Future<void> save(LikesSnapshot snapshot) async {
    saves++;
    _json = jsonEncode(snapshot.toJson());
  }
}

class FileLikesStore implements LikesStore {
  FileLikesStore({Future<Directory> Function()? directory}) : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  Future<void> _chain = Future<void>.value();

  Future<File> _file() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}liked_online.json');
  }

  @override
  Future<LikesSnapshot> load({Track Function(Track)? attach}) async {
    final f = await _file();
    if (!await f.exists()) return const LikesSnapshot();
    try {
      return LikesSnapshot.fromJson((jsonDecode(await f.readAsString()) as Map).cast<String, Object?>(), attach: attach);
    } catch (_) {
      return const LikesSnapshot(); // a damaged file is ignored rather than stopping the app
    }
  }

  @override
  Future<void> save(LikesSnapshot snapshot) {
    final run = _chain.then((_) async {
      final f = await _file();
      final temp = File('${f.path}.tmp');
      await temp.writeAsString(jsonEncode(snapshot.toJson()));
      await temp.rename(f.path); // write then rename, so a crash never leaves half a file
    });
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }
}
