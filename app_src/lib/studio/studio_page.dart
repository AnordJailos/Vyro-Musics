import 'package:flutter/material.dart';

import '../auth/screens/auth_widgets.dart' show BusyState, showError, showNotice;
import '../auth/screens/taste_page.dart' show tasteGenres;
import '../catalog/catalog_widgets.dart' show mmss;
import 'file_picker_service.dart';
import 'studio_api.dart';
import 'studio_models.dart';

String _size(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).round()} KB';
}

/// Upload a song: choose the file, name it, add a cover, and publish it.
class StudioPage extends StatefulWidget {
  const StudioPage({super.key, required this.studio, required this.picker});

  final StudioApi studio;
  final FilePickerService picker;

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> with BusyState<StudioPage> {
  final _title = TextEditingController();
  PickedFile? _audio;
  PickedFile? _cover;
  String? _genre;
  bool _explicit = false;
  bool _allowMixing = true;
  double? _progress;
  String? _draftId; // kept after a failed upload so a retry does not create a second song
  StudioTrack? _done;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _chooseAudio() async {
    try {
      final file = await widget.picker.pickAudio();
      if (file == null || !mounted) return;
      setState(() {
        _audio = file;
        if (_title.text.trim().isEmpty) _title.text = file.suggestedTitle;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _chooseCover() async {
    try {
      final file = await widget.picker.pickImage();
      if (file != null && mounted) setState(() => _cover = file);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _upload() async {
    final audio = _audio;
    final title = _title.text.trim();
    if (audio == null) {
      showNotice(context, 'Choose an audio file first.');
      return;
    }
    if (title.isEmpty) {
      showNotice(context, 'Give the song a title.');
      return;
    }
    await run(() async {
      final id = _draftId ?? (await widget.studio.createTrack(title: title, genre: _genre ?? 'other', explicit: _explicit, allowMixing: _allowMixing)).id;
      _draftId = id;
      if (mounted) setState(() => _progress = 0);
      var track = await widget.studio.uploadAudio(id, audio, onProgress: (sent, total) {
        if (mounted) setState(() => _progress = total == 0 ? null : sent / total);
      });
      final cover = _cover;
      if (cover != null) track = await widget.studio.uploadCover(id, cover);
      if (mounted) setState(() => _done = track);
    });
    if (mounted) setState(() => _progress = null);
  }

  Future<void> _publish() => run(() async {
        final track = await widget.studio.publish(_done!.id);
        if (mounted) setState(() => _done = track);
      });

  void _another() => setState(() {
        _done = null;
        _audio = null;
        _cover = null;
        _draftId = null;
        _genre = null;
        _explicit = false;
        _allowMixing = true;
        _title.clear();
      });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = _done;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (done != null) ..._result(context, done) else ..._form(context, text),
          ],
        ),
      ),
    );
  }

  List<Widget> _result(BuildContext context, StudioTrack t) {
    final text = Theme.of(context).textTheme;
    final quality = t.lossless ? '${t.codec ?? 'lossless'} · lossless' : '${t.codec ?? 'audio'}${t.bitrateKbps != null ? ' · ${t.bitrateKbps} kbps' : ''}';
    return [
      const Icon(Icons.check_circle_outline_rounded, size: 48),
      const SizedBox(height: 12),
      Text('"${t.title}" is uploaded', style: text.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('${mmss(t.durationMs)} · $quality${t.loudnessLufs != null ? ' · ${t.loudnessLufs} LUFS' : ''}', style: text.bodyMedium, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(t.statusLabel, style: text.labelLarge, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      if (!t.isLive) FilledButton(onPressed: busy ? null : _publish, child: const Text('Publish now')),
      if (t.isLive) Text('Your song is live on Vyro.', style: text.bodyLarge, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _another, child: const Text('Upload another song')),
    ];
  }

  List<Widget> _form(BuildContext context, TextTheme text) {
    return [
      Text('Upload a song', style: text.titleLarge),
      const SizedBox(height: 4),
      Text('MP3, M4A, FLAC, WAV, OGG or AIFF. You can publish it right after.', style: text.bodySmall),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: busy ? null : _chooseAudio,
        icon: const Icon(Icons.audio_file_outlined),
        label: Text(_audio == null ? 'Choose audio file' : '${_audio!.name} (${_size(_audio!.length)})', overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(height: 12),
      TextField(controller: _title, enabled: !busy, decoration: const InputDecoration(labelText: 'Song title')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Genre'),
        items: [for (final g in tasteGenres) DropdownMenuItem<String>(value: g.toLowerCase(), child: Text(g))],
        onChanged: busy ? null : (v) => _genre = v,
      ),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Explicit content'), value: _explicit, onChanged: busy ? null : (v) => setState(() => _explicit = v)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Allow blending in Mixing mode'),
        subtitle: const Text('Listeners can blend this song into the next one.'),
        value: _allowMixing,
        onChanged: busy ? null : (v) => setState(() => _allowMixing = v),
      ),
      OutlinedButton.icon(
        onPressed: busy ? null : _chooseCover,
        icon: const Icon(Icons.image_outlined),
        label: Text(_cover == null ? 'Add a cover picture (optional)' : _cover!.name, overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(height: 20),
      if (_progress != null) ...[
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: 4),
        Text('Uploading… ${((_progress ?? 0) * 100).round()}%', style: text.bodySmall),
        const SizedBox(height: 12),
      ],
      FilledButton(onPressed: busy ? null : _upload, child: const Text('Upload')),
    ];
  }
}
