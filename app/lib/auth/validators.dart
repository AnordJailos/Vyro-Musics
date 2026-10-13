/// Form checks. The server repeats every one of these and is the authority;
/// these only save a round trip and explain problems early.
final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'Enter your email.';
  if (!_emailRe.hasMatch(t)) return 'That email does not look right.';
  return null;
}

String? validatePassword(String? v) {
  final t = v ?? '';
  if (t.length < 8) return 'Use at least 8 characters.';
  if (t.length > 128) return 'That password is too long.';
  return null;
}

String? validateUsername(String? v) {
  if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(v ?? '')) return '3 to 24 characters: lowercase letters, numbers and _.';
  return null;
}

String? validateName(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'Enter a name.';
  if (t.length > 60) return 'That name is too long.';
  return null;
}

String? validateCode(String? v) => RegExp(r'^\d{6}$').hasMatch((v ?? '').trim()) ? null : 'Enter the 6-digit code.';

String normalizePhone(String s) => s.replaceAll(RegExp(r'[\s().-]'), '');

String? validatePhone(String? v) {
  if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(normalizePhone(v ?? ''))) {
    return 'Use international format: a + followed by the country code and number.';
  }
  return null;
}

/// Whole years on [now] for someone born on [birth].
int ageOn(DateTime birth, DateTime now) {
  var age = now.year - birth.year;
  final hadBirthday = now.month > birth.month || (now.month == birth.month && now.day >= birth.day);
  if (!hadBirthday) age -= 1;
  return age;
}

enum AgeBand { tooYoung, needsParent, minor, adult }

/// The same bands as the server: under 13 cannot join, 13 to 15 need a parent's
/// permission, under 18 are minors. These numbers need legal review per market.
AgeBand ageBandOf(int age) {
  if (age < 13) return AgeBand.tooYoung;
  if (age < 16) return AgeBand.needsParent;
  if (age < 18) return AgeBand.minor;
  return AgeBand.adult;
}

String formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}
