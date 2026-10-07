import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'deck.dart';
import 'fade.dart';
import 'track.dart';

/// NORMAL: tracks change one after another, with no overlap.
/// MIXING: every change (natural end, next, previous) blends the two tracks.
enum PlaybackMode { normal, mixing }

enum RepeatMode { off, all, one }

class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required Deck deckA,
    required Deck deckB,
    this.tickInterval = const Duration(milliseconds: 20),
  }) : _decks = [deckA, deckB] {
    for (var i = 0; i < 2; i++) {
      _subs.add(_decks[i].positionStream.listen((p) => _onPosition(i, p)));
      _subs.add(_decks[i].completedStream.listen((_) => _onCompleted(i)));
    }
  }

  static const double minSeconds = 1.0;
  static const double maxSeconds = 12.0;
  static const Duration _minMix = Duration(milliseconds: 300);
  static const Duration _restartThreshold = Duration(seconds: 3);

  final Duration tickInterval;
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

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0, bool autoPlay = true}) {
    return _enqueue(() async {
      _commitFade();
      _queue = List<Track>.unmodifiable(tracks);
      await _decks[1 - _active].stop();
      if (tracks.isEmpty) {
        _index = -1;
        _playing = false;
        await _decks[_active].stop();
        position.value = Duration.zero;
        notifyListeners();
        return;
      }
      _playing = autoPlay;
      await _cutTo(math.max(0, math.min(startIndex, tracks.length - 1)));
    });
  }

  Future<void> play() => _enqueue(() async {
        if (current == null) return;
        _playing = true;
        await _decks[_active].play();
        notifyListeners();
      });

  Future<void> pause() => _enqueue(() async {
        _commitFade();
        _playing = false;
        await _decks[_active].pause();
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
        if (_decks[_active].position > _restartThreshold || target == null) {
          _autoMixScheduled = false;
          await _decks[_active].seek(Duration.zero);
          position.value = Duration.zero;
          return;
        }
        await _transitionTo(target, manual: true);
      });

  Future<void> seek(Duration to) => _enqueue(() async {
        _commitFade();
        _autoMixScheduled = false;
        await _decks[_active].seek(to);
        position.value = to;
      });

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
        _error = '$e';
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
    _index = target;
    _autoMixScheduled = false;
    position.value = Duration.zero;
    notifyListeners();
    await deck.stop();
    await deck.setVolume(1);
    await deck.load(_queue[target]);
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
      _playing = false;
      await _decks[_active].pause();
      await _decks[_active].seek(Duration.zero);
      position.value = Duration.zero;
      notifyListeners();
      return;
    }
    if (target == _index) {
      _autoMixScheduled = false;
      await _decks[_active].seek(Duration.zero);
      await _decks[_active].play();
      return;
    }
    await _transitionTo(target, manual: false);
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
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
