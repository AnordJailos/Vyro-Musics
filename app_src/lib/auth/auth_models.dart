class UserSettings {
  const UserSettings({
    this.explicitAllowed = true,
    this.privateSession = false,
    this.hideActivity = false,
    this.shareListening = true,
    this.personalization = true,
  });

  final bool explicitAllowed;
  final bool privateSession;
  final bool hideActivity;
  final bool shareListening;
  final bool personalization;

  factory UserSettings.fromJson(Map<String, Object?> j) => UserSettings(
        explicitAllowed: j['explicitAllowed'] != false,
        privateSession: j['privateSession'] == true,
        hideActivity: j['hideActivity'] == true,
        shareListening: j['shareListening'] != false,
        personalization: j['personalization'] != false,
      );

  Map<String, Object?> toJson() => {
        'explicitAllowed': explicitAllowed,
        'privateSession': privateSession,
        'hideActivity': hideActivity,
        'shareListening': shareListening,
        'personalization': personalization,
      };
}

class ArtistInfo {
  const ArtistInfo({required this.stageName, this.bio = '', this.artistType = 'solo', this.verified = false, this.genres = const [], this.links = const []});

  final String stageName;
  final String bio;
  final String artistType;
  final bool verified;
  final List<String> genres;
  final List<String> links;

  factory ArtistInfo.fromJson(Map<String, Object?> j) => ArtistInfo(
        stageName: j['stageName'] as String,
        bio: (j['bio'] as String?) ?? '',
        artistType: (j['artistType'] as String?) ?? 'solo',
        verified: j['verified'] == true,
        genres: [for (final g in (j['genres'] as List? ?? const [])) g as String],
        links: [for (final l in (j['links'] as List? ?? const [])) l as String],
      );

  Map<String, Object?> toJson() => {'stageName': stageName, 'bio': bio, 'artistType': artistType, 'verified': verified, 'genres': genres, 'links': links};
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.username,
    this.email,
    this.phone,
    this.country,
    this.language = 'en',
    this.emailVerified = false,
    this.phoneVerified = false,
    this.hasPassword = true,
    this.isMinor = false,
    this.parentConsent = 'not_needed',
    this.settings = const UserSettings(),
    this.tasteSet = false,
    this.artist,
  });

  final String id;
  final String displayName;
  final String username;
  final String? email;
  final String? phone;
  final String? country;
  final String language;
  final bool emailVerified;
  final bool phoneVerified;
  final bool hasPassword;
  final bool isMinor;
  final String parentConsent; // not_needed, pending or granted
  final UserSettings settings;
  final bool tasteSet;
  final ArtistInfo? artist;

  bool get isArtist => artist != null;
  bool get contactVerified => emailVerified || phoneVerified;
  bool get needsEmailCheck => email != null && !emailVerified;
  bool get parentPending => parentConsent == 'pending';

  factory UserProfile.fromJson(Map<String, Object?> j) {
    final artist = j['artist'] as Map?;
    final settings = j['settings'] as Map?;
    return UserProfile(
      id: j['id'] as String,
      displayName: j['displayName'] as String,
      username: j['username'] as String,
      email: j['email'] as String?,
      phone: j['phone'] as String?,
      country: j['country'] as String?,
      language: (j['language'] as String?) ?? 'en',
      emailVerified: j['emailVerified'] == true,
      phoneVerified: j['phoneVerified'] == true,
      hasPassword: j['hasPassword'] != false,
      isMinor: j['isMinor'] == true,
      parentConsent: (j['parentConsent'] as String?) ?? 'not_needed',
      settings: settings == null ? const UserSettings() : UserSettings.fromJson(settings.cast<String, Object?>()),
      tasteSet: j['tasteSet'] == true,
      artist: artist == null ? null : ArtistInfo.fromJson(artist.cast<String, Object?>()),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'username': username,
        'email': email,
        'phone': phone,
        'country': country,
        'language': language,
        'emailVerified': emailVerified,
        'phoneVerified': phoneVerified,
        'hasPassword': hasPassword,
        'isMinor': isMinor,
        'parentConsent': parentConsent,
        'settings': settings.toJson(),
        'tasteSet': tasteSet,
        'artist': artist?.toJson(),
      };
}

class AuthTokens {
  const AuthTokens(this.accessToken, this.refreshToken);
  final String accessToken;
  final String refreshToken;
}

class Session {
  const Session(this.user, this.tokens);
  final UserProfile user;
  final AuthTokens tokens;
}

/// Someone who proved a phone number or a social account but has no profile yet.
class PendingProfile {
  const PendingProfile({required this.signupToken, this.suggestedEmail});
  final String signupToken;
  final String? suggestedEmail;
}

/// Either a finished sign-in or a request to complete the profile.
class SignInOutcome {
  const SignInOutcome.signedIn(Session this.session) : pending = null;
  const SignInOutcome.needsProfile(PendingProfile this.pending) : session = null;

  final Session? session;
  final PendingProfile? pending;
}

class SuggestedArtist {
  const SuggestedArtist({required this.id, required this.stageName, this.genres = const [], this.followers = 0});
  final String id;
  final String stageName;
  final List<String> genres;
  final int followers;
}

class RegisterRequest {
  const RegisterRequest({
    required this.email,
    required this.password,
    required this.displayName,
    required this.username,
    required this.birthDate,
    required this.acceptedTermsVersion,
    this.country,
    this.language = 'en',
    this.parentEmail,
    this.deviceName,
  });

  final String email;
  final String password;
  final String displayName;
  final String username;
  final String birthDate; // YYYY-MM-DD
  final String acceptedTermsVersion;
  final String? country;
  final String language;
  final String? parentEmail;
  final String? deviceName;

  Map<String, Object?> toJson() => {
        'email': email,
        'password': password,
        'displayName': displayName,
        'username': username,
        'birthDate': birthDate,
        'acceptedTermsVersion': acceptedTermsVersion,
        if (country != null) 'country': country,
        'language': language,
        if (parentEmail != null) 'parentEmail': parentEmail,
        if (deviceName != null) 'deviceName': deviceName,
      };
}

class CompleteProfileRequest {
  const CompleteProfileRequest({
    required this.displayName,
    required this.username,
    required this.birthDate,
    required this.acceptedTermsVersion,
    this.country,
    this.language = 'en',
    this.parentEmail,
    this.deviceName,
  });

  final String displayName;
  final String username;
  final String birthDate;
  final String acceptedTermsVersion;
  final String? country;
  final String language;
  final String? parentEmail;
  final String? deviceName;

  Map<String, Object?> toJson(String signupToken) => {
        'signupToken': signupToken,
        'displayName': displayName,
        'username': username,
        'birthDate': birthDate,
        'acceptedTermsVersion': acceptedTermsVersion,
        if (country != null) 'country': country,
        'language': language,
        if (parentEmail != null) 'parentEmail': parentEmail,
        if (deviceName != null) 'deviceName': deviceName,
      };
}

class ArtistRequest {
  const ArtistRequest({
    required this.stageName,
    required this.artistType,
    required this.agreementVersion,
    this.bio = '',
    this.genres = const [],
    this.links = const [],
  });

  final String stageName;
  final String artistType; // solo, group, producer_dj, label_manager
  final String agreementVersion;
  final String bio;
  final List<String> genres;
  final List<String> links;

  Map<String, Object?> toJson() => {
        'stageName': stageName,
        'artistType': artistType,
        'bio': bio,
        'genres': genres,
        'links': links,
        'rightsDeclaration': true, // the screen only submits after the person ticked it
        'agreementVersion': agreementVersion,
      };
}
