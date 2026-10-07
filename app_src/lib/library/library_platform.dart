/// Everything about the library that depends on the device: where music usually
/// lives, permissions, and the pickers. The real version is in
/// device_library_platform.dart; tests use fakes.
abstract class LibraryPlatform {
  /// Folders scanned when the user has not chosen any (empty on iOS).
  Future<List<String>> defaultRoots();

  /// Asks the system for permission to read music. True when scanning may go ahead.
  Future<bool> requestAccess();

  Future<String?> pickFolder();

  /// Lets the user choose songs and returns paths that stay valid. On phones the
  /// chosen files are copied into the app's own folder (the picker only lends
  /// them); on desktop they are used where they are. Empty when the user cancels.
  Future<List<String>> pickSongs();
}

class NoopLibraryPlatform implements LibraryPlatform {
  const NoopLibraryPlatform();

  @override
  Future<List<String>> defaultRoots() async => const [];

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<String?> pickFolder() async => null;

  @override
  Future<List<String>> pickSongs() async => const [];
}
