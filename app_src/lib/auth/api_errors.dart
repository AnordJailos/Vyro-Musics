/// An error from the server (or from not reaching it). [status] is 0 when the
/// network failed; [code] is the server's short error name.
class ApiException implements Exception {
  const ApiException(this.status, this.code);

  final int status;
  final String code;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;
  String get message => describeError(code);

  @override
  String toString() => 'ApiException($status, $code)';
}

/// Plain-language text for every error the account screens can meet.
String describeError(String code) {
  switch (code) {
    case 'network':
      return "Can't reach Vyro right now. Check your connection and try again.";
    case 'invalid_credentials':
      return "That email and password don't match.";
    case 'email_or_username_taken':
      return 'That email or username is already taken.';
    case 'username_taken':
      return 'That username is already taken.';
    case 'too_young':
      return 'Vyro is for people aged 13 and over.';
    case 'parent_email_required':
      return "Enter a parent or guardian's email.";
    case 'parent_email_must_differ':
      return "The parent's email must be different from yours.";
    case 'invalid_birth_date':
      return 'Check the date of birth.';
    case 'invalid_code':
      return "That code isn't right.";
    case 'code_expired':
      return 'That code has expired. Ask for a new one.';
    case 'too_many_attempts':
      return 'Too many wrong tries. Ask for a new code.';
    case 'too_many_codes':
      return 'Too many codes asked for. Try again in an hour.';
    case 'Too Many Requests':
      return 'Too many tries. Please wait a minute.';
    case 'invalid_token':
    case 'invalid_signup_token':
      return 'That sign-in did not work. Please try again.';
    case 'provider_email_unverified':
      return "That account's email has not been confirmed with the provider.";
    case 'social_not_configured':
      return 'This sign-in method is not set up yet.';
    case 'password_required':
      return 'Enter your password to confirm.';
    case 'verify_contact_first':
      return 'Confirm your email or phone first.';
    case 'parent_consent_pending':
      return 'Your parent or guardian needs to give permission first.';
    case 'artist_requires_adult':
      return 'Artist accounts are for people aged 18 and over.';
    case 'stage_name_taken':
      return 'That artist name is too close to one that already exists.';
    case 'already_artist':
      return "You're already an artist.";
    case 'age_restricted':
      return "Explicit content isn't available for your age.";
    case 'unauthorized':
    case 'invalid_refresh_token':
      return 'Please log in again.';
    case 'unsupported_audio':
      return 'That file is not a supported audio file. Use MP3, M4A, FLAC, WAV, OGG or AIFF.';
    case 'too_short':
      return 'Songs must be at least 10 seconds long.';
    case 'too_long':
      return 'That file is longer than 6 hours.';
    case 'bitrate_too_low':
      return 'The audio quality is too low. Upload at 128 kbps or better, or a lossless file.';
    case 'sample_rate_too_low':
      return 'The sample rate is too low. Use at least 22.05 kHz.';
    case 'file_too_large':
      return 'That file is too large.';
    case 'unsupported_image':
      return 'The cover must be a JPEG, PNG or WebP picture.';
    case 'upload_audio_first':
      return 'Upload the audio before publishing.';
    case 'explicit_not_allowed':
      return 'This song is marked explicit, and explicit content is turned off for your account.';
    case 'not_found':
      return 'That could not be found.';
    case 'invalid_request':
      return 'Please check what you entered.';
    default:
      return 'Something went wrong. Please try again.';
  }
}
