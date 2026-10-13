import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'library_platform.dart';
import 'library_scanner.dart' show supportedAudioExtensions;

class DeviceLibraryPlatform implements LibraryPlatform {
  const DeviceLibraryPlatform();

  bool get _isPhone => Platform.isAndroid || Platform.isIOS;

  @override
  Future<List<String>> defaultRoots() async {
    if (Platform.isIOS) return const [];
    if (Platform.isAndroid) return const ['/storage/emulated/0/Music', '/storage/emulated/0/Download'];
    final home = Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (home == null || home.isEmpty) return const [];
    return ['$home${Platform.pathSeparator}Music'];
  }

  @override
  Future<bool> requestAccess() async {
    if (!Platform.isAndroid) return true;
    // Android 13 and newer use the audio permission, older versions use storage.
    // Asking for both is harmless: the one that does not apply is answered silently.
    final results = await [Permission.audio, Permission.storage].request();
    return results.values.any((status) => status.isGranted);
  }

  @override
  Future<String?> pickFolder() => FilePicker.getDirectoryPath();

  @override
  Future<List<String>> pickSongs() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [for (final e in supportedAudioExtensions) e.substring(1)],
    );
    if (files.isEmpty) return const [];
    if (!_isPhone) return [for (final f in files) if (f.path != null) f.path!];

    // Phones: the picker may lend a temporary file or only a content address, so the
    // bytes are copied into the app's own folder, which is permanent.
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}imports');
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final out = <String>[];
    for (var i = 0; i < files.length; i++) {
      final target = File('${dir.path}${Platform.pathSeparator}${stamp}_${i}_${files[i].name}');
      final sink = target.openWrite();
      try {
        await sink.addStream(files[i].readAsByteStream());
      } finally {
        await sink.close();
      }
      out.add(target.path);
    }
    return out;
  }
}
