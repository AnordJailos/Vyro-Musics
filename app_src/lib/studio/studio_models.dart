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
  });

  final String id;
  final String title;
  final String status; // draft, ready or published
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

  bool get isLive => status == 'published';

  String get statusLabel => switch (status) {
        'published' => 'Live',
        'ready' => 'Ready to publish',
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
      );
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
