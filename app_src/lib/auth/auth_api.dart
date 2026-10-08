import 'api_client.dart';
import 'api_errors.dart';
import 'auth_models.dart';

/// Everything the account screens ask of the server.
abstract class AuthApi {
  Future<Session> register(RegisterRequest request);
  Future<Session> login(String email, String password, {String? deviceName});
  Future<AuthTokens> refresh(String refreshToken);
  Future<void> logout(String refreshToken);
  Future<UserProfile> me();
  Future<UserProfile> verifyEmail(String code);
  Future<void> resendEmail();
  Future<void> requestPhoneCode(String phone);
  Future<SignInOutcome> verifyPhoneCode(String phone, String code, {String? deviceName});
  Future<SignInOutcome> signInSocial(String provider, String idToken, {String? deviceName});
  Future<Session> completeProfile(String signupToken, CompleteProfileRequest request);
  Future<void> requestPasswordReset(String email);
  Future<void> confirmPasswordReset(String email, String code, String newPassword);
  Future<UserProfile> confirmParentConsent(String code);
  Future<void> resendParentConsent();
  Future<UserProfile> updateProfile({String? displayName, String? username, String? country, String? language});
  Future<UserProfile> updateSettings({bool? explicitAllowed, bool? privateSession, bool? hideActivity, bool? shareListening, bool? personalization});
  Future<List<SuggestedArtist>> suggestedArtists();
  Future<UserProfile> saveTaste({List<String> genres = const [], List<String> moods = const [], List<String> artistIds = const []});
  Future<UserProfile> becomeArtist(ArtistRequest request);
  Future<void> deleteAccount({String? password});
}

Map<String, Object?> _map(Object? json) => (json as Map).cast<String, Object?>();

/// The real thing: talks to the server over HTTP.
class HttpAuthApi implements AuthApi {
  HttpAuthApi(this._client);

  final ApiClient _client;

  Session _session(Object? json) {
    final m = _map(json);
    return Session(UserProfile.fromJson(_map(m['user'])), AuthTokens(m['accessToken'] as String, m['refreshToken'] as String));
  }

  SignInOutcome _outcome(Object? json) {
    final m = _map(json);
    if (m['needsProfile'] == true) {
      return SignInOutcome.needsProfile(PendingProfile(signupToken: m['signupToken'] as String, suggestedEmail: m['suggestedEmail'] as String?));
    }
    return SignInOutcome.signedIn(_session(json));
  }

  Future<UserProfile> _profile(Future<Object?> call) async => UserProfile.fromJson(_map(await call));

  @override
  Future<Session> register(RegisterRequest request) async => _session(await _client.send('POST', '/v1/auth/register', body: request.toJson(), auth: false));

  @override
  Future<Session> login(String email, String password, {String? deviceName}) async =>
      _session(await _client.send('POST', '/v1/auth/login', body: {'email': email, 'password': password, if (deviceName != null) 'deviceName': deviceName}, auth: false));

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    final m = _map(await _client.send('POST', '/v1/auth/refresh', body: {'refreshToken': refreshToken}, auth: false));
    return AuthTokens(m['accessToken'] as String, m['refreshToken'] as String);
  }

  @override
  Future<void> logout(String refreshToken) async {
    await _client.send('POST', '/v1/auth/logout', body: {'refreshToken': refreshToken}, auth: false);
  }

  @override
  Future<UserProfile> me() => _profile(_client.send('GET', '/v1/me'));

  @override
  Future<UserProfile> verifyEmail(String code) => _profile(_client.send('POST', '/v1/auth/email/verify', body: {'code': code}));

  @override
  Future<void> resendEmail() async {
    await _client.send('POST', '/v1/auth/email/resend');
  }

  @override
  Future<void> requestPhoneCode(String phone) async {
    await _client.send('POST', '/v1/auth/phone/request', body: {'phone': phone}, auth: false);
  }

  @override
  Future<SignInOutcome> verifyPhoneCode(String phone, String code, {String? deviceName}) async =>
      _outcome(await _client.send('POST', '/v1/auth/phone/verify', body: {'phone': phone, 'code': code, if (deviceName != null) 'deviceName': deviceName}, auth: false));

  @override
  Future<SignInOutcome> signInSocial(String provider, String idToken, {String? deviceName}) async =>
      _outcome(await _client.send('POST', '/v1/auth/social', body: {'provider': provider, 'idToken': idToken, if (deviceName != null) 'deviceName': deviceName}, auth: false));

  @override
  Future<Session> completeProfile(String signupToken, CompleteProfileRequest request) async =>
      _session(await _client.send('POST', '/v1/auth/complete-profile', body: request.toJson(signupToken), auth: false));

  @override
  Future<void> requestPasswordReset(String email) async {
    await _client.send('POST', '/v1/auth/password-reset/request', body: {'email': email}, auth: false);
  }

  @override
  Future<void> confirmPasswordReset(String email, String code, String newPassword) async {
    await _client.send('POST', '/v1/auth/password-reset/confirm', body: {'email': email, 'code': code, 'newPassword': newPassword}, auth: false);
  }

  @override
  Future<UserProfile> confirmParentConsent(String code) => _profile(_client.send('POST', '/v1/me/parent-consent/confirm', body: {'code': code}));

  @override
  Future<void> resendParentConsent() async {
    await _client.send('POST', '/v1/me/parent-consent/resend');
  }

  @override
  Future<UserProfile> updateProfile({String? displayName, String? username, String? country, String? language}) => _profile(_client.send('PATCH', '/v1/me', body: {
        if (displayName != null) 'displayName': displayName,
        if (username != null) 'username': username,
        if (country != null) 'country': country,
        if (language != null) 'language': language,
      }));

  @override
  Future<UserProfile> updateSettings({bool? explicitAllowed, bool? privateSession, bool? hideActivity, bool? shareListening, bool? personalization}) =>
      _profile(_client.send('PATCH', '/v1/me/settings', body: {
        if (explicitAllowed != null) 'explicitAllowed': explicitAllowed,
        if (privateSession != null) 'privateSession': privateSession,
        if (hideActivity != null) 'hideActivity': hideActivity,
        if (shareListening != null) 'shareListening': shareListening,
        if (personalization != null) 'personalization': personalization,
      }));

  @override
  Future<List<SuggestedArtist>> suggestedArtists() async {
    final m = _map(await _client.send('GET', '/v1/artists/suggested'));
    return [
      for (final a in (m['artists'] as List))
        SuggestedArtist(
          id: _map(a)['id'] as String,
          stageName: _map(a)['stageName'] as String,
          genres: [for (final g in (_map(a)['genres'] as List? ?? const [])) g as String],
          followers: (_map(a)['followers'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  @override
  Future<UserProfile> saveTaste({List<String> genres = const [], List<String> moods = const [], List<String> artistIds = const []}) =>
      _profile(_client.send('PUT', '/v1/me/taste', body: {'genres': genres, 'moods': moods, 'artistIds': artistIds}));

  @override
  Future<UserProfile> becomeArtist(ArtistRequest request) => _profile(_client.send('POST', '/v1/artists/me', body: request.toJson()));

  @override
  Future<void> deleteAccount({String? password}) async {
    await _client.send('POST', '/v1/me/delete', body: {'confirm': 'DELETE', if (password != null) 'password': password});
  }
}

/// Used where no server is available (tests, previews): every call fails as "no connection".
class OfflineAuthApi implements AuthApi {
  const OfflineAuthApi();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(const ApiException(0, 'network'));
}
