import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/library/library_models.dart';
import 'package:vyro_music/library/library_scanner.dart';

import 'library_fixtures.dart';

void main() {
  late Directory root;
  late FakeTagReader reader;

  LibraryScanner scanner() => LibraryScanner(readTags: reader.call, clock: () => DateTime.utc(2026, 10, 6));

  setUp(() {
    root = Directory.systemTemp.createTempSync('vyro_scan_');
    reader = FakeTagReader();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('finds audio files and skips other files, hidden folders and excluded folders', () async {
    makeAudio(root, 'a.mp3');
    makeAudio(root, 'sub/02 - Second_Song.flac');
    makeAudio(root, '.hidden/c.mp3');
    makeAudio(root, 'skip/d.mp3');
    File('${root.path}/notes.txt').writeAsStringSync('hello');
    reader.byFileName['a.mp3'] = const TagInfo(title: 'Alpha', artist: 'Ann', album: 'First', duration: Duration(minutes: 3));

    final result = await scanner().scan(roots: [root.path], excluded: ['${root.path}/skip']);

    expect(result.tracks.map((t) => t.title).toSet(), {'Alpha', 'Second Song'});
    expect(result.added, 2);
    final flac = result.tracks.firstWhere((t) => t.title == 'Second Song');
    expect(flac.artist, 'Unknown artist'); // no tags, so file name and defaults are used
    expect(result.tracks.firstWhere((t) => t.title == 'Alpha').artist, 'Ann');
  });

  test('does not read unchanged files again, but reads changed ones', () async {
    final a = makeAudio(root, 'a.mp3');
    makeAudio(root, 'b.mp3');
    final first = await scanner().scan(roots: [root.path]);
    expect(reader.reads, 2);

    final again = await scanner().scan(roots: [root.path], existing: first.tracks);
    expect(reader.reads, 2);
    expect(again.added, 0);
    expect(again.tracks.length, 2);

    a.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));
    final changed = await scanner().scan(roots: [root.path], existing: again.tracks);
    expect(reader.reads, 3);
    expect(changed.updated, 1);
  });

  test('removes songs whose file disappeared', () async {
    final a = makeAudio(root, 'a.mp3');
    makeAudio(root, 'b.mp3');
    final first = await scanner().scan(roots: [root.path]);
    a.deleteSync();
    final second = await scanner().scan(roots: [root.path], existing: first.tracks);
    expect(second.removed, 1);
    expect(second.tracks.map((t) => t.title), ['b']);
  });

  test('leaves out very short clips such as voice notes', () async {
    makeAudio(root, 'voice.mp3');
    makeAudio(root, 'song.mp3');
    reader.byFileName['voice.mp3'] = const TagInfo(duration: Duration(seconds: 5));
    reader.byFileName['song.mp3'] = const TagInfo(duration: Duration(minutes: 3));
    final result = await scanner().scan(roots: [root.path]);
    expect(result.skippedShort, 1);
    expect(result.tracks.map((t) => t.title), ['song']);
  });

  test('songs added one by one survive a folder scan while their file exists', () async {
    final other = Directory.systemTemp.createTempSync('vyro_other_');
    addTearDown(() => other.deleteSync(recursive: true));
    final picked = makeAudio(other, 'picked.mp3');
    makeAudio(root, 'a.mp3');

    final imported = await scanner().indexFiles([picked.path]);
    expect(imported.tracks.length, 1);

    final scanned = await scanner().scan(roots: [root.path], existing: imported.tracks);
    expect(scanned.tracks.map((t) => t.title).toSet(), {'picked', 'a'});

    picked.deleteSync();
    final later = await scanner().scan(roots: [root.path], existing: scanned.tracks);
    expect(later.tracks.map((t) => t.title), ['a']);
  });
}
