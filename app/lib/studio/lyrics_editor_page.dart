import 'package:flutter/material.dart';

import '../auth/screens/auth_widgets.dart' show showError, showNotice;
import '../lyrics/lyrics_models.dart';
import 'file_picker_service.dart';
import 'studio_api.dart';
import 'studio_models.dart';

/// Where an artist writes or pastes the lyrics of a song, plain or synced (LRC), or imports a .lrc file.
class LyricsEditorPage extends StatefulWidget {
  const LyricsEditorPage({super.key, required this.studio, required this.picker, required this.track});

  final StudioApi studio;
  final FilePickerService picker;
  final StudioTrack track;

  @override
  State<LyricsEditorPage> createState() => _LyricsEditorPageState();
}

class _LyricsEditorPageState extends State<LyricsEditorPage> {
  final _text = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _hadLyrics = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final draft = await widget.studio.lyrics(widget.track.id);
      if (!mounted) return;
      setState(() {
        _text.text = draft?.text ?? '';
        _hadLyrics = draft != null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _import() async {
    try {
      final file = await widget.picker.pickLyrics();
      if (file == null) return;
      final text = await readPickedText(file);
      if (mounted) setState(() => _text.text = text);
    } on FormatException catch (e) {
      if (mounted) showNotice(context, e.message);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final saved = await widget.studio.setLyrics(widget.track.id, _text.text);
      if (!mounted) return;
      showNotice(context, saved.synced ? 'Lyrics saved. They will follow the music.' : 'Lyrics saved.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove the lyrics?'),
        content: Text('Listeners will no longer see lyrics for "${widget.track.title}".'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.studio.removeLyrics(widget.track.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final parsed = parseLyrics(_text.text);
    final count = parsed.lines.where((l) => l.text.isNotEmpty).length;
    final lines = count == 1 ? '1 line' : '$count lines';
    final status = parsed.isEmpty
        ? 'Add the words of your song. To make them follow the music, put a time before each line, like [01:23.45].'
        : parsed.synced
            ? 'Synced lyrics, $lines. Listeners see each line light up as it is sung.'
            : 'Plain lyrics, $lines. Put a time like [00:12.50] before each line to make them follow the music.';
    return Scaffold(
      appBar: AppBar(title: Text('Lyrics: ${widget.track.title}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Could not load the lyrics.'), TextButton(onPressed: _load, child: const Text('Try again'))]))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _text,
                      minLines: 12,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(labelText: 'Lyrics', alignLabelWithHint: true, border: OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(status, style: text.bodySmall),
                    const SizedBox(height: 4),
                    Text('Only add lyrics you wrote, or have the right to share.', style: text.bodySmall),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(onPressed: _busy ? null : _import, icon: const Icon(Icons.file_open_outlined), label: const Text('Import a .lrc or .txt file')),
                        FilledButton(onPressed: _busy || parsed.isEmpty ? null : _save, child: const Text('Save lyrics')),
                        if (_hadLyrics) TextButton(onPressed: _busy ? null : _remove, child: const Text('Remove lyrics')),
                      ],
                    ),
                  ],
                ),
    );
  }
}
