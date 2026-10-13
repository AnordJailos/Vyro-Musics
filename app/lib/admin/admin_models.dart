/// Why a song can be rejected. The codes are the server's.
const rejectReasons = <String, String>{
  'copyright': 'Uses music the artist may not own',
  'duplicate': 'Duplicates another song',
  'low_quality': 'Audio quality too low',
  'explicit_not_marked': 'Explicit but not marked',
  'misleading': 'Misleading title or artist',
  'other': 'Does not meet the guidelines',
};

class DuplicateMatch {
  const DuplicateMatch({required this.title, required this.artistName, required this.similarity, required this.sameArtist, required this.status});

  final String title;
  final String artistName;
  final double similarity;
  final bool sameArtist;
  final String status;

  factory DuplicateMatch.fromJson(Map<String, Object?> j) => DuplicateMatch(
        title: (j['title'] as String?) ?? '',
        artistName: (j['artistName'] as String?) ?? '',
        similarity: (j['similarity'] as num?)?.toDouble() ?? 0,
        sameArtist: j['sameArtist'] == true,
        status: (j['status'] as String?) ?? '',
      );
}

class ExternalMatch {
  const ExternalMatch({required this.title, required this.artists, required this.score});

  final String title;
  final List<String> artists;
  final double score;

  factory ExternalMatch.fromJson(Map<String, Object?> j) => ExternalMatch(
        title: (j['title'] as String?) ?? '',
        artists: [for (final a in (j['artists'] as List? ?? const [])) '$a'],
        score: (j['score'] as num?)?.toDouble() ?? 0,
      );
}

/// What the automatic checks found for a song waiting for review.
class ReviewChecks {
  const ReviewChecks({this.fingerprinted = false, this.duplicates = const [], this.externalStatus = 'off', this.externalMatches = const []});

  final bool fingerprinted;
  final List<DuplicateMatch> duplicates;
  final String externalStatus; // off, unchecked, clean or matches
  final List<ExternalMatch> externalMatches;

  factory ReviewChecks.fromJson(Map<String, Object?>? j) {
    if (j == null || j.isEmpty) return const ReviewChecks();
    final external = (j['external'] as Map?)?.cast<String, Object?>() ?? const {};
    return ReviewChecks(
      fingerprinted: j['fingerprinted'] == true,
      duplicates: [for (final d in (j['duplicates'] as List? ?? const [])) DuplicateMatch.fromJson((d as Map).cast<String, Object?>())],
      externalStatus: (external['status'] as String?) ?? 'off',
      externalMatches: [for (final m in (external['matches'] as List? ?? const [])) ExternalMatch.fromJson((m as Map).cast<String, Object?>())],
    );
  }
}

class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.title,
    required this.status,
    required this.artistId,
    required this.artistName,
    this.artistVerified = false,
    this.strikes = 0,
    this.publishedCount = 0,
    this.genre = 'other',
    this.explicit = false,
    this.durationMs = 0,
    this.codec,
    this.bitrateKbps,
    this.lossless = false,
    this.loudnessLufs,
    this.checks = const ReviewChecks(),
  });

  final String id;
  final String title;
  final String status; // in_review or held
  final String artistId;
  final String artistName;
  final bool artistVerified;
  final int strikes;
  final int publishedCount;
  final String genre;
  final bool explicit;
  final int durationMs;
  final String? codec;
  final int? bitrateKbps;
  final bool lossless;
  final double? loudnessLufs;
  final ReviewChecks checks;

  factory ReviewItem.fromJson(Map<String, Object?> j) {
    final artist = (j['artist'] as Map).cast<String, Object?>();
    return ReviewItem(
      id: j['id'] as String,
      title: j['title'] as String,
      status: j['status'] as String,
      artistId: artist['id'] as String,
      artistName: artist['stageName'] as String,
      artistVerified: artist['verified'] == true,
      strikes: (artist['strikes'] as num?)?.toInt() ?? 0,
      publishedCount: (artist['publishedCount'] as num?)?.toInt() ?? 0,
      genre: (j['genre'] as String?) ?? 'other',
      explicit: j['explicit'] == true,
      durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
      codec: j['codec'] as String?,
      bitrateKbps: (j['bitrateKbps'] as num?)?.toInt(),
      lossless: j['lossless'] == true,
      loudnessLufs: (j['loudnessLufs'] as num?)?.toDouble(),
      checks: ReviewChecks.fromJson((j['checks'] as Map?)?.cast<String, Object?>()),
    );
  }
}

class TakedownNotice {
  const TakedownNotice({
    required this.id,
    required this.status,
    required this.trackTitle,
    required this.artistName,
    required this.claimantName,
    required this.claimantEmail,
    required this.statement,
    this.strikes = 0,
    this.claimantCompany,
    this.counterStatement,
  });

  final String id;
  final String status; // open or counter_filed
  final String trackTitle;
  final String artistName;
  final int strikes;
  final String claimantName;
  final String claimantEmail;
  final String? claimantCompany;
  final String statement;
  final String? counterStatement;

  factory TakedownNotice.fromJson(Map<String, Object?> j) {
    final track = (j['track'] as Map).cast<String, Object?>();
    final artist = (j['artist'] as Map).cast<String, Object?>();
    final claimant = (j['claimant'] as Map).cast<String, Object?>();
    final counter = (j['counter'] as Map?)?.cast<String, Object?>();
    return TakedownNotice(
      id: j['id'] as String,
      status: j['status'] as String,
      trackTitle: track['title'] as String,
      artistName: artist['stageName'] as String,
      strikes: (artist['strikes'] as num?)?.toInt() ?? 0,
      claimantName: claimant['name'] as String,
      claimantEmail: claimant['email'] as String,
      claimantCompany: claimant['company'] as String?,
      statement: j['statement'] as String,
      counterStatement: counter?['statement'] as String?,
    );
  }
}

class AdminArtist {
  const AdminArtist({required this.id, required this.stageName, required this.username, this.verified = false, this.suspended = false, this.suspensionReason, this.strikes = 0, this.trackCount = 0});

  final String id;
  final String stageName;
  final String username;
  final bool verified;
  final bool suspended;
  final String? suspensionReason;
  final int strikes;
  final int trackCount;

  factory AdminArtist.fromJson(Map<String, Object?> j) => AdminArtist(
        id: j['id'] as String,
        stageName: j['stageName'] as String,
        username: j['username'] as String,
        verified: j['verified'] == true,
        suspended: j['suspended'] == true,
        suspensionReason: j['suspensionReason'] as String?,
        strikes: (j['strikes'] as num?)?.toInt() ?? 0,
        trackCount: (j['trackCount'] as num?)?.toInt() ?? 0,
      );
}
