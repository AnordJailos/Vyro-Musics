import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/track.dart';
import '../history/play_record.dart' show newUuid;
import '../studio/studio_models.dart';
import 'playlist_models.dart';
import 'playlist_store.dart';

class AddResult {
  const AddResult({required this.added, required this.duplicates});

  /// Songs put in the playlist.
  final int added;

  /// Songs left out because the playlist already had them.
  final int duplicates;
}

const maxPlaylistName = 100;
const maxPlaylistDescription = 300;
const maxCoverBytes = 5 * 1024 * 1024;

/// The person's playlists: made on this device, from songs on the device and songs on Vyro.
class PlaylistsController extends ChangeNotifier {
  PlaylistsController({required this.store, this.attach, DateTime Function()? clock, String Function()? newId})
      : _clock = clock ?? DateTime.now,
        _newId = newId ?? newUuid;

  final PlaylistStore store;

  /// Gives a song read from the save what it needs to play (for Vyro songs, a way to ask for a fresh address).
  final Track Function(Track)? attach;
  final DateTime Function() _clock;
  final String Function() _newId;
  List<Playlist> _playlists = const [];
  Future<void> _chain = Future<void>.value();

  /// Most recently changed first.
  List<Playlist> get playlists => _playlists;

  Playlist? byId(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The playlists that already have this song.
  List<Playlist> containing(String trackId) => [for (final p in _playlists) if (p.contains(trackId)) p];

  Future<void> load() async {
    _playlists = _sorted(await store.load(attach: attach));
    notifyListeners();
  }

  List<Playlist> _sorted(List<Playlist> list) => List.of(list)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _commit(Playlist changed) {
    final others = [for (final p in _playlists) if (p.id != changed.id) p];
    _playlists = _sorted([...others, changed.copyWith(updatedAt: _clock())]);
    return _persist();
  }

  Future<void> _persist() {
    notifyListeners();
    final run = _chain.then((_) => store.save(_playlists));
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Playlist _need(String id) => byId(id) ?? (throw StateError('There is no playlist $id'));

  String _cleanName(String name) {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('A playlist needs a name.');
    return n.length > maxPlaylistName ? n.substring(0, maxPlaylistName) : n;
  }

  String _cleanDescription(String text) {
    final d = text.trim();
    return d.length > maxPlaylistDescription ? d.substring(0, maxPlaylistDescription) : d;
  }

  Future<Playlist> create(String name, {String description = ''}) async {
    final now = _clock();
    final playlist = Playlist(id: _newId(), name: _cleanName(name), description: _cleanDescription(description), createdAt: now, updatedAt: now);
    _playlists = _sorted([..._playlists, playlist]);
    await _persist();
    return playlist;
  }

  Future<void> update(String id, {String? name, String? description}) =>
      _commit(_need(id).copyWith(name: name == null ? null : _cleanName(name), description: description == null ? null : _cleanDescription(description)));

  Future<void> delete(String id) async {
    final gone = byId(id);
    if (gone == null) return;
    _playlists = [for (final p in _playlists) if (p.id != id) p];
    await _persist();
    if (gone.coverPath != null) await store.deleteCover(gone.coverPath!);
  }

  /// Uses a picture as the cover. Pictures over 5 MB are refused with a [FormatException].
  Future<void> setCover(String id, PickedFile file) async {
    if (file.length > maxCoverBytes) throw const FormatException('That picture is too large. Choose one under 5 MB.');
    final bytes = <int>[];
    await for (final chunk in file.open()) {
      bytes.addAll(chunk);
      if (bytes.length > maxCoverBytes) throw const FormatException('That picture is too large. Choose one under 5 MB.');
    }
    final dot = file.name.lastIndexOf('.');
    final ext = dot < 0 ? 'jpg' : file.name.substring(dot + 1).toLowerCase();
    final playlist = _need(id);
    final path = await store.saveCover(id, bytes, ext);
    final old = playlist.coverPath;
    await _commit(playlist.copyWith(coverPath: path));
    if (old != null) await store.deleteCover(old);
  }

  Future<void> removeCover(String id) async {
    final playlist = _need(id);
    final old = playlist.coverPath;
    if (old == null) return;
    await _commit(playlist.copyWith(coverPath: null));
    await store.deleteCover(old);
  }

  /// Adds songs to the end. Songs the playlist already has are left out unless [allowDuplicates].
  Future<AddResult> addTracks(String id, List<Track> tracks, {bool allowDuplicates = false}) async {
    final playlist = _need(id);
    final have = {for (final e in playlist.entries) e.track.id};
    final now = _clock();
    final added = <PlaylistEntry>[];
    var duplicates = 0;
    for (final t in tracks) {
      if (!allowDuplicates && have.contains(t.id)) {
        duplicates++;
        continue;
      }
      have.add(t.id);
      added.add(PlaylistEntry(id: _newId(), track: t, addedAt: now));
    }
    if (added.isNotEmpty) await _commit(playlist.copyWith(entries: [...playlist.entries, ...added]));
    return AddResult(added: added.length, duplicates: duplicates);
  }

  Future<void> removeEntries(String id, Set<String> entryIds) {
    final playlist = _need(id);
    return _commit(playlist.copyWith(entries: [for (final e in playlist.entries) if (!entryIds.contains(e.id)) e]));
  }

  /// Moves a song to another place in the playlist ([to] is its new index).
  Future<void> moveEntry(String id, int from, int to) async {
    final playlist = _need(id);
    final n = playlist.entries.length;
    if (from < 0 || to < 0 || from >= n || to >= n || from == to) return;
    final list = [...playlist.entries];
    list.insert(to, list.removeAt(from));
    await _commit(playlist.copyWith(entries: list));
  }

  /// Puts the songs in order for good (the new order is kept).
  Future<void> sortBy(String id, PlaylistSort key, {bool ascending = true}) {
    final playlist = _need(id);
    final indexed = [for (var i = 0; i < playlist.entries.length; i++) (i, playlist.entries[i])];
    int compare(PlaylistEntry a, PlaylistEntry b) => switch (key) {
          PlaylistSort.title => a.track.title.toLowerCase().compareTo(b.track.title.toLowerCase()),
          PlaylistSort.artist => a.track.artist.toLowerCase().compareTo(b.track.artist.toLowerCase()),
          PlaylistSort.dateAdded => a.addedAt.compareTo(b.addedAt),
          PlaylistSort.duration => (a.track.duration ?? Duration.zero).compareTo(b.track.duration ?? Duration.zero),
        };
    indexed.sort((x, y) {
      final c = compare(x.$2, y.$2);
      return c != 0 ? (ascending ? c : -c) : x.$1.compareTo(y.$1); // equal songs keep their order
    });
    return _commit(playlist.copyWith(entries: [for (final x in indexed) x.$2]));
  }

  /// Keeps the first copy of every song. Returns how many were taken out.
  Future<int> removeDuplicates(String id) async {
    final playlist = _need(id);
    final seen = <String>{};
    final kept = [for (final e in playlist.entries) if (seen.add(e.track.id)) e];
    final removed = playlist.entries.length - kept.length;
    if (removed > 0) await _commit(playlist.copyWith(entries: kept));
    return removed;
  }
}
