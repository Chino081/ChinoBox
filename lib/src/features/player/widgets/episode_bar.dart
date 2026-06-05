import 'package:flutter/material.dart';

import '../controllers/player_state_controller.dart';

class EpisodeBar extends StatelessWidget {
  const EpisodeBar({
    required this.state,
    required this.sourceName,
    required this.titleText,
    required this.autoPlayNext,
    required this.onNext,
    super.key,
  });

  final PlayerStateController state;
  final String sourceName;
  final String titleText;
  final bool autoPlayNext;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF050505),
            border: Border(top: BorderSide(color: Color(0xFF242424))),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$sourceName \u00b7 MediaKit \u00b7 ${autoPlayNext ? '自动下一集' : '手动下一集'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (state.loadingEpisodes)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                FilledButton.tonalIcon(
                  onPressed: onNext,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('下一集'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
