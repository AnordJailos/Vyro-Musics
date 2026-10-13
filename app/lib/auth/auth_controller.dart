import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_errors.dart';
import 'auth_api.dart';
import 'auth_models.dart';
import 'social_sign_in.dart';
import 'token_store.dart';

enum AuthStatus { starting, signedOut, guest, signedIn }

/// Who is using the app: signed out, a guest, or a signed-in person. Keeps the
/// login between launches and refreshes the access token when it expires.
class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.store, ApiSession? session, this.deviceName}) : session = session ?? ApiSession() {
    this.session.onUnauthorized = _refreshTokens;
  }

  final AuthApi api;
  final TokenStore store;
  final ApiSession session;
  final String? deviceName;

  AuthStatus _status = AuthStatus.starting;
  UserProfile? _user;
  PendingProfile? _pending;
  String? _refreshToken;
  Future<bool>? _refreshing;
  bool _offline = false;

  AuthStatus get status => _status;
  UserProfile? get user => _user;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get isGuest => _status == AuthStatus.guest;

  /// True when the app opened without reaching the server and is showing the last known profile.
  bool get isOffline => _offline;

  /// Set after a phone or social sign-in that still needs a profile.
  PendingProfile? get pending => _pending;

  void _set(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  /// Called once at start-up: picks the saved login back up.
  Future<void> restore() async {
    final token = await store.readRefreshToken();
    if (token == null) {
      _set(AuthStatus.signedOut);
      return;
    }
    _refreshToken = token;
    try {
      await _doRefresh();
      await _setUser(await api.me());
      _offline = false;
      _set(AuthStatus.signedIn);
    } on ApiException catch (e) {
      if (e.isNetwork) {
        final cached = await store.readProfile();
        if (cached != null) {
          _user = cached;
          _offline = true;
          _set(AuthStatus.signedIn);
          return;
        }
        _set(AuthStatus.signedOut);
        return;
      }
      await _expire();
    }
  }

  Future<void> _doRefresh() async {
    final token = _refreshToken;
    if (token == null) throw const ApiException(401, 'invalid_refresh_token');
    final tokens = await api.refresh(token);
    _refreshToken = tokens.refreshToken;
    session.accessToken = tokens.accessToken;
    await store.saveRefreshToken(tokens.refreshToken);
  }

  // Used by the HTTP client when the server says the access token ran out.
  // Several requests failing together share one refresh.
  Future<bool> _refreshTokens() {
    return _refreshing ??= () async {
      try {
        await _doRefresh();
        return true;
      } on ApiException catch (e) {
        if (e.isUnauthorized) await _expire();
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<void> _expire() async {
    await _clearLocal();
    _set(AuthStatus.signedOut);
  }

  Future<void> _clearLocal() async {
    _refreshToken = null;
    session.accessToken = null;
    _user = null;
    _pending = null;
    _offline = false;
    await store.clear();
  }

  Future<void> _setUser(UserProfile user) async {
    _user = user;
    await store.saveProfile(user);
  }

  Future<void> _adopt(Session s) async {
    _refreshToken = s.tokens.refreshToken;
    session.accessToken = s.tokens.accessToken;
    _pending = null;
    _offline = false;
    await store.saveRefreshToken(s.tokens.refreshToken);
    await _setUser(s.user);
    _set(AuthStatus.signedIn);
  }

  // ---- ways in -------------------------------------------------------------

  Future<void> signUp(RegisterRequest request) async => _adopt(await api.register(request));

  Future<void> signIn(String email, String password) async => _adopt(await api.login(email, password, deviceName: deviceName));

  void continueAsGuest() => _set(AuthStatus.guest);

  /// A guest who wants to sign in goes back to the welcome screen.
  void leaveGuest() => _set(AuthStatus.signedOut);

  Future<void> requestPhoneCode(String phone) => api.requestPhoneCode(phone);

  Future<SignInOutcome> verifyPhoneCode(String phone, String code) async => _finish(await api.verifyPhoneCode(phone, code, deviceName: deviceName));

  Future<SignInOutcome> signInSocial(SocialProvider provider, String idToken) async => _finish(await api.signInSocial(provider.name, idToken, deviceName: deviceName));

  Future<SignInOutcome> _finish(SignInOutcome outcome) async {
    final s = outcome.session;
    if (s != null) {
      await _adopt(s);
    } else {
      _pending = outcome.pending;
      notifyListeners();
    }
    return outcome;
  }

  Future<void> completeProfile(CompleteProfileRequest request) async {
    final p = _pending;
    if (p == null) throw const ApiException(401, 'invalid_signup_token');
    await _adopt(await api.completeProfile(p.signupToken, request));
  }

  Future<void> requestPasswordReset(String email) => api.requestPasswordReset(email);
  Future<void> confirmPasswordReset(String email, String code, String newPassword) => api.confirmPasswordReset(email, code, newPassword);

  // ---- signed-in actions ------------------------------------------------------

  Future<void> refreshUser() async {
    await _setUser(await api.me());
    notifyListeners();
  }

  Future<void> verifyEmail(String code) => _update(api.verifyEmail(code));
  Future<void> resendEmail() => api.resendEmail();
  Future<void> confirmParentConsent(String code) => _update(api.confirmParentConsent(code));
  Future<void> resendParentConsent() => api.resendParentConsent();

  Future<void> updateProfile({String? displayName, String? username, String? country, String? language}) =>
      _update(api.updateProfile(displayName: displayName, username: username, country: country, language: language));

  Future<void> updateSettings({bool? explicitAllowed, bool? privateSession, bool? hideActivity, bool? shareListening, bool? personalization}) =>
      _update(api.updateSettings(
        explicitAllowed: explicitAllowed,
        privateSession: privateSession,
        hideActivity: hideActivity,
        shareListening: shareListening,
        personalization: personalization,
      ));

  Future<List<SuggestedArtist>> suggestedArtists() => api.suggestedArtists();

  Future<void> saveTaste({List<String> genres = const [], List<String> moods = const [], List<String> artistIds = const []}) =>
      _update(api.saveTaste(genres: genres, moods: moods, artistIds: artistIds));

  Future<void> becomeArtist(ArtistRequest request) => _update(api.becomeArtist(request));

  Future<void> _update(Future<UserProfile> call) async {
    await _setUser(await call);
    notifyListeners();
  }

  Future<void> signOut() async {
    final token = _refreshToken;
    if (token != null) {
      try {
        await api.logout(token);
      } on ApiException {
        // Signing out always works on this device, even without a connection.
      }
    }
    await _clearLocal();
    _set(AuthStatus.signedOut);
  }

  Future<void> deleteAccount({String? password}) async {
    await api.deleteAccount(password: password);
    await _clearLocal();
    _set(AuthStatus.signedOut);
  }
}
