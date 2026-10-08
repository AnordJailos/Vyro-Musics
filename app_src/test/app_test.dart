import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/auth/auth_controller.dart';
import 'package:vyro_music/auth/auth_api.dart';
import 'package:vyro_music/auth/token_store.dart';
import 'package:vyro_music/main.dart';

import 'auth_fakes.dart';
import 'fakes.dart';

PlaybackController _playback() => PlaybackController(deckA: FakeDeck(), deckB: FakeDeck());

Widget _app(AuthController auth) => VyroApp(playback: _playback(), auth: auth);

AuthController _guest() => AuthController(api: const OfflineAuthApi(), store: MemoryTokenStore())..continueAsGuest();

void main() {
  testWidgets('an artist switches between listener and artist modes', (tester) async {
    final auth = await signedIn(FakeAuthApi(user: testUser(artist: true)));
    await tester.pumpWidget(_app(auth));
    expect(find.text('Library'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to Artist Studio'));
    await tester.pumpAndSettle();
    expect(find.text('Releases'), findsWidgets);
    expect(find.text('Library'), findsNothing);
  });

  testWidgets('someone who is not an artist yet is taken to "Become an artist"', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(await signedIn(FakeAuthApi())));
    await tester.tap(find.byTooltip('Become an artist'));
    await tester.pumpAndSettle();
    expect(find.text('Create artist profile'), findsOneWidget);
  });

  testWidgets('a guest is asked to sign in before using the artist studio', (tester) async {
    final auth = _guest();
    await tester.pumpWidget(_app(auth));
    await tester.tap(find.byTooltip('Sign in to become an artist'));
    await tester.pumpAndSettle();
    expect(find.text('Create an account'), findsOneWidget);
    await tester.tap(find.text('Create account or log in'));
    await tester.pumpAndSettle();
    expect(auth.status, AuthStatus.signedOut);
  });

  testWidgets('theme can be switched to Daylight from Settings', (tester) async {
    await tester.pumpWidget(_app(_guest()));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daylight'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.light);
  });

  testWidgets('tapping a demo song shows the mini player', (tester) async {
    await tester.pumpWidget(_app(_guest()));
    await tester.tap(find.text('Demo song 2'));
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Next'), findsOneWidget);
  });

  testWidgets('a signed-in listener sees their profile statistics', (tester) async {
    await tester.pumpWidget(_app(await signedIn(FakeAuthApi())));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Minutes listened'), findsOneWidget);
    expect(find.text('@amani'), findsOneWidget);
  });

  testWidgets('a guest sees an invitation instead of a profile', (tester) async {
    await tester.pumpWidget(_app(_guest()));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('You are browsing as a guest'), findsOneWidget);
    expect(find.text('Minutes listened'), findsNothing);
  });

  testWidgets('an artist\'s Stats tab shows the dashboard', (tester) async {
    await tester.pumpWidget(_app(await signedIn(FakeAuthApi(user: testUser(artist: true)))));
    await tester.tap(find.byTooltip('Switch to Artist Studio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('Right now'), findsOneWidget);
  });
}
