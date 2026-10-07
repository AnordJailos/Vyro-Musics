import '../audio/track.dart';

/// What the tag reader found inside an audio file (all optional).
class TagInfo {
  const TagInfo({this.title, this.artist, this.album, this.genre, this.duration, this.trackNumber, this.year});

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final Duration? duration;
  final int? trackNumber;
  final int? year;
}

/// One song found on the device. Stored in the library file and shown in the lists.
class LibraryTrack {
  const LibraryTrack({
    required this.id,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.durationMs,
    required this.trackNumber,
    required this.year,
    required this.sizeBytes,
    required this.modifiedMs,
    required this.addedMs,
  });

  final String id;
  final String path;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int durationMs;
  final int trackNumber;
  final int year;
  final int sizeBytes;
  final int modifiedMs;
  final int addedMs;

  Map<String, Object?> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'artist': artist,
        'album': album,
        'genre': genre,
        'durationMs': durationMs,
        'trackNumber': trackNumber,
        'year': year,
        'sizeBytes': sizeBytes,
        'modifiedMs': modifiedMs,
        'addedMs': addedMs,
      };

  factory LibraryTrack.fromJson(Map<String, Object?> json) => LibraryTrack(
        id: json['id'] as String,
        path: json['path'] as String,
        title: json['title'] as String,
        artist: (json['artist'] as String?) ?? 'Unknown artist',
        album: (json['album'] as String?) ?? 'Unknown album',
        genre: (json['genre'] as String?) ?? 'Unknown genre',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        trackNumber: (json['trackNumber'] as num?)?.toInt() ?? 0,
        year: (json['year'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        modifiedMs: (json['modifiedMs'] as num?)?.toInt() ?? 0,
        addedMs: (json['addedMs'] as num?)?.toInt() ?? 0,
      );

  /// The playable form handed to the player. Local files can be mixed.
  Track toPlayable() => Track(
        id: id,
        title: title,
        artist: artist,
        uri: Uri.file(path),
        source: TrackSource.local,
        duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
      );
}
