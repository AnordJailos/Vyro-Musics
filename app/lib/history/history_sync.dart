import 'dart:async';

import '../auth/api_client.dart';
import '../auth/api_errors.dart';
import 'history_store.dart';
import 'play_record.dart';

/// Sends plays to the server.
abstract class HistoryApi {
  Future<void> uploadPlays(List<PlayRecord> plays);
}

class HttpHistoryApi implements HistoryApi {
  HttpHistoryApi(this._client);

  final ApiClient _client;

  @override
  Future<void> uploadPlays(List<PlayRecord> plays) async {
    await _client.send('POST', '/v1/events/listens', body: {'events': [for (final p in plays) p.toUpload()]});
  }
}

class _Sent {
  const _Sent({required this.stop, required this.done});

  /// True when sending cannot continue now (no connection, signed out, server trouble).
  final bool stop;

  /// Plays that are finished with: sent, or refused for good.
  final Set<String> done;
}

/// Empties the outbox of Vyro plays whenever someone is signed in and the server can be reached.
/// Safe to run again and again: every play has its own id, which the server uses to ignore repeats.
class HistorySync {
  HistorySync({required this.store, required this.api, required this.canUpload, this.delay = const Duration(seconds: 5), this.batchSize = 100});

  final HistoryStore store;
  final HistoryApi api;
  final bool Function() canUpload;
  final Duration delay;
  final int batchSize;
  Timer? _timer;
  bool _running = false;

  /// Sends soon (after a short pause, so several plays go together), or right away.
  void schedule({bool immediately = false}) {
    _timer?.cancel();
    if (immediately) {
      unawaited(flush());
      return;
    }
    _timer = Timer(delay, () => unawaited(flush()));
  }

  Future<void> flush() async {
    if (_running || !canUpload()) return;
    _running = true;
    try {
      while (canUpload()) {
        final batch = await store.outboxPeek(batchSize);
        if (batch.isEmpty) break;
        final result = await _send(batch);
        if (result.done.isNotEmpty) await store.outboxRemove(result.done);
        if (result.stop) break;
      }
    } finally {
      _running = false;
    }
  }

  /// A batch the server refuses as invalid is split in halves, so one bad play cannot block all the others.
  Future<_Sent> _send(List<PlayRecord> batch) async {
    final ids = {for (final r in batch) r.id};
    try {
      await api.uploadPlays(batch);
      return _Sent(stop: false, done: ids);
    } on ApiException catch (e) {
      if (e.status != 400 && e.status != 413) return const _Sent(stop: true, done: {});
      if (batch.length == 1) return _Sent(stop: false, done: ids); // refused for good: drop it
      final middle = batch.length ~/ 2;
      final first = await _send(batch.sublist(0, middle));
      if (first.stop) return first;
      final second = await _send(batch.sublist(middle));
      return _Sent(stop: second.stop, done: {...first.done, ...second.done});
    }
  }

  void dispose() => _timer?.cancel();
}
