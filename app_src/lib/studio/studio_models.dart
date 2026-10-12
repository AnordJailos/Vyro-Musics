import 'dart:convert';

/// One of the artist's own songs, as the Studio shows it.
class StudioTrack {
  const StudioTrack({
    required this.id,
    required this.title,
    required this.status,
    this.genre = 'other',
    this.durationMs = 0,
    this.explicit = false,
    this.allowMixing = true,
    this.hasAudio = false,
    this.hasCover = false,
    this.codec,
    this.bitrateKbps,
    this.lossless = false,
    this.loudnessLufs,
    this.rejectReason,
    this.reviewNote,
    this.hasLyrics = false,
  });

  final String id;
  final String title;
  final String status; // draft, ready, in_review, held, published, rejected or taken_down
  final String genre;
  final int durationMs;
  final bool explicit;
  final bool allowMixing;
  final bool hasAudio;
  final bool hasCover;
  final String? codec;
  final int? bitrateKbps;
  final bool lossless;
  final double? loudnessLufs;
  final String? rejectReason;
  final String? reviewNote;
  final bool hasLyrics;

  bool get isLive => status == 'published';

  /// Submitted and waiting for a person (or a copyright check) to decide.
  bool get isWaiting => status == 'in_review' || status == 'held';

  bool get isTakenDown => status == 'taken_down';

  /// Can be sent for release: it has audio and is not already live, waiting or taken down.
  bool get canSubmit => hasAudio && (status == 'ready' || status == 'rejected');

  String get statusLabel => switch (status) {
        'published' => 'Live',
        'in_review' => 'In review',
        'held' => 'On hold for a copyright check',
        'rejected' => 'Not approved',
        'taken_down' => 'Taken down',
        'ready' => 'Ready to submit',
        _ => 'Draft',
      };

  factory StudioTrack.fromJson(Map<String, Object?> j) => StudioTrack(
        id: j['id'] as String,
        title: j['title'] as String,
        status: j['status'] as String,
        genre: (j['genre'] as String?) ?? 'other',
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        explicit: j['explicit'] == true,
        allowMixing: j['allowMixing'] != false,
        hasAudio: j['hasAudio'] == true,
        hasCover: j['hasCover'] == true,
        codec: j['codec'] as String?,
        bitrateKbps: (j['bitrateKbps'] as num?)?.toInt(),
        lossless: j['lossless'] == true,
        loudnessLufs: (j['loudnessLufs'] as num?)?.toDouble(),
        rejectReason: j['rejectReason'] as String?,
        reviewNote: j['reviewNote'] as String?,
        hasLyrics: j['hasLyrics'] == true,
      );
}

/// Why a song was not approved, in words an artist can act on.
String rejectReasonText(String? code) => switch (code) {
      'copyright' => 'it appears to use music you do not have the rights to',
      'duplicate' => 'it duplicates another song on Vyro',
      'low_quality' => 'the audio quality is too low',
      'explicit_not_marked' => 'it has explicit content that was not marked explicit',
      'misleading' => 'the title or artist name is misleading',
      _ => 'it does not meet our guidelines',
    };

/// A copyright notice about one of the artist's songs.
class TakedownInfo {
  const TakedownInfo({required this.id, required this.status, required this.trackId, required this.trackTitle, required this.claimantName, required this.statement});

  final String id;
  final String status; // open, counter_filed, upheld or restored
  final String trackId;
  final String trackTitle;
  final String claimantName;
  final String statement;

  factory TakedownInfo.fromJson(Map<String, Object?> j) {
    final track = (j['track'] as Map).cast<String, Object?>();
    return TakedownInfo(
      id: j['id'] as String,
      status: j['status'] as String,
      trackId: track['id'] as String,
      trackTitle: track['title'] as String,
      claimantName: (j['claimantName'] as String?) ?? '',
      statement: (j['statement'] as String?) ?? '',
    );
  }
}

/// The lyrics an artist saved, as they wrote them.
class LyricsDraft {
  const LyricsDraft({required this.text, required this.synced});
  final String text;
  final bool synced;
}

/// What the server made of lyrics that were just saved.
class LyricsSaved {
  const LyricsSaved({required this.synced, required this.lineCount});
  final bool synced;
  final int lineCount;
}

/// Reads a small text file the artist chose (a .lrc or .txt file with lyrics).
Future<String> readPickedText(PickedFile file, {int maxBytes = 200 * 1024}) async {
  if (file.length > maxBytes) throw const FormatException('That file is too large to be lyrics.');
  final bytes = <int>[];
  await for (final chunk in file.open()) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) throw const FormatException('That file is too large to be lyrics.');
  }
  return utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
}

/// A file the artist chose. Read as a stream, so large files never sit in memory.
class PickedFile {
  const PickedFile({required this.name, required this.length, required this.open});

  final String name;
  final int length;
  final Stream<List<int>> Function() open;

  /// "01 - My_Song.mp3" becomes "My Song".
  String get suggestedTitle {
    final dot = name.lastIndexOf('.');
    var t = dot > 0 ? name.substring(0, dot) : name;
    t = t.replaceFirst(RegExp(r'^\d{1,3}\s*[-._]\s*'), '').replaceAll('_', ' ').trim();
    return t.isEmpty ? name : t;
  }
}
