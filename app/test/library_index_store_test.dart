import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/library/library_index.dart';
import 'package:vyro_music/library/library_store.dart';

import 'library_fixtures.dart';

void main() {
  test('songs sort by title ignoring letter case', () {
    final sorted = sortedSongs([libTrack('beta'), libTrack('Alpha'), libTrack('Gamma')]);
    expect(sorted.map((t) => t.title), ['Alpha', 'beta', 'Gamma']);
  });

  test('search needs every typed word to match title, artist or album', () {
    final all = [libTrack('Sunrise', artist: 'Ann'), libTrack('Sunset', artist: 'Bob'), libTrack('Moon', artist: 'Ann Lee')];
    expect(searchTracks(all, 'sun').length, 2);
    expect(searchTracks(all, 'sun ann').map((t) => t.title), ['Sunrise']);
    expect(searchTracks(all, '  ').length, 3);
    expect(searchTracks(all, 'zzz'), isEmpty);
  });

  test('albums group songs, order them by track number and name the artist', () {
    final albums = albumsOf([
      libTrack('Two', artist: 'Ann', album: 'First', number: 2),
      libTrack('One', artist: 'Ann', album: 'First', number: 1),
      libTrack('Mix A', artist: 'Ann', album: 'Compilation'),
      libTrack('Mix B', artist: 'Bob', album: 'compilation'),
    ]);
    expect(albums.map((a) => a.name), ['Compilation', 'First']);
    expect(albums.first.artist, 'Various artists');
    expect(albums.last.tracks.map((t) => t.title), ['One', 'Two']);
    expect(albums.last.artist, 'Ann');
  });

  test('artists group songs regardless of letter case', () {
    final artists = artistsOf([libTrack('B', artist: 'ann'), libTrack('A', artist: 'Ann'), libTrack('C', artist: 'Bob')]);
    expect(artists.length, 2);
    expect(artists.first.tracks.map((t) => t.title), ['A', 'B']);
  });

  test('a local song is playable and mixable', () {
    final playable = libTrack('Alpha').toPlayable();
    expect(playable.source, TrackSource.local);
    expect(playable.mixable, isTrue);
    expect(playable.duration, const Duration(minutes: 3));
  });

  group('JsonLibraryStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vyro_store_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('saves and loads tracks, folders and liked songs', () async {
      final store = JsonLibraryStore(directory: () async => dir);
      final track = libTrack('Alpha');
      await store.save(LibrarySnapshot(tracks: [track], roots: ['/music'], excluded: ['/music/skip'], liked: {track.id}));

      final loaded = await JsonLibraryStore(directory: () async => dir).load();
      expect(loaded.tracks.single.title, 'Alpha');
      expect(loaded.roots, ['/music']);
      expect(loaded.excluded, ['/music/skip']);
      expect(loaded.liked, {track.id});
    });

    test('a damaged file gives an empty library instead of a crash', () async {
      File('${dir.path}/library.json').writeAsStringSync('{ not json');
      final loaded = await JsonLibraryStore(directory: () async => dir).load();
      expect(loaded.tracks, isEmpty);
    });

    test('loading before anything was saved gives an empty library', () async {
      final loaded = await JsonLibraryStore(directory: () async => dir).load();
      expect(loaded.tracks, isEmpty);
    });
  });
}
