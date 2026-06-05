import 'package:flutter/material.dart';

import '../models/player_episode_ref.dart';

class EpisodeSheet extends StatelessWidget {
  const EpisodeSheet({
    required this.episodes,
    required this.currentIndex,
    required this.isFullscreen,
    super.key,
  });

  final List<PlayerEpisodeRef> episodes;
  final int currentIndex;
  final bool isFullscreen;

  static Future<int?> show(
    BuildContext context, {
    required List<PlayerEpisodeRef> episodes,
    required int currentIndex,
    required bool isFullscreen,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF101010),
      showDragHandle: true,
      builder: (_) => EpisodeSheet(
        episodes: episodes,
        currentIndex: currentIndex,
        isFullscreen: isFullscreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height =
        MediaQuery.sizeOf(context).height * (isFullscreen ? 0.82 : 0.64);
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选集',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 118,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.45,
                  ),
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    final episode = episodes[index];
                    final selected = index == currentIndex;
                    return FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(index),
                      style: FilledButton.styleFrom(
                        backgroundColor: selected
                            ? const Color(0xFFFF4081)
                            : const Color(0xFF252525),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        episode.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
