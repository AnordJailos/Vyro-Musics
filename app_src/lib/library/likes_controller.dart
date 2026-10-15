import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/track.dart';
import '../auth/api_errors.dart';
import '../catalog/catalog_api.dart';
import 'library_controller.dart';
import 'likes_store.dart';

/// Likes for any song, wherever it comes from: songs on the device (kept in the library) and songs on Vyro (kept on
/// the device, and saved on the server for signed-in people so likes follow them to another device).
class LikesController extends ChangeNotifier {
  LikesController({required this.library, required this.store, required this.catalog, this.canSync, this.attach}) {
    library.addListener(notifyListeners);
  }

  final LibraryController library;
  final LikesStore store;
  final CatalogApi catalog;

  /// Whether the server can be reached on behalf of a signed-in person right now.
  final bool Function()? canSync;
  final Track Function(Track)? attach;

  Map<String, Track> _online = {};
  Set<String> _pendingSave = {};
  Set<String> _pendingUnsave = {};
  bool _syncing = false;

  Future<void> load() async {
    final s = await store.load(attach: attach);
    _online = {for (final t in s.tracks) t.id: t};
    _pendingSave = {...s.pendingSave};
    _pendingUnsave = {...s.pendingUnsave};
    notifyListeners();
  }

  @override
  void dispose() {
    library.removeListener(notifyListeners);
    super.dispose();
  }

  bool isLiked(Track track) => track.source == TrackSource.local ? library.isLiked(track.id) : _online.containsKey(track.id);

  /// Every liked song, from both sources, by title.
  List<Track> get tracks {
    final all = [for (final t in library.likedSongs) t.toPlayable(), ..._online.values];
    all.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return all;
  }

  Future<void> toggle(Track track) async {
    if (track.source == TrackSource.local) {
      await library.toggleLike(track.id);
      return;
    }
    final id = track.id;
    if (_online.remove(id) != null) {
      if (!_pendingSave.remove(id)) _pendingUnsave.add(id); // never reached the server? then there is nothing to undo there
    } else {
      _online[id] = track;
      if (!_pendingUnsave.remove(id)) _pendingSave.add(id);
    }
    await _persist();
    notifyListeners();
    unawaited(sync());
  }

  Future<void> _persist() => store.save(LikesSnapshot(tracks: _online.values.toList(), pendingSave: _pendingSave, pendingUnsave: _pendingUnsave));

  String _serverId(String id) => id.startsWith('vyro:') ? id.substring(5) : id;

  /// Sends what is waiting, then takes the server's list as the truth (keeping what is still waiting). Without a
  /// connection or a login nothing happens, and everything is sent later.
  Future<void> sync() async {
    if (_syncing || !(canSync?.call() ?? false)) return;
    _syncing = true;
    try {
      for (final id in _pendingSave.toList()) {
        await catalog.saveTrack(_serverId(id));
        _pendingSave.remove(id);
      }
      for (final id in _pendingUnsave.toList()) {
        await catalog.unsaveTrack(_serverId(id));
        _pendingUnsave.remove(id);
      }
      final remote = await catalog.savedTracks();
      final merged = <String, Track>{for (final c in remote) 'vyro:${c.id}': c.toPlayable(catalog.streamUri)};
      for (final id in _pendingSave) {
        final mine = _online[id];
        if (mine != null) merged[id] = mine; // liked while the list was being fetched
      }
      for (final id in _pendingUnsave) {
        merged.remove(id);
      }
      _online = merged;
      await _persist();
      notifyListeners();
    } on ApiException {
      await _persist(); // whatever was sent is no longer waiting; the rest is tried again next time
    } finally {
      _syncing = false;
    }
  }
}
