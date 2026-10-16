import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vyro_music/auth/api_client.dart';
import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/auth/auth_api.dart';
import 'package:vyro_music/auth/auth_models.dart';
import 'package:vyro_music/auth/screens/account_page.dart';
import 'package:vyro_music/studio/studio_models.dart';

import 'auth_fakes.dart';
import 'catalog_fakes.dart';

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, Object?> profileJson({String? photoUrl, bool shareCountry = true, String language = 'en'}) => {
      'id': 'u1',
      'displayName': 'Amani',
      'username': 'amani',
      'language': language,
      'settings': {'shareCountry': shareCountry},
      'photoUrl': photoUrl,
    };

void main() {
  group('the profile', () {
    test('reads the photo and the share-country choice, and assumes sharing when an older server does not say', () {
      final p = UserProfile.fromJson(profileJson(photoUrl: '/v1/users/u1/photo?v=5', shareCountry: false));
      expect([p.photoUrl, p.settings.shareCountry], ['/v1/users/u1/photo?v=5', false]);
      final old = UserProfile.fromJson({'id': 'u1', 'displayName': 'A', 'username': 'a'});
      expect([old.photoUrl, old.settings.shareCountry], [null, true]);
      expect(UserProfile.fromJson(p.toJson()).photoUrl, p.photoUrl);
      expect(UserProfile.fromJson(p.toJson()).settings.shareCountry, isFalse);
    });

    test('can change one thing at a time', () {
      final p = UserProfile.fromJson(profileJson(photoUrl: '/x'));
      expect(p.copyWith(language: 'sw').language, 'sw');
      expect(p.copyWith(language: 'sw').photoUrl, '/x');
      expect(p.copyWith(removePhoto: true).photoUrl, isNull);
      expect(p.copyWith(country: 'KE').country, 'KE');
    });
  });

  group('the HTTP API', () {
    HttpAuthApi apiFor(http.Response Function(http.Request) answer, List<http.Request> seen, {String? token}) {
      final session = ApiSession()..accessToken = token;
      return HttpAuthApi(ApiClient(
        baseUrl: Uri.parse('http://localhost:3000'),
        session: session,
        client: MockClient((request) async {
          seen.add(request);
          return answer(request);
        }),
      ));
    }

    PickedFile picture(int length, {String name = 'me.png'}) => PickedFile(name: name, length: length, open: () => Stream.value(List<int>.filled(length, 7)));

    test('uploads a photo as the request body, and returns the new profile', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) => _json(200, profileJson(photoUrl: '/v1/users/u1/photo?v=9')), seen, token: 't');
      final p = await api.uploadPhoto(picture(300));
      expect([seen.single.method, seen.single.url.path, seen.single.headers['content-type'], seen.single.bodyBytes.length], ['PUT', '/v1/me/photo', 'image/png', 300]);
      expect(p.photoUrl, '/v1/users/u1/photo?v=9');
    });

    test('refuses a photo over 5 MB without sending it', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) => _json(200, profileJson()), seen);
      await expectLater(api.uploadPhoto(picture(5 * 1024 * 1024 + 1)), throwsA(isA<ApiException>().having((e) => e.status, 'status', 413)));
      expect(seen, isEmpty);
    });

    test('removes a photo, and sends the share-country choice', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) => r.method == 'DELETE' ? http.Response('', 204) : _json(200, profileJson(shareCountry: false)), seen);
      await api.removePhoto();
      final p = await api.updateSettings(shareCountry: false);
      expect([seen[0].method, seen[0].url.path], ['DELETE', '/v1/me/photo']);
      expect([seen[1].method, seen[1].url.path, jsonDecode(seen[1].body)], ['PATCH', '/v1/me/settings', {'shareCountry': false}]);
      expect(p.settings.shareCountry, isFalse);
    });

    test('downloads the person\'s data as readable text', () async {
      final seen = <http.Request>[];
      final api = apiFor((r) => _json(200, {'exportedAt': 'now', 'follows': <Object>[]}), seen);
      final text = await api.exportData();
      expect(seen.single.url.path, '/v1/me/export');
      expect(text, contains('\n  "exportedAt": "now"')); // indented, so a person can read it
      expect(jsonDecode(text), {'exportedAt': 'now', 'follows': []});
    });

    test('knows where a photo is, and how to fetch a private one', () {
      final signedIn = apiFor((r) => http.Response('', 204), [], token: 'abc');
      expect(signedIn.photoUri('/v1/users/u1/photo?v=5').toString(), 'http://localhost:3000/v1/users/u1/photo?v=5');
      expect(signedIn.imageHeaders, {'authorization': 'Bearer abc'});
      expect(apiFor((r) => http.Response('', 204), []).imageHeaders, isEmpty);
    });

    test('with no connection to the server, a photo address is simply not available', () {
      const offline = OfflineAuthApi();
      expect(offline.photoUri('/x'), isNull);
      expect(offline.imageHeaders, isEmpty);
    });
  });

  group('the Account screen', () {
    late FakeAuthApi api;
    late FakePicker picker;

    Future<void> show(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      api = FakeAuthApi();
      picker = FakePicker(image: pickedFile('me.png', 1000));
      final auth = await signedIn(api);
      await tester.pumpWidget(MaterialApp(home: AccountPage(auth: auth, picker: picker)));
    }

    testWidgets('adds, changes and removes a profile photo', (tester) async {
      await show(tester);
      expect(find.text('Add a profile photo'), findsOneWidget);
      expect(find.text('Remove profile photo'), findsNothing);
      await tester.tap(find.text('Add a profile photo'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('uploadPhoto'));
      expect(find.text('Change profile photo'), findsOneWidget);
      await tester.tap(find.text('Remove profile photo'));
      await tester.pumpAndSettle();
      expect(api.calls, contains('removePhoto'));
      expect(find.text('Add a profile photo'), findsOneWidget);
    });

    testWidgets('will not send a picture over 5 MB, and says why', (tester) async {
      await show(tester);
      picker.image = PickedFile(name: 'huge.png', length: 6 * 1024 * 1024, open: () => const Stream.empty());
      await tester.tap(find.text('Add a profile photo'));
      await tester.pumpAndSettle();
      expect(find.text('That picture is too large. Choose one under 5 MB.'), findsOneWidget);
      expect(api.calls, isNot(contains('uploadPhoto')));
    });

    testWidgets('keeps the choice of language, and of country', (tester) async {
      await show(tester);
      expect(find.text('English'), findsOneWidget);
      tester.widget<DropdownButton<String>>(find.byKey(const ValueKey('language'))).onChanged!('sw');
      await tester.pumpAndSettle();
      expect(find.text('Kiswahili'), findsOneWidget);
      expect(find.textContaining('not translated yet'), findsOneWidget); // honest about what the choice does today
      tester.widget<DropdownButton<String>>(find.byKey(const ValueKey('country'))).onChanged!('KE');
      await tester.pumpAndSettle();
      expect(find.text('Kenya'), findsOneWidget);
    });

    testWidgets('lets the person stop sharing their country with artists', (tester) async {
      await show(tester);
      final tile = find.widgetWithText(SwitchListTile, 'Share my country with artists');
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    });

    testWidgets('is honest about the controls that do nothing yet', (tester) async {
      await show(tester);
      expect(find.textContaining('Nothing is shown to other people yet'), findsOneWidget);
      expect(find.textContaining('Applies once friends and sharing arrive'), findsOneWidget);
    });

    testWidgets('copies a download of the person\'s data', (tester) async {
      await show(tester);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.text('Download my data'));
      await tester.pumpAndSettle();
      expect(copied, '{"fake": true}');
      expect(find.text('Your data was copied. Paste it into a file to keep it.'), findsOneWidget);
    });
  });
}
