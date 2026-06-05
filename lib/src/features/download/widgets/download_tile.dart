import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../data/download_manager.dart';
import '../domain/download_models.dart';

class DownloadTile extends StatelessWidget {
  const DownloadTile({
    required this.task,
    required this.episodes,
    required this.manager,
    this.onDismissed,
    super.key,
  });

  final DownloadTask task;
  final List<DownloadEpisode> episodes;
  final DownloadManager manager;
  final VoidCallback? onDismissed;

  @override
  Widget build(BuildContext context) {
    final downloading =
        episodes.where((e) => e.state == DownloadState.downloading).length;
    final completed =
        episodes.where((e) => e.state == DownloadState.completed).length;
    final failed =
        episodes.where((e) => e.state == DownloadState.failed).length;
    final total = episodes.length;

    // Average progress of active downloads
    final activeEps =
        episodes.where((e) => e.state == DownloadState.downloading).toList();
    final avgProgress = activeEps.isEmpty
        ? 0.0
        : activeEps.map((e) => e.progress).reduce((a, b) => a + b) /
            activeEps.length;

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除确认'),
            content: Text('确定删除「${task.title}」及其所有下载吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        manager.deleteTask(task.id);
        onDismissed?.call();
      },
      child: Card(
        child: ExpansionTile(
          leading: _Thumb(url: task.poster),
          title: Text(task.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                _statusText(downloading, completed, failed, total),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              if (downloading > 0) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: avgProgress.clamp(0.0, 1.0)),
              ],
            ],
          ),
          children: [
            for (final ep in episodes) _EpisodeRow(episode: ep, manager: manager),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _statusText(int downloading, int completed, int failed, int total) {
    final parts = <String>[];
    if (downloading > 0) parts.add('下载中 $downloading');
    if (completed > 0) parts.add('已完成 $completed');
    if (failed > 0) parts.add('失败 $failed');
    parts.add('共 $total 集');
    return parts.join(' · ');
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.manager});

  final DownloadEpisode episode;
  final DownloadManager manager;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _stateIcon(context),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (episode.state == DownloadState.downloading) ...[
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: episode.progress.clamp(0.0, 1.0),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _progressText(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.outline,
                        ),
                  ),
                ],
                if (episode.state == DownloadState.failed &&
                    episode.errorMessage.isNotEmpty)
                  Text(
                    episode.errorMessage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.error,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          _actionButton(context),
        ],
      ),
    );
  }

  Widget _stateIcon(BuildContext context) {
    switch (episode.state) {
      case DownloadState.queued:
        return const Icon(Icons.hourglass_empty_rounded, size: 20);
      case DownloadState.downloading:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: episode.progress > 0 ? episode.progress : null,
          ),
        );
      case DownloadState.paused:
        return Icon(Icons.pause_circle_outline_rounded,
            size: 20, color: Theme.of(context).colorScheme.outline);
      case DownloadState.completed:
        return Icon(Icons.check_circle_rounded,
            size: 20, color: Theme.of(context).colorScheme.primary);
      case DownloadState.failed:
        return Icon(Icons.error_outline_rounded,
            size: 20, color: Theme.of(context).colorScheme.error);
    }
  }

  Widget _actionButton(BuildContext context) {
    switch (episode.state) {
      case DownloadState.downloading:
        return IconButton(
          icon: const Icon(Icons.pause_rounded),
          onPressed: () => manager.pause(episode.id),
          tooltip: '暂停',
        );
      case DownloadState.paused:
      case DownloadState.failed:
        return IconButton(
          icon: Icon(episode.state == DownloadState.paused
              ? Icons.play_arrow_rounded
              : Icons.refresh_rounded),
          onPressed: () {
            if (episode.state == DownloadState.paused) {
              manager.resume(episode.id);
            } else {
              manager.retry(episode.id);
            }
          },
          tooltip: episode.state == DownloadState.paused ? '继续' : '重试',
        );
      case DownloadState.completed:
        return IconButton(
          icon: const Icon(Icons.play_circle_outline_rounded),
          onPressed: () => _playLocal(context),
          tooltip: '播放',
        );
      case DownloadState.queued:
        return IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => manager.cancel(episode.id),
          tooltip: '取消',
        );
    }
  }

  void _playLocal(BuildContext context) {
    context.push(playerLocation({
      'source': '',
      'title': '',
      'poster': '',
      'detailUrl': '',
      'episodeTitle': episode.title,
      'episodeUrl': episode.episodeUrl,
      'playUrl': episode.localPath,
      'playTitle': episode.title,
      if (episode.playHeaders.isNotEmpty)
        'playHeaders':
            base64Url.encode(utf8.encode(jsonEncode(episode.playHeaders))),
    }));
  }

  String _progressText() {
    if (episode.totalBytes > 0) {
      final mb = episode.downloadedBytes / (1024 * 1024);
      final totalMb = episode.totalBytes / (1024 * 1024);
      return '${mb.toStringAsFixed(1)} MB / ${totalMb.toStringAsFixed(1)} MB';
    }
    final mb = episode.downloadedBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: url.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.movie_outlined, size: 20),
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 80,
                errorWidget: (_, __, ___) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.movie_outlined, size: 20),
                ),
              ),
      ),
    );
  }
}
