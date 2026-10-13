import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'playback_controller.dart';
import 'playback_snapshot.dart';
import 'track.dart';

/// Keeps the player's state between runs of the app.
abstract class PlaybackStore {
  Future<PlaybackSnapshot?> load();
  Future<void> save(PlaybackSnapshot snapshot);
  Future<void> clear();
}

class MemoryPlaybackStore implements PlaybackStore {
  Map<String, Object?>? _saved;
  int saves = 0;

  @override
  Future<PlaybackSnapshot?> load() async => _saved == null ? null : PlaybackSnapshot.fromJson(_saved!);

  @override
  Future<void> save(PlaybackSnapshot snapshot) async {
    saves++;
    _saved = jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>;
  }

  @override
  Future<void> clear() async => _saved = null;
}

class FilePlaybackStore implements PlaybackStore {
  FilePlaybackStore({Future<Directory> Function()? directory, this.attach}) : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  /// Gives a song read from the save back what it needs to play (see [PlaybackSnapshot.fromJson]).
  final Track Function(Track)? attach;
  Future<void> _chain = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _chain.then((_) => job());
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<File> _file() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}playback_state.json');
  }

  @override
  Future<PlaybackSnapshot?> load() => _serial(() async {
        final f = await _file();
        if (!await f.exists()) return null;
        try {
          return PlaybackSnapshot.fromJson((jsonDecode(await f.readAsString()) as Map).cast<String, Object?>(), attach: attach);
        } catch (_) {
          return null; // a damaged save is ignored; the player simply starts empty
        }
      });

  @override
  Future<void> save(PlaybackSnapshot snapshot) => _serial(() async {
        final f = await _file();
        final temp = File('${f.path}.tmp');
        await temp.writeAsString(jsonEncode(snapshot.toJson()));
        await temp.rename(f.path); // write then rename, so a crash never leaves half a file
      });

  @override
  Future<void> clear() => _serial(() async {
        final f = await _file();
        if (await f.exists()) await f.delete();
      });
}

/// Saves the player's state shortly after it changes, regularly while a song plays, and when the app goes to the
/// background, so the next start can continue exactly where this one stopped.
class PlaybackPersistor with WidgetsBindingObserver {
  PlaybackPersistor({required this.controller, required this.store, this.every = const Duration(seconds: 5), this.settle = const Duration(milliseconds: 800)});

  final PlaybackController controller;
  final PlaybackStore store;
  final Duration every;
  final Duration settle;
  Timer? _ticker;
  Timer? _debounce;

  void start() {
    controller.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(every, (_) {
      if (controller.isPlaying) unawaited(flush());
    });
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(settle, () => unawaited(flush()));
  }

  Future<void> flush() async {
    try {
      final snapshot = controller.snapshot();
      if (snapshot.queue.isEmpty) {
        await store.clear();
      } else {
        await store.save(snapshot);
      }
    } catch (_) {
      // Remembering the queue is a convenience; it must never get in the way of playing.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(flush());
  }

  void dispose() {
    controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _debounce?.cancel();
  }
}
