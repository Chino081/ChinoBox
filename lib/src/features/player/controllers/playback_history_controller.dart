import 'dart:async';

import '../../content/data/content_repository.dart';
import '../../content/domain/content_models.dart';
import '../../../core/logging/app_logger.dart';
import 'player_state_controller.dart';

class PlaybackHistoryController {
  PlaybackHistoryController({
    required this.state,
    required this.contentRepository,
    required this.sourceId,
    required this.title,
    required this.detailUrl,
    required this.poster,
    required this.playHeadersBuilder,
  });

  final PlayerStateController state;
  final ContentRepository contentRepository;
  final String sourceId;
  final String title;
  final String detailUrl;
  final String poster;

  /// Builds effective headers given a play URL and raw headers.
  final Map<String, String> Function(String playUrl, Map<String, String> raw)
      playHeadersBuilder;

  Timer? _saveTimer;

  Future<void> save() async {
    if (detailUrl.isEmpty) return;
    final id = '$sourceId:$detailUrl';
    try {
      await contentRepository.saveHistory(
        HistoryEntry(
          id: id,
          sourceId: sourceId,
          title: title,
          detailUrl: detailUrl,
          episodeTitle: state.currentEpisodeTitle,
          episodeUrl: state.currentEpisodeUrl,
          playUrl: state.currentPlayUrl,
          playHeaders: playHeadersBuilder(
            state.currentPlayUrl,
            state.currentPlayHeaders,
          ),
          poster: poster,
          position: state.position.inMilliseconds,
          duration: state.duration.inMilliseconds,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      AppLogger.warn('保存历史记录失败: $e');
    }
  }

  void startPeriodicSave() {
    _saveTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(save()),
    );
  }

  void dispose() {
    _saveTimer?.cancel();
  }
}
