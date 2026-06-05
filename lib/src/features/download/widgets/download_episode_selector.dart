import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../content/data/content_repository.dart';
import '../../content/domain/content_models.dart';
import '../data/download_manager.dart';

class DownloadEpisodeSelector extends ConsumerStatefulWidget {
  const DownloadEpisodeSelector({
    required this.sourceId,
    required this.detail,
    super.key,
  });

  final String sourceId;
  final MediaDetail detail;

  static Future<void> show(
    BuildContext context, {
    required String sourceId,
    required MediaDetail detail,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DownloadEpisodeSelector(
        sourceId: sourceId,
        detail: detail,
      ),
    );
  }

  @override
  ConsumerState<DownloadEpisodeSelector> createState() =>
      _DownloadEpisodeSelectorState();
}

class _DownloadEpisodeSelectorState
    extends ConsumerState<DownloadEpisodeSelector> {
  final Set<String> _selected = {};
  bool _isSubmitting = false;
  int _groupIndex = 0;

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final groups = detail.groups;

    if (groups.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('暂无可下载的剧集')),
      );
    }

    final currentGroup = groups[_groupIndex];
    final hasSelection = _selected.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '下载 - ${detail.title}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (groups.length > 1)
                    DropdownButton<int>(
                      value: _groupIndex,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (int i = 0; i < groups.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(groups[i].title),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() {
                          _groupIndex = v;
                          _selected.clear();
                        });
                      },
                    ),
                ],
              ),
            ),
            // Select all / deselect all
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selected.length ==
                            currentGroup.episodes.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(
                            currentGroup.episodes.map((e) => e.url),
                          );
                        }
                      });
                    },
                    child: Text(
                      _selected.length == currentGroup.episodes.length
                          ? '取消全选'
                          : '全选',
                    ),
                  ),
                  const Spacer(),
                  if (hasSelection)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '已选 ${_selected.length} 集',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Episode list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: currentGroup.episodes.length,
                itemBuilder: (context, index) {
                  final ep = currentGroup.episodes[index];
                  final isSelected = _selected.contains(ep.url);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(ep.url);
                        } else {
                          _selected.remove(ep.url);
                        }
                      });
                    },
                    title: Text(ep.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            const Divider(height: 1),
            // Download button
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: hasSelection && !_isSubmitting
                        ? _submit
                        : null,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(
                      _isSubmitting
                          ? '正在解析...'
                          : hasSelection
                              ? '下载 ${_selected.length} 集'
                              : '请选择剧集',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_selected.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    final manager = ref.read(downloadManagerProvider);
    final repo = ref.read(contentRepositoryProvider);
    final detail = widget.detail;

    try {
      // Create or get the download task
      final task = await manager.addTask(
        sourceId: widget.sourceId,
        title: detail.title,
        detailUrl: detail.url,
        poster: detail.poster,
      );

      final group = detail.groups[_groupIndex];
      final episodesToDownload =
          group.episodes.where((e) => _selected.contains(e.url)).toList();

      int successCount = 0;
      int skipCount = 0;

      for (final episode in episodesToDownload) {
        try {
          // Resolve actual play URL
          final items =
              await repo.playItems(widget.sourceId, episode.url);
          if (items.isEmpty) {
            skipCount++;
            continue;
          }

          final play = items.firstWhere(
            (item) => item.type == PlayType.mp4,
            orElse: () => items.first,
          );

          // Skip m3u8 downloads
          if (play.type == PlayType.m3u8) {
            AppLogger.info('跳过M3U8格式: ${episode.title}');
            skipCount++;
            continue;
          }

          await manager.addEpisode(
            taskId: task.id,
            episodeTitle: episode.title,
            episodeUrl: episode.url,
            playUrl: play.url,
            playHeaders: play.headers,
          );
          successCount++;
        } catch (e) {
          AppLogger.warn('解析播放地址失败: ${episode.title} - $e');
          skipCount++;
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        String message;
        if (successCount > 0 && skipCount > 0) {
          message = '已添加 $successCount 集下载，跳过 $skipCount 集';
        } else if (successCount > 0) {
          message = '已添加 $successCount 集下载';
        } else {
          message = '没有可用的MP4下载地址';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加下载失败: $e')),
        );
      }
    }
  }
}
