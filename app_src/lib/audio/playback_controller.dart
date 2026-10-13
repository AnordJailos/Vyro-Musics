import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'deck.dart';
import 'fade.dart';
import 'playback_snapshot.dart';
import 'track.dart';

/// NORMAL: tracks change one after another, with no overlap.
/// MIXING: every change (natural end, next, previous) blends the two tracks.
enum PlaybackMode { normal, mixing }

enum RepeatMode { off, all, one }

/// One song's play, reported when it stops being the current song.
class PlayEnded {
  const PlayEnded({required this.track, required this.startedAt, required this.listenedMs, required this.mode, required this.origin, this.mixedInto});

  final Track track;
  final DateTime startedAt;

  /// Time actually spent listening. A jump forward (a seek) adds nothing, and pausing does not end a play.
  final int listenedMs;
  final PlaybackMode mode;

  /// Where the person started it: search, chart, library, direct and so on.
  final String origin;

  /// The song this one was blended into, when it ended with a blend.
  final Track? mixedInto;
}

class _Session {
  _Session(this.track, this.startedAt, this.mode, this.origin);

  final Track track;
  final DateTime startedAt;
  final PlaybackMode mode;
  final String origin;
  Duration played = Duration.zero;
  Duration? lastPosition;
}

class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required Deck deckA,
    required Deck deckB,
    this.tickInterval = const Duration(milliseconds: 20),
    this.describeError,
    this.onPlayEnded,
    DateTime Function()? clock,
    math.Random? random,
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)],
    this.isRetryable,
  })  : _decks = [deckA, deckB],
        _clock = clock ?? DateTime.now,
        _random = random ?? math.Random() {
    for (var i = 0; i < 2; i++) {
      _subs.add(_decks[i].positionStream.listen((p) => _onPosition(i, p)));
      _subs.add(_decks[i].completedStream.listen((_) => _onCompleted(i)));
      _subs.add(_decks[i].bufferingStream.listen((b) => _onBuffering(i, b)));
      _subs.add(_decks[i].errorStream.listen((e) => _onDeckError(i, e)));
    }
  }

  static const double minSeconds = 1.0;
  static const double maxSeconds = 12.0;
  static const Duration _minMix = Duration(milliseconds: 300);
  static const Duration _restartThreshold = Duration(seconds: 3);

  final Duration tickInterval;

  /// Turns a failure (for example no connection) into a message for the person.
  final String Function(Object error)? describeError;

  /// Called each time a song's play ends, so it can go into the listening history.
  final void Function(PlayEnded play)? onPlayEnded;
  final DateTime Function() _clock;
  String _origin = 'direct';
  final List<_Session?> _sessions = [null, null];
  final math.Random _random;

  /// How long to wait before each new attempt when the connection is lost in the middle of a song.
  final List<Duration> retryDelays;

  /// Whether an error is worth trying again (a lost connection is, a "not allowed" is not). Defaults to yes.
  final bool Function(Object error)? isRetryable;

  // Every queue entry has its own number, so the same song queued twice can be told apart, and the original
  // order can be brought back when shuffle is switched off.
  List<int> _ids = const [];
  List<int> _originalIds = const [];
  int _nextUid = 1;
  bool _shuffle = false;
  final List<Track> _history = [];
  final List<bool> _buffering = [false, false];
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _retrying = false;
  Duration _resumeAt = Duration.zero;

  // After restoring a saved queue, or after giving up on a lost connection, nothing is loaded in the deck yet.
  // The next press of play loads the song and jumps to where it was.
  bool _needsLoad = false;
  Duration _pendingSeek = Duration.zero;
  final List<Deck> _decks;
  final List<StreamSubscription<Object?>> _subs = [];

  /// Position of the track on screen. Separate from the main notifier so the
  /// seek bar can update many times a second without rebuilding everything.
  final ValueNotifier<Duration> position = ValueNotifier<Duration>(Duration.zero);

  List<Track> _queue = const [];
  int _index = -1;
  int _active = 0;
  bool _playing = false;
  bool _autoMixScheduled = false;
  PlaybackMode _mode = PlaybackMode.normal;
  RepeatMode _repeat = RepeatMode.off;
  double _autoSeconds = 6;
  double _manualSeconds = 3;
  String? _error;
  _Fade? _fade;
  Timer? _fadeTimer;
  Future<void> _chain = Future<void>.value();

  // ---- state for the UI ---------------------------------------------------

  List<Track> get queue => _queue;
  int get index => _index;
  Track? get current => (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  Track? get upcoming {
    final n = _nextIndex(natural: true);
    return n == null ? null : _queue[n];
  }

  /// The track being blended in right now, or null when no blend is running.
  Track? get mixingInto {
    final f = _fade;
    return f == null ? null : _queue[f.target];
  }

  bool get isPlaying => _playing;
  bool get isTransitioning => _fade != null;
  PlaybackMode get mode => _mode;
  RepeatMode get repeat => _repeat;
  double get autoSeconds => _autoSeconds;
  double get manualSeconds => _manualSeconds;
  String? get error => _error;
  bool get shuffle => _shuffle;

  /// One number per queue entry, in queue order: stable keys for lists on screen.
  List<int> get queueIds => _ids;

  /// Songs already played, most recent first.
  List<Track> get history => List<Track>.unmodifiable(_history.reversed);

  /// Waiting for audio to arrive (not shown while paused).
  bool get isBuffering => _playing && _buffering[_displayDeck];

  /// The connection was lost and the player is trying again.
  bool get isRetrying => _retrying;

  Duration get _livePosition => _needsLoad ? _pendingSeek : _decks[_active].position;

  int get _displayDeck {
    final f = _fade;
    return (f != null && f.switched) ? f.incoming : _active;
  }

  Duration? get duration => _decks[_displayDeck].duration ?? current?.duration;

  // ---- settings -----------------------------------------------------------

  void setMode(PlaybackMode value) {
    if (value == _mode) return;
    _mode = value;
    _autoMixScheduled = false;
    notifyListeners();
  }

  void setRepeat(RepeatMode value) {
    if (value == _repeat) return;
    _repeat = value;
    notifyListeners();
  }

  /// Blend length when a song ends by itself (mixing mode).
  void setAutoSeconds(double seconds) {
    _autoSeconds = _clampSeconds(seconds);
    notifyListeners();
  }

  /// Blend length when the user presses next or previous (mixing mode).
  void setManualSeconds(double seconds) {
    _manualSeconds = _clampSeconds(seconds);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  double _clampSeconds(double s) => math.max(minSeconds, math.min(maxSeconds, s));

  // ---- commands -----------------------------------------------------------

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0, bool autoPlay = true, String origin = 'direct'}) {
    return _enqueue(() => _setQueueNow(tracks, startIndex, autoPlay, origin));
  }

  Future<void> _setQueueNow(List<Track> tracks, int startIndex, bool autoPlay, String origin) async {
    _commitFade();
    _cancelRetry();
    _origin = origin;
    final leaving = current;
    if (leaving != null) _remember(leaving);
    _setQueueState(tracks);
    _originalIds = List<int>.of(_ids);
    await _decks[1 - _active].stop();
    if (tracks.isEmpty) {
      _endSession(0);
      _endSession(1);
      _index = -1;
      _playing = false;
      _needsLoad = false;
      _originalIds = const [];
      await _decks[_active].stop();
      position.value = Duration.zero;
      notifyListeners();
      return;
    }
    _playing = autoPlay;
    var start = math.max(0, math.min(startIndex, tracks.length - 1));
    if (_shuffle) start = _shuffleKeeping(start);
    await _cutTo(start);
  }

  Future<void> play() => _enqueue(() async {
        if (current == null) return;
        _playing = true;
        if (_needsLoad) {
          await _loadForResume();
        } else {
          await _decks[_active].play();
        }
        notifyListeners();
      });

  Future<void> pause() => _enqueue(() async {
        _commitFade();
        _cancelRetry();
        _playing = false;
        if (!_needsLoad) await _decks[_active].pause();
        notifyListeners();
      });

  Future<void> togglePlay() => _playing ? pause() : play();

  /// Next track. In mixing mode the two tracks are blended; in normal mode it
  /// is a plain change.
  Future<void> next() => _enqueue(() async {
        _commitFade(); // settle a running blend first, so "next" counts from the song on screen
        final target = _nextIndex(natural: false);
        if (target == null) return;
        await _transitionTo(target, manual: true);
      });

  /// Previous track. After the first 3 seconds it restarts the current track
  /// instead (the usual player behavior), in both modes.
  Future<void> previous() => _enqueue(() async {
        if (current == null) return;
        _commitFade();
        final target = _previousIndex();
        if (_livePosition > _restartThreshold || target == null) {
          _autoMixScheduled = false;
          await _seekNow(Duration.zero);
          return;
        }
        await _transitionTo(target, manual: true);
      });

  Future<void> seek(Duration to) => _enqueue(() async {
        _commitFade();
        _autoMixScheduled = false;
        await _seekNow(to);
      });

  Future<void> _seekNow(Duration to) async {
    if (_needsLoad) {
      _pendingSeek = to; // nothing is loaded yet; the jump happens when playback starts
    } else {
      await _decks[_active].seek(to);
    }
    position.value = to;
  }

  // ---- shuffle and the queue ----------------------------------------------

  /// Plays the queue in a random order, starting with the song that is playing now. Switching it off puts the
  /// queue back in the order it had.
  Future<void> setShuffle(bool value) => _enqueue(() async {
        _commitFade();
        if (value == _shuffle) return;
        _shuffle = value;
        if (_index >= 0 && _queue.isNotEmpty) {
          if (value) {
            _originalIds = List<int>.of(_ids);
            _index = _shuffleKeeping(_index);
          } else {
            _restoreOriginalOrder();
          }
        } else {
          _originalIds = value ? List<int>.of(_ids) : const [];
        }
        _autoMixScheduled = false; // the song that comes next may have changed
        notifyListeners();
      });

  /// Puts the song at [keep] first and everything else in random order. Returns the new index of that song (0).
  int _shuffleKeeping(int keep) {
    final rest = [for (var i = 0; i < _queue.length; i++) if (i != keep) i];
    for (var i = rest.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final swap = rest[i];
      rest[i] = rest[j];
      rest[j] = swap;
    }
    final order = [keep, ...rest];
    _queue = List<Track>.unmodifiable([for (final i in order) _queue[i]]);
    _ids = [for (final i in order) _ids[i]];
    return 0;
  }

  void _restoreOriginalOrder() {
    final uid = _ids[_index];
    final rank = {for (var i = 0; i < _originalIds.length; i++) _originalIds[i]: i};
    final order = List<int>.generate(_queue.length, (i) => i)..sort((a, b) => (rank[_ids[a]] ?? 1 << 30).compareTo(rank[_ids[b]] ?? 1 << 30));
    _queue = List<Track>.unmodifiable([for (final i in order) _queue[i]]);
    _ids = [for (final i in order) _ids[i]];
    _index = _ids.indexOf(uid);
    _originalIds = const [];
  }

  void _setQueueState(List<Track> tracks) {
    _queue = List<Track>.unmodifiable(tracks);
    _ids = [for (var i = 0; i < tracks.length; i++) _nextUid++];
  }

  void _insertAt(int at, Track track, {required bool afterCurrent}) {
    final uid = _nextUid++;
    _queue = List<Track>.unmodifiable([..._queue.sublist(0, at), track, ..._queue.sublist(at)]);
    _ids = [..._ids.sublist(0, at), uid, ..._ids.sublist(at)];
    if (_shuffle) {
      // In the original order the new song goes right after the one playing now (or at the end).
      final anchor = afterCurrent && _index >= 0 ? _originalIds.indexOf(_ids[_index]) + 1 : _originalIds.length;
      _originalIds = [..._originalIds.sublist(0, anchor), uid, ..._originalIds.sublist(anchor)];
    }
  }

  /// Plays [track] right after the song that is playing now. With nothing playing, it starts playing.
  Future<void> playNext(Track track) => _enqueue(() async {
        _commitFade();
        if (current == null) return _setQueueNow([track], 0, true, _origin);
        _insertAt(_index + 1, track, afterCurrent: true);
        _autoMixScheduled = false;
        notifyListeners();
      });

  /// Adds [track] to the end of the queue. With nothing playing, it starts playing.
  Future<void> addToQueue(Track track) => _enqueue(() async {
        _commitFade();
        if (current == null) return _setQueueNow([track], 0, true, _origin);
        _insertAt(_queue.length, track, afterCurrent: false);
        notifyListeners();
      });

  /// Takes a song out of the queue. The song that is playing now cannot be removed.
  Future<void> removeFromQueue(int index) => _enqueue(() async {
        _commitFade();
        if (index < 0 || index >= _queue.length || index == _index) return;
        final uid = _ids[index];
        _queue = List<Track>.unmodifiable([..._queue.sublist(0, index), ..._queue.sublist(index + 1)]);
        _ids = [..._ids.sublist(0, index), ..._ids.sublist(index + 1)];
        if (index < _index) _index--;
        if (_shuffle) _originalIds = [for (final u in _originalIds) if (u != uid) u];
        _autoMixScheduled = false;
        notifyListeners();
      });

  /// Moves a song that is still to come to another place among the songs still to come ([to] is its new index).
  Future<void> moveInQueue(int from, int to) => _enqueue(() async {
        _commitFade();
        if (from <= _index || to <= _index || from >= _queue.length || to >= _queue.length || from == to) return;
        final list = [..._queue];
        final ids = [..._ids];
        list.insert(to, list.removeAt(from));
        ids.insert(to, ids.removeAt(from));
        _queue = List<Track>.unmodifiable(list);
        _ids = ids;
        _autoMixScheduled = false;
        notifyListeners();
      });

  /// Empties the queue after the song that is playing now.
  Future<void> clearUpcoming() => _enqueue(() async {
        _commitFade();
        if (_index < 0 || _index >= _queue.length - 1) return;
        final gone = _ids.sublist(_index + 1).toSet();
        _queue = List<Track>.unmodifiable(_queue.sublist(0, _index + 1));
        _ids = _ids.sublist(0, _index + 1);
        if (_shuffle) _originalIds = [for (final u in _originalIds) if (!gone.contains(u)) u];
        _autoMixScheduled = false;
        notifyListeners();
      });

  /// Plays the song at [index] of the queue now (blended in Mixing mode).
  Future<void> jumpTo(int index) => _enqueue(() async {
        _commitFade();
        if (index < 0 || index >= _queue.length || index == _index) return;
        await _transitionTo(index, manual: true);
      });

  /// Plays [track] now by putting it next in the queue and moving on to it (used for the history).
  Future<void> playNow(Track track) => _enqueue(() async {
        _commitFade();
        if (current == null) return _setQueueNow([track], 0, true, _origin);
        _insertAt(_index + 1, track, afterCurrent: true);
        await _transitionTo(_index + 1, manual: true);
      });

  void _remember(Track track) {
    _history.add(track);
    if (_history.length > 100) _history.removeAt(0);
  }

  // ---- navigation helpers -------------------------------------------------

  int? _nextIndex({required bool natural}) {
    if (_queue.isEmpty || _index < 0) return null;
    if (natural && _repeat == RepeatMode.one) return _index;
    final n = _index + 1;
    if (n < _queue.length) return n;
    return _repeat == RepeatMode.all ? 0 : null;
  }

  int? _previousIndex() {
    if (_queue.isEmpty || _index < 0) return null;
    final p = _index - 1;
    if (p >= 0) return p;
    return _repeat == RepeatMode.all ? _queue.length - 1 : null;
  }

  Future<void> _enqueue(Future<void> Function() job) {
    final run = _chain.then((_) async {
      try {
        await job();
      } catch (e) {
        _error = describeError?.call(e) ?? 'Could not play that song.';
        notifyListeners();
      }
    });
    _chain = run;
    return run;
  }

  // ---- transitions --------------------------------------------------------

  Future<void> _transitionTo(int target, {required bool manual}) async {
    _commitFade();
    final from = current;
    if (from != null && target != _index) _remember(from);
    final to = _queue[target];
    final blend = _mode == PlaybackMode.mixing &&
        _playing &&
        from != null &&
        from.mixable &&
        to.mixable;
    if (blend) {
      await _mixInto(target, manual ? _manualSeconds : _autoSeconds);
    } else {
      await _cutTo(target);
    }
  }

  /// Plain change on the active deck: no overlap.
  Future<void> _cutTo(int target) async {
    final deck = _decks[_active];
    _cancelRetry();
    _needsLoad = false;
    _endSession(0);
    _endSession(1);
    _startSession(_active, _queue[target]);
    _index = target;
    _autoMixScheduled = false;
    position.value = Duration.zero;
    notifyListeners();
    await deck.stop();
    await deck.setVolume(1);
    try {
      await deck.load(_queue[target]);
    } catch (e) {
      if (_queue[target].source != TrackSource.local && _canRetry(e)) {
        // Probably the connection: keep the song selected and try again shortly.
        _needsLoad = true;
        _pendingSeek = Duration.zero;
        _resumeAt = Duration.zero;
        _scheduleRetry();
        return;
      }
      _playing = false;
      notifyListeners();
      rethrow;
    }
    if (_playing) await deck.play();
  }

  /// Blend: start the next track on the idle deck at volume 0, then ramp the
  /// two decks in opposite directions (equal-power curves).
  Future<void> _mixInto(int target, double seconds) async {
    final outgoingIdx = _active;
    final incomingIdx = 1 - outgoingIdx;
    final outgoing = _decks[outgoingIdx];
    final incoming = _decks[incomingIdx];
    final nextTrack = _queue[target];

    var length = Duration(milliseconds: (seconds * 1000).round());
    final total = outgoing.duration ?? current?.duration;
    if (total != null) {
      final left = total - outgoing.position;
      if (left < length) length = left; // never blend longer than what is left
    }
    final nextTotal = nextTrack.duration;
    if (nextTotal != null && nextTotal ~/ 2 < length) length = nextTotal ~/ 2;
    if (length < _minMix) {
      await _cutTo(target);
      return;
    }

    await incoming.stop();
    await incoming.setVolume(0);
    await incoming.load(nextTrack);
    await incoming.play();
    _startSession(incomingIdx, nextTrack);

    _fade = _Fade(outgoing: outgoingIdx, incoming: incomingIdx, total: length, target: target);
    _autoMixScheduled = false;
    _fadeTimer = Timer.periodic(tickInterval, (_) => _tick());
    notifyListeners();
  }

  // Elapsed time is counted in whole ticks, which keeps the fade deterministic.
  void _tick() {
    final f = _fade;
    if (f == null) return;
    f.elapsed += tickInterval;
    final raw = f.elapsed.inMicroseconds / f.total.inMicroseconds;
    final t = raw > 1.0 ? 1.0 : raw;
    unawaited(_decks[f.outgoing].setVolume(equalPowerOut(t)));
    unawaited(_decks[f.incoming].setVolume(equalPowerIn(t)));
    if (!f.switched && t >= 0.5) {
      f.switched = true;
      _index = f.target; // the screen follows the new track at the midpoint
      position.value = _decks[f.incoming].position;
      notifyListeners();
    }
    if (t >= 1.0) _commitFade();
  }

  /// Finishes a running blend immediately: the outgoing deck stops, the
  /// incoming deck takes over at full volume.
  void _commitFade() {
    final f = _fade;
    if (f == null) return;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fade = null;
    _endSession(f.outgoing, mixedInto: _queue[f.target]);
    unawaited(_decks[f.outgoing].stop());
    unawaited(_decks[f.incoming].setVolume(1));
    _active = f.incoming;
    _index = f.target;
    _autoMixScheduled = false;
    position.value = _decks[_active].position;
    notifyListeners();
  }

  // ---- natural end of a track --------------------------------------------

  void _onPosition(int deck, Duration p) {
    _accumulate(deck, p);
    if (deck != _displayDeck) return;
    position.value = p;
    if (deck == _active) _maybeScheduleAutoMix(p);
  }

  void _maybeScheduleAutoMix(Duration p) {
    if (_mode != PlaybackMode.mixing || !_playing || _fade != null || _autoMixScheduled) return;
    final cur = current;
    final total = _decks[_active].duration ?? cur?.duration;
    if (cur == null || total == null || !cur.mixable) return;
    final target = _nextIndex(natural: true);
    if (target == null || target == _index || !_queue[target].mixable) return;
    final lead = Duration(milliseconds: (_autoSeconds * 1000).round());
    if (total - p <= lead) {
      _autoMixScheduled = true;
      final from = _index;
      unawaited(_enqueue(() => _advanceAuto(from)));
    }
  }

  void _onCompleted(int deck) {
    if (deck != _active || _fade != null) return;
    final from = _index;
    unawaited(_enqueue(() => _advanceAuto(from)));
  }

  /// A track reached its end (or entered its mix zone) on its own.
  Future<void> _advanceAuto(int fromIndex) async {
    if (_index != fromIndex || _fade != null) return;
    final target = _nextIndex(natural: true);
    if (target == null) {
      _endSession(_active);
      _playing = false;
      await _decks[_active].pause();
      await _decks[_active].seek(Duration.zero);
      position.value = Duration.zero;
      notifyListeners();
      return;
    }
    if (target == _index) {
      _autoMixScheduled = false;
      _endSession(_active); // playing it again counts as a new play
      _startSession(_active, current!);
      await _decks[_active].seek(Duration.zero);
      await _decks[_active].play();
      return;
    }
    await _transitionTo(target, manual: false);
  }

  // ---- connection trouble, buffering and resuming -------------------------

  bool _canRetry(Object error) => isRetryable?.call(error) ?? true;

  void _onBuffering(int deck, bool value) {
    if (_buffering[deck] == value) return;
    _buffering[deck] = value;
    if (deck == _displayDeck) notifyListeners();
  }

  void _onDeckError(int deck, Object error) {
    if (deck != _active || _fade != null || current == null || _needsLoad) return;
    if (current!.source == TrackSource.local || !_canRetry(error)) {
      _failPlayback(describeError?.call(error) ?? 'Could not play that song.');
      return;
    }
    if (_retryTimer != null) return; // already waiting to try again
    final at = _decks[deck].position;
    _resumeAt = at > Duration.zero ? at : position.value;
    _scheduleRetry();
  }

  void _failPlayback(String message) {
    _error = message;
    _playing = false;
    notifyListeners();
    unawaited(_enqueue(() => _decks[_active].pause()));
  }

  // Tries again after 1, 2 and 4 seconds, then gives up and leaves the song ready: the next press of play
  // loads it again and jumps to where it stopped. (The address of a streamed song is asked for again each time,
  // because the old one may have expired.)
  void _scheduleRetry() {
    if (_retryAttempt >= retryDelays.length) {
      _retryAttempt = 0;
      _retrying = false;
      _needsLoad = true;
      _pendingSeek = _resumeAt;
      _playing = false;
      _error = 'Lost the connection. Press play to try again.';
      notifyListeners();
      unawaited(_enqueue(() async => _decks[_active].pause()));
      return;
    }
    _retrying = true;
    notifyListeners();
    final delay = retryDelays[_retryAttempt++];
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_enqueue(_attemptResume));
    });
  }

  Future<void> _attemptResume() async {
    if (!_retrying) return; // the listener did something else in the meantime
    final track = current;
    if (track == null) {
      _cancelRetry();
      return;
    }
    final deck = _decks[_active];
    try {
      await deck.stop();
      await deck.setVolume(1);
      await deck.load(track);
      if (_resumeAt > Duration.zero) await deck.seek(_resumeAt);
      _retryAttempt = 0;
      _retrying = false;
      _needsLoad = false;
      _error = null;
      position.value = _resumeAt;
      if (_playing) await deck.play();
      notifyListeners();
    } catch (e) {
      if (_canRetry(e)) {
        _scheduleRetry();
      } else {
        _retrying = false;
        _failPlayback(describeError?.call(e) ?? 'Could not play that song.');
      }
    }
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _retrying = false;
  }

  /// Loads the current song and jumps to where it was left (after a restart, or after a lost connection).
  Future<void> _loadForResume() async {
    final deck = _decks[_active];
    final track = current!;
    final at = _pendingSeek;
    _cancelRetry();
    _error = null;
    if (_sessions[_active] == null) _startSession(_active, track);
    try {
      await deck.stop();
      await deck.setVolume(1);
      await deck.load(track);
      if (at > Duration.zero) await deck.seek(at);
      _needsLoad = false;
      position.value = at;
      if (_playing) await deck.play();
    } catch (e) {
      if (track.source != TrackSource.local && _canRetry(e)) {
        _resumeAt = at;
        _scheduleRetry();
      } else {
        _playing = false;
        rethrow;
      }
    }
  }

  /// Everything needed to bring the player back as it is now.
  PlaybackSnapshot snapshot() => PlaybackSnapshot(
        queue: _queue,
        ids: _ids,
        originalIds: _originalIds,
        index: _index,
        position: _needsLoad ? _pendingSeek : position.value,
        shuffle: _shuffle,
        repeat: _repeat,
        mode: _mode,
        autoSeconds: _autoSeconds,
        manualSeconds: _manualSeconds,
        origin: _origin,
      );

  /// Brings back a saved queue, ready and paused at the saved position. Nothing is loaded until play is pressed,
  /// so starting the app does not need the network.
  Future<void> restore(PlaybackSnapshot saved) => _enqueue(() async {
        if (saved.queue.isEmpty || _queue.isNotEmpty) return; // never replaces something already playing
        _commitFade();
        _cancelRetry();
        _queue = List<Track>.unmodifiable(saved.queue);
        _ids = List<int>.of(saved.ids);
        _originalIds = List<int>.of(saved.originalIds);
        _nextUid = ([0, ..._ids].reduce(math.max)) + 1;
        _index = math.max(0, math.min(saved.index, _queue.length - 1));
        _shuffle = saved.shuffle;
        _repeat = saved.repeat;
        _mode = saved.mode;
        _autoSeconds = _clampSeconds(saved.autoSeconds);
        _manualSeconds = _clampSeconds(saved.manualSeconds);
        _origin = saved.origin;
        _playing = false;
        _needsLoad = true;
        _pendingSeek = saved.position;
        position.value = saved.position;
        notifyListeners();
      });

  // ---- listening history ---------------------------------------------------

  void _startSession(int deck, Track track) {
    _endSession(deck);
    _sessions[deck] = track.countsAsListening ? _Session(track, _clock().toUtc(), _mode, _origin) : null;
  }

  void _endSession(int deck, {Track? mixedInto}) {
    final s = _sessions[deck];
    _sessions[deck] = null;
    final report = onPlayEnded;
    if (s == null || report == null) return;
    var played = s.played;
    final length = s.track.duration;
    if (length != null && played > length) played = length;
    if (played < const Duration(seconds: 1)) return; // an accidental tap is not a play
    report(PlayEnded(track: s.track, startedAt: s.startedAt, listenedMs: played.inMilliseconds, mode: s.mode, origin: s.origin, mixedInto: mixedInto));
  }

  // Adds up time spent listening from the position readings. A big jump is a seek and counts for nothing.
  void _accumulate(int deck, Duration position) {
    final s = _sessions[deck];
    if (s == null || !_playing) return;
    final last = s.lastPosition;
    s.lastPosition = position;
    if (last == null) return;
    final step = position - last;
    if (step > Duration.zero && step < const Duration(seconds: 2)) s.played += step;
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _retryTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    for (final d in _decks) {
      unawaited(d.dispose());
    }
    position.dispose();
    super.dispose();
  }
}

class _Fade {
  _Fade({
    required this.outgoing,
    required this.incoming,
    required this.total,
    required this.target,
  });

  final int outgoing;
  final int incoming;
  final int target;
  final Duration total;
  Duration elapsed = Duration.zero;
  bool switched = false;
}
