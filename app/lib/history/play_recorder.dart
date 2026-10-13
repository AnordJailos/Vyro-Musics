import 'dart:async';

import '../audio/playback_controller.dart';
import 'history_store.dart';
import 'history_sync.dart';
import 'play_record.dart';

/// Turns finished plays into history: kept on the device, and, for Vyro songs, queued to be sent.
class PlayRecorder {
  PlayRecorder({required this.store, this.sync, this.isPrivate, this.platform = 'android', String Function()? newId}) : _newId = newId ?? newUuid;

  final HistoryStore store;
  final HistorySync? sync;

  /// True during a private session: the play is not kept in the person's history. (It is still sent, and the
  /// server counts it for the artist without linking it to the listener.)
  final bool Function()? isPrivate;
  final String platform;
  final String Function() _newId;
  Future<void> _chain = Future<void>.value();

  Future<void> record(PlayEnded ended) {
    final run = _chain.then((_) async {
      final r = PlayRecord.fromEnded(ended, id: _newId(), platform: platform);
      if (!(isPrivate?.call() ?? false)) await store.append(r);
      if (r.source == 'vyro') {
        await store.outboxAdd(r);
        sync?.schedule();
      }
    });
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }
}
