import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/main.dart';

import 'fakes.dart';

Widget _app() => VyroApp(playback: PlaybackController(deckA: FakeDeck(), deckB: FakeDeck()));

void main() {
  testWidgets('switches between listener and artist modes', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('Library'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to Artist Studio'));
    await tester.pumpAndSettle();
    expect(find.text('Releases'), findsWidgets);
    expect(find.text('Library'), findsNothing);
  });

  testWidgets('theme can be switched to Daylight from Settings', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daylight'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.light);
  });

  testWidgets('tapping a demo song shows the mini player', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Demo song 2'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Next'), findsOneWidget);
  });

  testWidgets('listener Profile tab shows listening statistics', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Minutes listened'), findsOneWidget);
  });

  testWidgets('artist Stats tab shows the dashboard', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byTooltip('Switch to Artist Studio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('Right now'), findsOneWidget);
  });
}
