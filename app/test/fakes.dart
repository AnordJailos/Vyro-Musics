import 'dart:async';

import 'package:vyro_music/audio/deck.dart';
import 'package:vyro_music/audio/track.dart';

class FakeDeck implements Deck {
  double volume = 1;
  bool playing = false;
  Track? loaded;
  Duration pos = Duration.zero;
  Duration? dur;
  final List<Duration> seeks = [];
  final _positions = StreamController<Duration>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final List<Track> loads = [];
  int failLoads = 0;

  void emitPosition(Duration p) {
    pos = p;
    _positions.add(p);
  }

  void finish() => _completed.add(null);
  void emitBuffering(bool value) => _buffering.add(value);
  void emitError(Object error) => _errors.add(error);

  @override
  Future<void> load(Track track) async {
    if (failLoads > 0) {
      failLoads--;
      throw Exception('load failed');
    }
    loads.add(track);
    loaded = track;
    dur = track.duration;
    pos = Duration.zero;
  }

  @override
  Future<void> play() async {
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    pos = position;
  }

  @override
  Future<void> setVolume(double v) async {
    volume = v;
  }

  @override
  Duration get position => pos;

  @override
  Duration? get duration => dur;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<void> dispose() async {
    await _positions.close();
    await _completed.close();
  }
}
