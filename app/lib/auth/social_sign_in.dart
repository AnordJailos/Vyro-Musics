enum SocialProvider { google, apple }

/// Gets an ID token from Google or Apple. The real version needs your Google
/// and Apple client IDs and the sign-in plugins; until then every provider is
/// reported as not set up and the buttons explain that.
abstract class SocialSignIn {
  bool isAvailable(SocialProvider provider);

  /// The provider's ID token, or null when the person cancels.
  Future<String?> idToken(SocialProvider provider);
}

class UnconfiguredSocialSignIn implements SocialSignIn {
  const UnconfiguredSocialSignIn();

  @override
  bool isAvailable(SocialProvider provider) => false;

  @override
  Future<String?> idToken(SocialProvider provider) async => null;
}
