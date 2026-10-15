import '../audio/playback_snapshot.dart' show trackFromJson, trackToJson;
import '../audio/track.dart';

/// One song in a playlist. The same song can appear twice, so every entry has its own id.
class PlaylistEntry {
  const PlaylistEntry({required this.id, required this.track, required this.addedAt});

  final String id;
  final Track track;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {'id': id, 'addedAt': addedAt.toUtc().toIso8601String(), 'track': trackToJson(track)};

  factory PlaylistEntry.fromJson(Map<String, Object?> j, {Track Function(Track)? attach}) {
    final track = trackFromJson((j['track'] as Map).cast<String, Object?>());
    return PlaylistEntry(id: j['id'] as String, track: attach == null ? track : attach(track), addedAt: DateTime.parse(j['addedAt'] as String));
  }
}

enum PlaylistSort { title, artist, dateAdded, duration }

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.coverPath,
    this.entries = const [],
  });

  final String id;
  final String name;
  final String description;

  /// A picture chosen by the person, kept in the app's own folder.
  final String? coverPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PlaylistEntry> entries;

  List<Track> get tracks => [for (final e in entries) e.track];

  /// The length of the songs whose length is known.
  Duration get totalDuration => entries.fold(Duration.zero, (sum, e) => sum + (e.track.duration ?? Duration.zero));

  bool contains(String trackId) => entries.any((e) => e.track.id == trackId);

  Playlist copyWith({String? name, String? description, Object? coverPath = _keep, DateTime? updatedAt, List<PlaylistEntry>? entries}) => Playlist(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        coverPath: identical(coverPath, _keep) ? this.coverPath : coverPath as String?,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        entries: entries ?? this.entries,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'coverPath': coverPath,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'entries': [for (final e in entries) e.toJson()],
      };

  factory Playlist.fromJson(Map<String, Object?> j, {Track Function(Track)? attach}) => Playlist(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        coverPath: j['coverPath'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        entries: [for (final e in (j['entries'] as List? ?? const [])) PlaylistEntry.fromJson((e as Map).cast<String, Object?>(), attach: attach)],
      );
}

const Object _keep = Object();
