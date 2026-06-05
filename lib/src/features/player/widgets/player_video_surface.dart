import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_video;

import '../controllers/player_state_controller.dart';

class PlayerVideoSurface extends StatelessWidget {
  const PlayerVideoSurface({
    required this.state,
    required this.videoController,
    required this.poster,
    super.key,
  });

  final PlayerStateController state;
  final media_video.VideoController? videoController;
  final String poster;

  @override
  Widget build(BuildContext context) {
    final controller = videoController;
    if (controller == null) return _buildPosterPlaceholder();
    return media_video.Video(
      controller: controller,
      controls: null,
      fit: state.fitMode.fit,
      fill: Colors.black,
      pauseUponEnteringBackgroundMode: false,
    );
  }

  Widget _buildPosterPlaceholder() {
    if (poster.isEmpty) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(Icons.movie_outlined, color: Colors.white54, size: 56),
        ),
      );
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: CachedNetworkImage(
          imageUrl: poster,
          fit: BoxFit.contain,
          memCacheWidth: 284,
          errorWidget: (_, __, ___) {
            return const Icon(
              Icons.movie_outlined,
              color: Colors.white54,
              size: 56,
            );
          },
        ),
      ),
    );
  }
}
