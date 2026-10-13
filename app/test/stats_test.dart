import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/stats/artist_stats_page.dart';
import 'package:vyro_music/stats/demo_stats_repository.dart';
import 'package:vyro_music/stats/listener_profile_page.dart';
import 'package:vyro_music/stats/widgets.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  test('compact numbers', () {
    expect(compact(999), '999');
    expect(compact(1000), '1K');
    expect(compact(1234), '1.2K');
    expect(compact(15300), '15K');
    expect(compact(2500000), '2.5M');
  });

  test('thousands separators', () {
    expect(thousands(7), '7');
    expect(thousands(1234), '1,234');
    expect(thousands(41059), '41,059');
    expect(thousands(1000000), '1,000,000');
  });

  testWidgets('artist dashboard shows headline numbers and changes period', (tester) async {
    await tester.pumpWidget(_host(ArtistStatsPage(repository: DemoStatsRepository())));
    await tester.pumpAndSettle();
    expect(find.text('Right now'), findsOneWidget);
    expect(find.text('Plays'), findsOneWidget);
    expect(find.text('Listeners'), findsOneWidget);

    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(find.text('Right now'), findsOneWidget);
  });

  testWidgets('tapping a song opens how far listeners get', (tester) async {
    await tester.pumpWidget(_host(ArtistStatsPage(repository: DemoStatsRepository())));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Midnight Drive'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Midnight Drive'));
    await tester.pumpAndSettle();
    expect(find.text('How far listeners get'), findsOneWidget);
  });

  testWidgets('listener profile shows minutes and follows the chosen period', (tester) async {
    await tester.pumpWidget(_host(ListenerProfilePage(repository: DemoStatsRepository(), displayName: 'Amani', username: 'amani')));
    await tester.pumpAndSettle();
    expect(find.text('Minutes listened'), findsOneWidget);
    expect(find.text('@amani'), findsOneWidget);
    expect(find.text('2,184'), findsOneWidget);

    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    expect(find.text('41,059'), findsOneWidget);
  });
}
