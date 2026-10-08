import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vyro_music/auth/api_client.dart';
import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/auth/auth_controller.dart';
import 'package:vyro_music/auth/auth_models.dart';
import 'package:vyro_music/auth/token_store.dart';
import 'package:vyro_music/auth/validators.dart';

import 'auth_fakes.dart';

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('validators and age rules', () {
    test('emails, passwords, usernames, codes and phone numbers', () {
      expect(validateEmail('a@b.co'), isNull);
      expect(validateEmail('nope'), isNotNull);
      expect(validatePassword('1234567'), isNotNull);
      expect(validatePassword('12345678'), isNull);
      expect(validateUsername('good_name1'), isNull);
      expect(validateUsername('Bad Name'), isNotNull);
      expect(validateUsername('ab'), isNotNull);
      expect(validateCode('123456'), isNull);
      expect(validateCode('12345'), isNotNull);
      expect(validatePhone('+1 (415) 555-0123'), isNull);
      expect(validatePhone('0712345678'), isNotNull);
      expect(normalizePhone('+1 (415) 555-0123'), '+14155550123');
    });

    test('age around a birthday, and the bands the server also uses', () {
      final now = DateTime(2026, 10, 6);
      expect(ageOn(DateTime(2013, 10, 6), now), 13);
      expect(ageOn(DateTime(2013, 10, 7), now), 12);
      expect(ageBandOf(12), AgeBand.tooYoung);
      expect(ageBandOf(13), AgeBand.needsParent);
      expect(ageBandOf(15), AgeBand.needsParent);
      expect(ageBandOf(16), AgeBand.minor);
      expect(ageBandOf(17), AgeBand.minor);
      expect(ageBandOf(18), AgeBand.adult);
      expect(formatDate(DateTime(2005, 3, 9)), '2005-03-09');
    });
  });

  group('models', () {
    test('a profile survives being saved and read back', () {
      final user = testUser(artist: true, emailVerified: false, parentConsent: 'pending', isMinor: true);
      final back = UserProfile.fromJson(user.toJson());
      expect(back.displayName, 'Amani');
      expect(back.isArtist, isTrue);
      expect(back.artist!.stageName, 'Amani Beats');
      expect(back.parentPending, isTrue);
      expect(back.needsEmailCheck, isTrue);
      expect(back.isMinor, isTrue);
    });

    test('reads the server\'s profile, including a phone-only account', () {
      final u = UserProfile.fromJson({
        'id': 'x',
        'displayName': 'P',
        'username': 'p_user',
        'email': null,
        'phone': '+14155550123',
        'language': 'en',
        'emailVerified': false,
        'phoneVerified': true,
        'hasPassword': false,
        'isMinor': false,
        'parentConsent': 'not_needed',
        'settings': {'explicitAllowed': true, 'privateSession': true, 'hideActivity': false, 'shareListening': true, 'personalization': true},
        'tasteSet': false,
        'artist': null,
        'modes': ['listener'],
      });
      expect(u.email, isNull);
      expect(u.contactVerified, isTrue);
      expect(u.hasPassword, isFalse);
      expect(u.settings.privateSession, isTrue);
      expect(u.needsEmailCheck, isFalse);
    });

    test('every server error has a plain-language message', () {
      for (final code in ['network', 'invalid_credentials', 'too_young', 'code_expired', 'stage_name_taken', 'artist_requires_adult', 'anything-new']) {
        expect(describeError(code), isNotEmpty);
      }
      expect(const ApiException(0, 'network').isNetwork, isTrue);
    });
  });

  group('ApiClient', () {
    test('sends the access token and JSON, and returns the decoded answer', () async {
      late http.BaseRequest seen;
      final session = ApiSession()..accessToken = 'tok';
      final client = ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: session,
        client: MockClient((request) async {
          seen = request;
          return _json(200, {'ok': true});
        }),
      );
      final result = await client.send('POST', '/v1/thing', body: {'a': 1}, query: {'range': '28d'});
      expect(result, {'ok': true});
      expect(seen.url.toString(), 'http://localhost:3000/v1/thing?range=28d');
      expect(seen.headers['authorization'], 'Bearer tok');
      expect(seen.headers['content-type'], 'application/json');
    });

    test('leaves the token off for sign-in calls', () async {
      late http.BaseRequest seen;
      final client = ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: ApiSession()..accessToken = 'tok',
        client: MockClient((request) async {
          seen = request;
          return _json(200, {});
        }),
      );
      await client.send('POST', '/v1/auth/login', auth: false);
      expect(seen.headers.containsKey('authorization'), isFalse);
    });

    test('turns server errors into ApiException with the server\'s code', () async {
      final client = ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: ApiSession(),
        client: MockClient((_) async => _json(403, {'error': 'too_young'})),
      );
      await expectLater(
        client.send('POST', '/x', auth: false),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'too_young').having((e) => e.status, 'status', 403)),
      );
    });

    test('refreshes an expired token once and retries the request', () async {
      final seenTokens = <String?>[];
      final session = ApiSession()..accessToken = 'old';
      session.onUnauthorized = () async {
        session.accessToken = 'new';
        return true;
      };
      final client = ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: session,
        client: MockClient((request) async {
          seenTokens.add(request.headers['authorization']);
          return request.headers['authorization'] == 'Bearer new' ? _json(200, {'ok': 1}) : _json(401, {'error': 'unauthorized'});
        }),
      );
      expect(await client.send('GET', '/v1/me'), {'ok': 1});
      expect(seenTokens, ['Bearer old', 'Bearer new']);
    });

    test('gives up with 401 when the refresh does not work, and never loops', () async {
      var calls = 0;
      final session = ApiSession()..accessToken = 'old';
      session.onUnauthorized = () async => false;
      final client = ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: session,
        client: MockClient((_) async {
          calls++;
          return _json(401, {'error': 'unauthorized'});
        }),
      );
      await expectLater(client.send('GET', '/v1/me'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'unauthorized', isTrue)));
      expect(calls, 1);
    });

    test('a dropped connection becomes a network error', () async {
      final client = ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: ApiSession(),
        client: MockClient((_) async => throw http.ClientException('connection lost')),
      );
      await expectLater(client.send('GET', '/x', auth: false), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', isTrue)));
    });
  });

  group('AuthController', () {
    test('signing in saves the login and shows the profile', () async {
      final api = FakeAuthApi();
      final store = MemoryTokenStore();
      final auth = AuthController(api: api, store: store);
      expect(auth.status, AuthStatus.starting);
      await auth.signIn('amani@example.com', 'password-123');
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.user!.displayName, 'Amani');
      expect(await store.readRefreshToken(), 'refresh-1');
      expect((await store.readProfile())!.username, 'amani');
      expect(auth.session.accessToken, 'access-1');
    });

    test('a saved login is picked back up at start-up', () async {
      final api = FakeAuthApi();
      final store = MemoryTokenStore()..saveRefreshToken('refresh-0');
      final auth = AuthController(api: api, store: store);
      await auth.restore();
      expect(auth.status, AuthStatus.signedIn);
      expect(api.calls, ['refresh', 'me']);
      expect(await store.readRefreshToken(), 'refresh-1'); // the new token replaced the old one
    });

    test('with nothing saved it starts signed out', () async {
      final auth = AuthController(api: FakeAuthApi(), store: MemoryTokenStore());
      await auth.restore();
      expect(auth.status, AuthStatus.signedOut);
    });

    test('an expired login is cleared and the person is signed out', () async {
      final api = FakeAuthApi()..failWith = const ApiException(401, 'invalid_refresh_token');
      final store = MemoryTokenStore()..saveRefreshToken('stale');
      final auth = AuthController(api: api, store: store);
      await auth.restore();
      expect(auth.status, AuthStatus.signedOut);
      expect(await store.readRefreshToken(), isNull);
    });

    test('without a connection the app opens with the last saved profile', () async {
      final api = FakeAuthApi()..failWith = networkDown;
      final store = MemoryTokenStore()
        ..saveRefreshToken('refresh-0')
        ..saveProfile(testUser());
      final auth = AuthController(api: api, store: store);
      await auth.restore();
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.isOffline, isTrue);
      expect(auth.user!.username, 'amani');
      expect(await store.readRefreshToken(), 'refresh-0'); // kept, so signing in works once back online
    });

    test('without a connection and nothing saved it starts signed out', () async {
      final api = FakeAuthApi()..failWith = networkDown;
      final store = MemoryTokenStore()..saveRefreshToken('refresh-0');
      final auth = AuthController(api: api, store: store);
      await auth.restore();
      expect(auth.status, AuthStatus.signedOut);
    });

    test('guests can look around, and leave to sign in', () {
      final auth = AuthController(api: FakeAuthApi(), store: MemoryTokenStore());
      auth.continueAsGuest();
      expect(auth.isGuest, isTrue);
      auth.leaveGuest();
      expect(auth.status, AuthStatus.signedOut);
    });

    test('a phone sign-in for a new person waits for the profile, then finishes', () async {
      final api = FakeAuthApi()..phoneOutcome = const SignInOutcome.needsProfile(PendingProfile(signupToken: 'pass'));
      final auth = AuthController(api: api, store: MemoryTokenStore());
      final outcome = await auth.verifyPhoneCode('+14155550123', '123456');
      expect(outcome.pending, isNotNull);
      expect(auth.pending!.signupToken, 'pass');
      expect(auth.status, AuthStatus.starting); // not signed in yet
      await auth.completeProfile(const CompleteProfileRequest(displayName: 'P', username: 'p_user', birthDate: '1990-01-01', acceptedTermsVersion: '2026-10'));
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.pending, isNull);
    });

    test('finishing a profile without a pass is refused', () async {
      final auth = AuthController(api: FakeAuthApi(), store: MemoryTokenStore());
      await expectLater(
        auth.completeProfile(const CompleteProfileRequest(displayName: 'P', username: 'p_user', birthDate: '1990-01-01', acceptedTermsVersion: '2026-10')),
        throwsA(isA<ApiException>()),
      );
    });

    test('several requests with an expired token share one refresh', () async {
      final api = FakeAuthApi();
      final store = MemoryTokenStore()..saveRefreshToken('refresh-0');
      final auth = AuthController(api: api, store: store);
      await auth.restore();
      api.calls.clear();
      final results = await Future.wait([auth.session.onUnauthorized!(), auth.session.onUnauthorized!(), auth.session.onUnauthorized!()]);
      expect(results, [true, true, true]);
      expect(api.calls.where((c) => c == 'refresh').length, 1);
    });

    test('a refresh the server refuses signs the person out', () async {
      final api = FakeAuthApi();
      final auth = AuthController(api: api, store: MemoryTokenStore());
      await auth.signIn('a@b.co', 'password-123');
      api.failWith = const ApiException(401, 'invalid_refresh_token');
      expect(await auth.session.onUnauthorized!(), isFalse);
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.user, isNull);
    });

    test('settings and becoming an artist update the profile', () async {
      final api = FakeAuthApi();
      final auth = await signedIn(api);
      await auth.updateSettings(privateSession: true);
      expect(auth.user!.settings.privateSession, isTrue);
      expect(auth.user!.isArtist, isFalse);
      await auth.becomeArtist(const ArtistRequest(stageName: 'Amani Beats', artistType: 'solo', agreementVersion: '2026-10'));
      expect(auth.user!.isArtist, isTrue);
    });

    test('signing out works even without a connection', () async {
      final api = FakeAuthApi();
      final store = MemoryTokenStore();
      final auth = AuthController(api: api, store: store);
      await auth.signIn('a@b.co', 'password-123');
      api.failWith = networkDown;
      await auth.signOut();
      expect(auth.status, AuthStatus.signedOut);
      expect(await store.readRefreshToken(), isNull);
    });

    test('deleting the account clears everything on the device', () async {
      final api = FakeAuthApi();
      final store = MemoryTokenStore();
      final auth = AuthController(api: api, store: store);
      await auth.signIn('a@b.co', 'password-123');
      await auth.deleteAccount(password: 'password-123');
      expect(api.calls, contains('deleteAccount'));
      expect(auth.status, AuthStatus.signedOut);
      expect(await store.readProfile(), isNull);
    });
  });
}
