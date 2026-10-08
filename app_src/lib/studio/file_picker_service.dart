import 'package:file_picker/file_picker.dart';

import 'studio_models.dart';

/// Lets the artist choose a song or a cover picture. The real version uses the
/// system picker; tests use a fake.
abstract class FilePickerService {
  Future<PickedFile?> pickAudio();
  Future<PickedFile?> pickImage();
}

class NoFilePickerService implements FilePickerService {
  const NoFilePickerService();

  @override
  Future<PickedFile?> pickAudio() async => null;

  @override
  Future<PickedFile?> pickImage() async => null;
}

class DeviceFilePickerService implements FilePickerService {
  const DeviceFilePickerService();

  Future<PickedFile?> _pick(List<String> extensions) async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: extensions);
    if (files.isEmpty) return null;
    final f = files.first;
    final length = await f.length();
    if (length == null) return null;
    return PickedFile(name: f.name, length: length, open: f.readAsByteStream);
  }

  @override
  Future<PickedFile?> pickAudio() => _pick(const ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'aif', 'aiff']);

  @override
  Future<PickedFile?> pickImage() => _pick(const ['jpg', 'jpeg', 'png', 'webp']);
}
