import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/auth/auth_controller.dart';
import 'package:vyro_music/auth/screens/account_banners.dart';
import 'package:vyro_music/auth/screens/account_page.dart';
import 'package:vyro_music/auth/screens/artist_upgrade_page.dart';
import 'package:vyro_music/auth/screens/auth_gate.dart';
import 'package:vyro_music/auth/screens/guest_prompt.dart';
import 'package:vyro_music/auth/screens/sign_in_page.dart';
import 'package:vyro_music/auth/screens/sign_up_page.dart';
import 'package:vyro_music/auth/screens/taste_page.dart';
import 'package:vyro_music/auth/screens/welcome_page.dart';
import 'package:vyro_music/auth/social_sign_in.dart';
import 'package:vyro_music/auth/token_store.dart';
import 'package:vyro_music/auth/validators.dart';

import 'auth_fakes.dart';

Widget _host(Widget child) => MaterialApp(home: child);

Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

AuthController _plain([FakeAuthApi? api]) => AuthController(api: api ?? FakeAuthApi(), store: MemoryTokenStore());

/// Shows [page] on top of another screen, the way it is used in the app, so closing it works.
Future<void> _openPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)), child: const Text('open')),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('welcome', () {
    testWidgets('offers every way in, and says when a provider is not set up', (tester) async {
      await _tall(tester);
      final auth = _plain()..leaveGuest();
      await tester.pumpWidget(_host(WelcomePage(auth: auth, social: const UnconfiguredSocialSignIn())));
      for (final label in ['Create account', 'Log in', 'Use my phone number', 'Continue with Google', 'Continue as guest']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();
      expect(find.textContaining('not set up'), findsOneWidget);

      await tester.tap(find.text('Continue as guest'));
      expect(auth.isGuest, isTrue);
    });
  });

  group('log in', () {
    testWidgets('checks the form, then signs in', (tester) async {
      await _tall(tester);
      final api = FakeAuthApi();
      final auth = _plain(api);
      await tester.pumpWidget(_host(SignInPage(auth: auth)));

      await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
      await tester.pump();
      expect(find.text('That email does not look right.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'amani@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'password-123');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('login'));
      expect(auth.status, AuthStatus.signedIn);
    });

    testWidgets('shows the server\'s reason when sign-in fails', (tester) async {
      await _tall(tester);
      final api = FakeAuthApi()..failWith = const ApiExceptionForTest();
      await tester.pumpWidget(_host(SignInPage(auth: _plain(api))));
      await tester.enterText(find.byType(TextFormField).at(0), 'amani@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(find.text("That email and password don't match."), findsOneWidget);
    });
  });

  group('create account', () {
    testWidgets('asks for everything that is missing', (tester) async {
      await _tall(tester);
      final api = FakeAuthApi();
      await tester.pumpWidget(_host(SignUpPage(auth: _plain(api))));
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Choose your date of birth.'), findsOneWidget);
      expect(find.text('Please agree to continue.'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('explains the age rules for each age', (tester) async {
      Future<void> shows(AgeBand? band, String? text) async {
        await tester.pumpWidget(_host(Scaffold(body: AgeNotice(band: band))));
        if (text == null) {
          expect(find.byType(Text), findsNothing);
        } else {
          expect(find.textContaining(text), findsOneWidget);
        }
      }

      await shows(AgeBand.tooYoung, 'aged 13 and over');
      await shows(AgeBand.needsParent, 'parent or guardian has to give permission');
      await shows(AgeBand.minor, 'turned off for accounts under 18');
      await shows(AgeBand.adult, null);
    });
  });

  group('taste picker', () {
    testWidgets('skipping saves an empty choice so it is not asked again', (tester) async {
      await _tall(tester);
      final api = FakeAuthApi(user: testUser(tasteSet: false));
      final auth = await signedIn(api);
      await tester.pumpWidget(_host(TastePage(auth: auth)));
      await tester.pumpAndSettle();
      expect(find.text('Afrobeats'), findsOneWidget);
      expect(find.textContaining('Artists will appear here'), findsOneWidget);
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('saveTaste'));
      expect(auth.user!.tasteSet, isTrue);
    });
  });

  group('what to show', () {
    Widget gate(AuthController auth) => _host(AuthGate(auth: auth, social: const UnconfiguredSocialSignIn(), appBuilder: (_) => const Scaffold(body: Text('THE APP'))));

    testWidgets('loading, then the welcome screen for someone signed out', (tester) async {
      final auth = _plain();
      await tester.pumpWidget(gate(auth));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await auth.restore();
      await tester.pump();
      expect(find.text('Create account'), findsOneWidget);
    });

    testWidgets('guests and signed-in people reach the app; new accounts see the taste picker first', (tester) async {
      final guest = _plain()..continueAsGuest();
      await tester.pumpWidget(gate(guest));
      expect(find.text('THE APP'), findsOneWidget);

      final done = await signedIn(FakeAuthApi());
      await tester.pumpWidget(gate(done));
      expect(find.text('THE APP'), findsOneWidget);

      final fresh = await signedIn(FakeAuthApi(user: testUser(tasteSet: false)));
      await tester.pumpWidget(gate(fresh));
      await tester.pumpAndSettle();
      expect(find.text('What do you like?'), findsOneWidget);
      expect(find.text('THE APP'), findsNothing);
    });
  });

  group('become an artist', () {
    testWidgets('explains what is missing before showing the form', (tester) async {
      await _tall(tester);
      await tester.pumpWidget(_host(ArtistUpgradePage(auth: await signedIn(FakeAuthApi(user: testUser(emailVerified: false))))));
      expect(find.textContaining('Confirm your email before'), findsOneWidget);
      expect(find.text('Confirm my email'), findsOneWidget);

      await tester.pumpWidget(_host(ArtistUpgradePage(auth: await signedIn(FakeAuthApi(user: testUser(isMinor: true))))));
      expect(find.text('Artist accounts are for people aged 18 and over.'), findsOneWidget);

      await tester.pumpWidget(_host(ArtistUpgradePage(auth: await signedIn(FakeAuthApi(user: testUser(parentConsent: 'pending', isMinor: true))))));
      expect(find.textContaining('parent or guardian needs to give permission'), findsOneWidget);
    });

    testWidgets('needs both boxes ticked, and creates the artist profile', (tester) async {
      await _tall(tester);
      final api = FakeAuthApi();
      final auth = await signedIn(api);
      await _openPage(tester, ArtistUpgradePage(auth: auth));
      expect(find.text('Create artist profile'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Create artist profile'));
      await tester.pump();
      expect(find.text('Please tick both boxes to continue.'), findsOneWidget);
      expect(api.calls, isNot(contains('becomeArtist')));

      await tester.enterText(find.byType(TextFormField).first, 'Amani Beats');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solo artist').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('I own or control everything I will upload.'));
      await tester.tap(find.text('I accept the Vyro artist agreement.'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Create artist profile'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('becomeArtist'));
      expect(auth.user!.isArtist, isTrue);
    });
  });

  group('account', () {
    testWidgets('shows who you are, saves privacy choices, and guards deletion', (tester) async {
      await _tall(tester);
      final api = FakeAuthApi();
      final auth = await signedIn(api);
      await tester.pumpWidget(_host(AccountPage(auth: auth)));
      expect(find.text('Amani'), findsOneWidget);
      expect(find.textContaining('@amani'), findsOneWidget);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Private session'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('updateSettings'));
      expect(auth.user!.settings.privateSession, isTrue);

      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.text('Type DELETE to confirm'), findsOneWidget);
      expect(find.text('Your password'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls, isNot(contains('deleteAccount')));
    });

    testWidgets('keeps explicit content off for minors', (tester) async {
      await _tall(tester);
      final auth = await signedIn(FakeAuthApi(user: testUser(isMinor: true)));
      await tester.pumpWidget(_host(AccountPage(auth: auth)));
      final tile = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Allow explicit content'));
      expect(tile.onChanged, isNull);
      expect(find.text('Not available for accounts under 18.'), findsOneWidget);
    });
  });

  group('reminders and guests', () {
    testWidgets('banners ask for the email check and the parent\'s permission', (tester) async {
      final auth = await signedIn(FakeAuthApi(user: testUser(emailVerified: false, parentConsent: 'pending', isMinor: true)));
      await tester.pumpWidget(_host(Scaffold(body: AccountBanners(auth: auth))));
      expect(find.textContaining('Confirm your email'), findsOneWidget);
      expect(find.textContaining("parent or guardian's permission"), findsOneWidget);
    });

    testWidgets('a verified adult sees no banners', (tester) async {
      final auth = await signedIn(FakeAuthApi());
      await tester.pumpWidget(_host(Scaffold(body: AccountBanners(auth: auth))));
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('the guest prompt leads back to sign-in', (tester) async {
      final auth = _plain()..continueAsGuest();
      await tester.pumpWidget(_host(Scaffold(body: GuestPrompt(auth: auth))));
      await tester.tap(find.text('Create account or log in'));
      expect(auth.status, AuthStatus.signedOut);
    });
  });
}
