import 'package:flutter/material.dart';

import '../audio/playback_controller.dart';
import '../audio/track.dart';
import '../auth/screens/auth_widgets.dart' show showError, showNotice;
import 'lyrics_models.dart';
import 'lyrics_provider.dart';

/// Lyrics for the current song. Synced lyrics highlight the line being sung and scroll along; tapping a line jumps to it.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, required this.controller, required this.provider});

  final PlaybackController controller;
  final LyricsProvider provider;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  Track? _track;
  Lyrics? _lyrics;
  bool _loading = false;
  bool _failed = false;
  bool _ready = false;
  int _index = -1;
  int _loadId = 0;
  List<GlobalKey> _keys = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTrack);
    widget.controller.position.addListener(_onPosition);
    _onTrack();
    _ready = true;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTrack);
    widget.controller.position.removeListener(_onPosition);
    super.dispose();
  }

  void _update(VoidCallback change) => _ready && mounted ? setState(change) : change();

  void _onTrack() {
    final track = widget.controller.current;
    if (track?.id == _track?.id) return;
    _track = track;
    _load();
  }

  Future<void> _load() async {
    final track = _track;
    final myId = ++_loadId;
    _update(() {
      _lyrics = null;
      _failed = false;
      _index = -1;
      _loading = track != null;
    });
    if (track == null) return;
    try {
      final found = await widget.provider.lyricsFor(track);
      if (myId != _loadId || !mounted) return;
      setState(() {
        _lyrics = found;
        _keys = [for (var i = 0; i < (found?.lines.length ?? 0); i++) GlobalKey()];
        _loading = false;
      });
      _onPosition();
    } catch (_) {
      if (myId == _loadId && mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _onPosition() {
    final lyrics = _lyrics;
    if (lyrics == null || !lyrics.synced) return;
    final i = currentLineIndex(lyrics, widget.controller.position.value);
    if (i == _index) return;
    setState(() => _index = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = (i >= 0 && i < _keys.length) ? _keys[i].currentContext : null;
      if (context != null && mounted) {
        Scrollable.ensureVisible(context, alignment: 0.4, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _report(String reason) async {
    final track = _track;
    if (track == null) return;
    try {
      await widget.provider.report(track, reason);
      if (mounted) showNotice(context, 'Thank you. The artist has been told.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _message(String text, {Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [Text(text, textAlign: TextAlign.center), if (action != null) ...[const SizedBox(height: 8), action]]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final track = _track;
    if (track == null) return _message('Nothing is playing.');
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) return _message('Could not load the lyrics.', action: TextButton(onPressed: _load, child: const Text('Try again')));
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return _message(
        track.source == TrackSource.local
            ? 'No lyrics found. Put a .lrc file with the same name as the song next to it, and the lyrics appear here.'
            : 'No lyrics for this song yet.',
      );
    }

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (track.source == TrackSource.vyro)
          Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<String>(
              tooltip: 'Lyrics options',
              icon: const Icon(Icons.flag_outlined),
              onSelected: _report,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'wrong_text', child: Text('Report wrong words')),
                PopupMenuItem(value: 'wrong_timing', child: Text('Report wrong timing')),
                PopupMenuItem(value: 'offensive', child: Text('Report offensive content')),
                PopupMenuItem(value: 'copyright', child: Text('Report copied lyrics')),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < lyrics.lines.length; i++)
                  if (!lyrics.synced && lyrics.lines[i].text.isEmpty)
                    const SizedBox(height: 16)
                  else
                    InkWell(
                      key: lyrics.synced ? _keys[i] : null,
                      onTap: lyrics.synced ? () => widget.controller.seek(Duration(milliseconds: lyrics.lines[i].timeMs ?? 0)) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: (i == _index ? text.titleLarge : text.titleMedium)!.copyWith(
                            fontWeight: i == _index ? FontWeight.w700 : FontWeight.w400,
                            color: lyrics.synced && i != _index ? scheme.onSurface.withValues(alpha: 0.5) : scheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                          child: Text(lyrics.lines[i].text.isEmpty ? '♪' : lyrics.lines[i].text, key: lyrics.synced && i == _index ? const ValueKey('current-lyric-line') : null, textAlign: TextAlign.center),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
