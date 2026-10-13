class LyricLine {
  const LyricLine(this.timeMs, this.text);

  /// When the line starts, in milliseconds. Null for plain (unsynced) lyrics.
  final int? timeMs;
  final String text;
}

class Lyrics {
  const Lyrics({required this.synced, required this.lines});

  final bool synced;
  final List<LyricLine> lines;

  /// Nothing worth showing: no lines, or only blank ones.
  bool get isEmpty => lines.every((l) => l.text.isEmpty);
}

final _stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
final _leadingStamps = RegExp(r'^(?:\s*\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\])+');
final _tagLine = RegExp(r'^\[([A-Za-z#]+):(.*)\]$');
final _wordStamp = RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>');

class _Stamped {
  _Stamped(this.timeMs, this.text, this.order);
  final int timeMs;
  final String text;
  final int order;
}

/// Reads lyrics in the LRC format ("[01:23.45] a line"): several time stamps on one line, the [offset:+500] tag
/// (positive shows lyrics sooner), and word-by-word stamps (ignored). Text without time stamps is plain lyrics.
/// This follows the same rules as the server, so a song shows the same lyrics wherever they come from.
Lyrics parseLyrics(String raw) {
  final text = raw.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  var offset = 0;
  final stamped = <_Stamped>[];
  final plain = <String>[];
  var order = 0;

  for (final original in text.split('\n')) {
    final line = original.trim();
    final tag = _tagLine.firstMatch(line);
    if (tag != null && !RegExp(r'^\d').hasMatch(tag.group(1)!)) {
      if (tag.group(1)!.toLowerCase() == 'offset') {
        final n = int.tryParse(tag.group(2)!.trim());
        if (n != null) offset = n;
      }
      continue; // title, artist, album and other tags are not lyrics
    }
    final lead = _leadingStamps.firstMatch(line);
    if (lead == null) {
      plain.add(original.trimRight());
      continue;
    }
    final content = line.substring(lead.group(0)!.length).replaceAll(_wordStamp, '').trim();
    for (final m in _stamp.allMatches(lead.group(0)!)) {
      final minutes = int.parse(m.group(1)!);
      final seconds = int.parse(m.group(2)!);
      final fraction = m.group(3);
      final ms = fraction == null ? 0 : int.parse(fraction.padRight(3, '0'));
      final at = (minutes * 60 + seconds) * 1000 + ms - offset;
      stamped.add(_Stamped(at < 0 ? 0 : at, content, order++));
    }
  }

  if (stamped.isNotEmpty) {
    stamped.sort((a, b) => a.timeMs != b.timeMs ? a.timeMs.compareTo(b.timeMs) : a.order.compareTo(b.order));
    final lines = <LyricLine>[];
    for (final s in stamped) {
      final previous = lines.isEmpty ? null : lines.last;
      if (s.text.isEmpty && (previous == null || previous.text.isEmpty)) continue; // no leading or doubled gaps
      lines.add(LyricLine(s.timeMs, s.text));
    }
    return Lyrics(synced: true, lines: lines);
  }

  final lines = <LyricLine>[];
  for (final p in plain) {
    if (p.isEmpty && (lines.isEmpty || lines.last.text.isEmpty)) continue;
    lines.add(LyricLine(null, p));
  }
  while (lines.isNotEmpty && lines.last.text.isEmpty) {
    lines.removeLast();
  }
  return Lyrics(synced: false, lines: lines);
}

/// The line being sung at [position]: the last one that has started. -1 before the first line.
int currentLineIndex(Lyrics lyrics, Duration position) {
  if (!lyrics.synced || lyrics.lines.isEmpty) return -1;
  final ms = position.inMilliseconds;
  var low = 0;
  var high = lyrics.lines.length - 1;
  var found = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if ((lyrics.lines[mid].timeMs ?? 0) <= ms) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return found;
}
