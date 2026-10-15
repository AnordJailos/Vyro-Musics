import 'package:flutter/widgets.dart';

import '../studio/file_picker_service.dart';
import 'playlists_controller.dart';

/// Makes the playlists available to every screen, so a song row anywhere can offer "Add to playlist".
class PlaylistsScope extends InheritedNotifier<PlaylistsController> {
  const PlaylistsScope({super.key, required PlaylistsController controller, this.picker = const NoFilePickerService(), required super.child}) : super(notifier: controller);

  /// Used to choose a cover picture.
  final FilePickerService picker;

  static PlaylistsController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PlaylistsScope>()?.notifier;

  static PlaylistsController of(BuildContext context) => maybeOf(context) ?? (throw StateError('No PlaylistsScope above this screen'));

  static FilePickerService pickerOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PlaylistsScope>()?.picker ?? const NoFilePickerService();
}
