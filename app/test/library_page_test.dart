import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/library/library_controller.dart';
import 'package:vyro_music/library/library_page.dart';
import 'package:vyro_music/library/library_scanner.dart';
import 'package:vyro_music/library/library_store.dart';

import 'fakes.dart';
import 'library_fixtures.dart';

LibraryController _library(LibrarySnapshot snapshot) =>
    LibraryController(store: MemoryLibraryStore(snapshot), scanner: LibraryScanner(readTags: FakeTagReader().call));

Widget _host(LibraryController library, PlaybackController playback) =>
    MaterialApp(home: Scaffold(body: LibraryPage(library: library, playback: playback)));

void main() {
  testWidgets('lists songs, narrows them with search, and plays the one you tap', (tester) async {
    final library = _library(LibrarySnapshot(tracks: [
      libTrack('Alpha', artist: 'Ann'),
      libTrack('Beta', artist: 'Bob'),
      libTrack('Gamma', artist: 'Ann'),
    ]));
    await library.load();
    final playback = PlaybackController(deckA: FakeDeck(), deckB: FakeDeck());

    await tester.pumpWidget(_host(library, playback));
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bob');
    await tester.pump();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Beta'));
    await tester.pump();
    await tester.pump();
    expect(playback.current?.id, 'local:/music/Beta.mp3');
    expect(playback.current?.source.name, 'local');
  });

  testWidgets('with no music it offers to scan or add songs', (tester) async {
    final library = _library(const LibrarySnapshot());
    await library.load();
    await tester.pumpWidget(_host(library, PlaybackController(deckA: FakeDeck(), deckB: FakeDeck())));
    expect(find.text('No music yet'), findsOneWidget);
    expect(find.text('Scan this device'), findsOneWidget);
    expect(find.text('Add songs'), findsWidgets);
  });
}
