import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_models.dart';

/// Where the login survives between launches.
abstract class TokenStore {
  Future<String?> readRefreshToken();
  Future<void> saveRefreshToken(String token);

  /// The last known profile, so the app can open offline.
  Future<UserProfile?> readProfile();
  Future<void> saveProfile(UserProfile profile);
  Future<void> clear();
}

class MemoryTokenStore implements TokenStore {
  String? _token;
  UserProfile? _profile;

  @override
  Future<String?> readRefreshToken() async => _token;
  @override
  Future<void> saveRefreshToken(String token) async => _token = token;
  @override
  Future<UserProfile?> readProfile() async => _profile;
  @override
  Future<void> saveProfile(UserProfile profile) async => _profile = profile;
  @override
  Future<void> clear() async {
    _token = null;
    _profile = null;
  }
}

/// The system's secure storage (Keychain, Keystore, and so on). If a platform
/// refuses it, the app keeps working with the login held in memory only, so the
/// person is simply asked to log in again next launch.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? FlutterSecureStorage();

  static const _tokenKey = 'vyro.refresh_token';
  static const _profileKey = 'vyro.profile';

  final FlutterSecureStorage _storage;
  final MemoryTokenStore _fallback = MemoryTokenStore();
  bool _broken = false;

  /// True while values really are saved on the device.
  bool get persistent => !_broken;

  Future<T> _guard<T>(Future<T> Function() secure, Future<T> Function() memory) async {
    if (_broken) return memory();
    try {
      return await secure();
    } catch (_) {
      _broken = true;
      return memory();
    }
  }

  @override
  Future<String?> readRefreshToken() => _guard(() => _storage.read(key: _tokenKey), _fallback.readRefreshToken);

  @override
  Future<void> saveRefreshToken(String token) {
    // Kept in memory as well, so a storage failure halfway does not lose the login.
    _fallback.saveRefreshToken(token);
    return _guard(() => _storage.write(key: _tokenKey, value: token), () async {});
  }

  @override
  Future<UserProfile?> readProfile() => _guard(() async {
        final text = await _storage.read(key: _profileKey);
        if (text == null) return null;
        return UserProfile.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
      }, _fallback.readProfile);

  @override
  Future<void> saveProfile(UserProfile profile) {
    _fallback.saveProfile(profile);
    return _guard(() => _storage.write(key: _profileKey, value: jsonEncode(profile.toJson())), () async {});
  }

  @override
  Future<void> clear() async {
    await _fallback.clear();
    await _guard(() async {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _profileKey);
    }, () async {});
  }
}
