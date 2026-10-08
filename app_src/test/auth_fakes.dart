import 'package:vyro_music/auth/api_errors.dart';
import 'package:vyro_music/auth/auth_api.dart';
import 'package:vyro_music/auth/auth_controller.dart';
import 'package:vyro_music/auth/auth_models.dart';
import 'package:vyro_music/auth/token_store.dart';

UserProfile testUser({bool artist = false, bool tasteSet = true, bool emailVerified = true, String parentConsent = 'not_needed', bool isMinor = false}) => UserProfile(
      id: 'u1',
      displayName: 'Amani',
      username: 'amani',
      email: 'amani@example.com',
      emailVerified: emailVerified,
      tasteSet: tasteSet,
      parentConsent: parentConsent,
      isMinor: isMinor,
      artist: artist ? const ArtistInfo(stageName: 'Amani Beats') : null,
    );

/// A server that answers from memory and remembers what it was asked.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({UserProfile? user}) : user = user ?? testUser();

  UserProfile user;
  final calls = <String>[];
  Object? failWith;
  int refreshes = 0;
  SignInOutcome? phoneOutcome;

  T _go<T>(String name, T value) {
    calls.add(name);
    final e = failWith;
    if (e != null) throw e;
    return value;
  }

  Session get _session => Session(user, AuthTokens('access-${refreshes + 1}', 'refresh-${refreshes + 1}'));

  @override
  Future<Session> register(RegisterRequest request) async => _go('register', _session);
  @override
  Future<Session> login(String email, String password, {String? deviceName}) async => _go('login', _session);
  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    calls.add('refresh');
    final e = failWith;
    if (e != null) throw e;
    refreshes++;
    return AuthTokens('access-$refreshes', 'refresh-$refreshes');
  }

  @override
  Future<void> logout(String refreshToken) async => _go('logout', null);
  @override
  Future<UserProfile> me() async => _go('me', user);
  @override
  Future<UserProfile> verifyEmail(String code) async {
    user = testUser(emailVerified: true, artist: user.isArtist);
    return _go('verifyEmail', user);
  }

  @override
  Future<void> resendEmail() async => _go('resendEmail', null);
  @override
  Future<void> requestPhoneCode(String phone) async => _go('requestPhoneCode', null);
  @override
  Future<SignInOutcome> verifyPhoneCode(String phone, String code, {String? deviceName}) async =>
      _go('verifyPhoneCode', phoneOutcome ?? SignInOutcome.signedIn(_session));
  @override
  Future<SignInOutcome> signInSocial(String provider, String idToken, {String? deviceName}) async => _go('signInSocial', SignInOutcome.signedIn(_session));
  @override
  Future<Session> completeProfile(String signupToken, CompleteProfileRequest request) async => _go('completeProfile', _session);
  @override
  Future<void> requestPasswordReset(String email) async => _go('requestPasswordReset', null);
  @override
  Future<void> confirmPasswordReset(String email, String code, String newPassword) async => _go('confirmPasswordReset', null);
  @override
  Future<UserProfile> confirmParentConsent(String code) async => _go('confirmParentConsent', user);
  @override
  Future<void> resendParentConsent() async => _go('resendParentConsent', null);
  @override
  Future<UserProfile> updateProfile({String? displayName, String? username, String? country, String? language}) async => _go('updateProfile', user);
  @override
  Future<UserProfile> updateSettings({bool? explicitAllowed, bool? privateSession, bool? hideActivity, bool? shareListening, bool? personalization}) async {
    user = UserProfile(
      id: user.id,
      displayName: user.displayName,
      username: user.username,
      email: user.email,
      emailVerified: user.emailVerified,
      tasteSet: user.tasteSet,
      artist: user.artist,
      settings: UserSettings(privateSession: privateSession ?? user.settings.privateSession, shareListening: shareListening ?? user.settings.shareListening),
    );
    return _go('updateSettings', user);
  }

  @override
  Future<List<SuggestedArtist>> suggestedArtists() async => _go('suggestedArtists', const <SuggestedArtist>[]);
  @override
  Future<UserProfile> saveTaste({List<String> genres = const [], List<String> moods = const [], List<String> artistIds = const []}) async {
    user = testUser(tasteSet: true, artist: user.isArtist);
    return _go('saveTaste', user);
  }

  @override
  Future<UserProfile> becomeArtist(ArtistRequest request) async {
    user = testUser(artist: true);
    return _go('becomeArtist', user);
  }

  @override
  Future<void> deleteAccount({String? password}) async => _go('deleteAccount', null);
}

/// A signed-in controller, ready for widget tests.
Future<AuthController> signedIn(FakeAuthApi api) async {
  final auth = AuthController(api: api, store: MemoryTokenStore());
  await auth.signIn('amani@example.com', 'password-123');
  return auth;
}

ApiException get networkDown => const ApiException(0, 'network');

/// The server's answer to a wrong password.
class ApiExceptionForTest extends ApiException {
  const ApiExceptionForTest() : super(401, 'invalid_credentials');
}
