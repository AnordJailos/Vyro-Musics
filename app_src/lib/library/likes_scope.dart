import 'package:flutter/material.dart';

import '../audio/track.dart';
import 'likes_controller.dart';

/// Makes likes available to every screen, so a heart can appear on any song.
class LikesScope extends InheritedNotifier<LikesController> {
  const LikesScope({super.key, required LikesController controller, required super.child}) : super(notifier: controller);

  static LikesController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LikesScope>()?.notifier;
}

/// A heart that likes or unlikes a song. Shows nothing when the app has no likes.
class LikeButton extends StatelessWidget {
  const LikeButton({super.key, required this.track, this.label});

  final Track track;

  /// The song's title, so the button can be told apart from the others on screen.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final likes = LikesScope.maybeOf(context);
    if (likes == null) return const SizedBox.shrink();
    final liked = likes.isLiked(track);
    final what = label == null ? '' : ' $label';
    return IconButton(
      tooltip: liked ? 'Unlike$what' : 'Like$what',
      icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded),
      onPressed: () => likes.toggle(track),
    );
  }
}
