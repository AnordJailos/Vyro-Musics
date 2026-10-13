import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'play_record.dart';

/// Where plays are kept on the device: the history itself, and an outbox of Vyro plays waiting to be sent.
abstract class HistoryStore {
  Future<List<PlayRecord>> loadAll();
  Future<void> append(PlayRecord record);

  /// Forgets the listening history on this device. Plays already waiting to be sent stay in the outbox.
  Future<void> clearHistory();

  Future<void> outboxAdd(PlayRecord record);
  Future<List<PlayRecord>> outboxPeek(int count);
  Future<void> outboxRemove(Set<String> ids);
}

const maxHistoryRecords = 20000;
const maxOutboxRecords = 5000;

class MemoryHistoryStore implements HistoryStore {
  final List<PlayRecord> _history = [];
  final List<PlayRecord> _outbox = [];

  @override
  Future<List<PlayRecord>> loadAll() async => List.of(_history);

  @override
  Future<void> append(PlayRecord record) async => _history.add(record);

  @override
  Future<void> clearHistory() async => _history.clear();

  @override
  Future<void> outboxAdd(PlayRecord record) async {
    _outbox.add(record);
    if (_outbox.length > maxOutboxRecords) _outbox.removeRange(0, _outbox.length - maxOutboxRecords);
  }

  @override
  Future<List<PlayRecord>> outboxPeek(int count) async => _outbox.take(count).toList();

  @override
  Future<void> outboxRemove(Set<String> ids) async => _outbox.removeWhere((r) => ids.contains(r.id));
}

/// History as one line of JSON per play (cheap to add to), and the outbox as a small JSON file.
class FileHistoryStore implements HistoryStore {
  FileHistoryStore({Future<Directory> Function()? directory}) : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  Future<void> _chain = Future<void>.value();

  // Everything that changes a file goes one after another, so two plays ending together cannot overwrite each other.
  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _chain.then((_) => job());
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<File> _file(String name) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<List<PlayRecord>> loadAll() => _serial(() async {
        final f = await _file('plays.jsonl');
        if (!await f.exists()) return <PlayRecord>[];
        final out = <PlayRecord>[];
        for (final line in await f.readAsLines()) {
          if (line.trim().isEmpty) continue;
          try {
            out.add(PlayRecord.fromJson((jsonDecode(line) as Map).cast<String, Object?>()));
          } catch (_) {
            // a damaged line is skipped; the rest of the history is still good
          }
        }
        if (out.length > maxHistoryRecords) {
          final kept = out.sublist(out.length - maxHistoryRecords);
          await f.writeAsString('${kept.map((r) => jsonEncode(r.toJson())).join('\n')}\n');
          return kept;
        }
        return out;
      });

  @override
  Future<void> append(PlayRecord record) => _serial(() async {
        final f = await _file('plays.jsonl');
        await f.writeAsString('${jsonEncode(record.toJson())}\n', mode: FileMode.append, flush: true);
      });

  @override
  Future<void> clearHistory() => _serial(() async {
        final f = await _file('plays.jsonl');
        if (await f.exists()) await f.delete();
      });

  Future<List<PlayRecord>> _readOutbox() async {
    final f = await _file('outbox.json');
    if (!await f.exists()) return [];
    try {
      return [for (final r in (jsonDecode(await f.readAsString()) as List)) PlayRecord.fromJson((r as Map).cast<String, Object?>())];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeOutbox(List<PlayRecord> records) async {
    final f = await _file('outbox.json');
    final temp = File('${f.path}.tmp');
    await temp.writeAsString(jsonEncode([for (final r in records) r.toJson()]));
    await temp.rename(f.path); // write then rename, so a crash never leaves half a file
  }

  @override
  Future<void> outboxAdd(PlayRecord record) => _serial(() async {
        final box = await _readOutbox()..add(record);
        await _writeOutbox(box.length > maxOutboxRecords ? box.sublist(box.length - maxOutboxRecords) : box);
      });

  @override
  Future<List<PlayRecord>> outboxPeek(int count) => _serial(() async => (await _readOutbox()).take(count).toList());

  @override
  Future<void> outboxRemove(Set<String> ids) => _serial(() async {
        final box = await _readOutbox();
        await _writeOutbox([for (final r in box) if (!ids.contains(r.id)) r]);
      });
}
