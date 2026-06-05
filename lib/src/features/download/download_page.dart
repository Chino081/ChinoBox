import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_state.dart';
import 'data/download_manager.dart';
import 'domain/download_models.dart';
import 'widgets/download_tile.dart';

enum _DownloadFilter { all, downloading, completed }

class DownloadPage extends ConsumerStatefulWidget {
  const DownloadPage({super.key});

  @override
  ConsumerState<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends ConsumerState<DownloadPage> {
  _DownloadFilter _filter = _DownloadFilter.all;

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(downloadManagerProvider);

    if (!manager.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final tasks = manager.tasks;
    if (tasks.isEmpty) {
      return const EmptyState(
        message: '还没有下载内容',
        icon: Icons.download_rounded,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SegmentedButton<_DownloadFilter>(
            segments: const [
              ButtonSegment(
                value: _DownloadFilter.all,
                label: Text('全部'),
              ),
              ButtonSegment(
                value: _DownloadFilter.downloading,
                label: Text('下载中'),
              ),
              ButtonSegment(
                value: _DownloadFilter.completed,
                label: Text('已完成'),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (v) => setState(() => _filter = v.first),
          ),
        ),
        Expanded(
          child: _DownloadList(
            manager: manager,
            tasks: tasks,
            filter: _filter,
          ),
        ),
      ],
    );
  }
}

class _DownloadList extends StatefulWidget {
  const _DownloadList({
    required this.manager,
    required this.tasks,
    required this.filter,
  });

  final DownloadManager manager;
  final List<DownloadTask> tasks;
  final _DownloadFilter filter;

  @override
  State<_DownloadList> createState() => _DownloadListState();
}

class _DownloadListState extends State<_DownloadList> {
  final Map<String, List<DownloadEpisode>> _episodeCache = {};

  @override
  void initState() {
    super.initState();
    _loadAllEpisodes();
    widget.manager.addListener(_onManagerChanged);
  }

  @override
  void didUpdateWidget(covariant _DownloadList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      oldWidget.manager.removeListener(_onManagerChanged);
      widget.manager.addListener(_onManagerChanged);
      _loadAllEpisodes();
    }
  }

  @override
  void dispose() {
    widget.manager.removeListener(_onManagerChanged);
    super.dispose();
  }

  void _onManagerChanged() {
    _loadAllEpisodes();
  }

  Future<void> _loadAllEpisodes() async {
    for (final task in widget.tasks) {
      final episodes = await widget.manager.episodesForTask(task.id);
      if (mounted) {
        setState(() {
          _episodeCache[task.id] = episodes;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTasks();
    if (filtered.isEmpty) {
      return EmptyState(
        message: _emptyMessage(),
        icon: Icons.download_done_rounded,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _loadAllEpisodes(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final task = filtered[index];
          final episodes = _episodeCache[task.id] ?? [];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: DownloadTile(
              task: task,
              episodes: episodes,
              manager: widget.manager,
              onDismissed: () => _loadAllEpisodes(),
            ),
          );
        },
      ),
    );
  }

  List<DownloadTask> _filteredTasks() {
    return widget.tasks.where((task) {
      final episodes = _episodeCache[task.id] ?? [];
      switch (widget.filter) {
        case _DownloadFilter.all:
          return episodes.isNotEmpty;
        case _DownloadFilter.downloading:
          return episodes.any((e) =>
              e.state == DownloadState.downloading ||
              e.state == DownloadState.queued ||
              e.state == DownloadState.paused);
        case _DownloadFilter.completed:
          return episodes.any((e) => e.state == DownloadState.completed);
      }
    }).toList();
  }

  String _emptyMessage() {
    switch (widget.filter) {
      case _DownloadFilter.all:
        return '还没有下载内容';
      case _DownloadFilter.downloading:
        return '没有正在下载的内容';
      case _DownloadFilter.completed:
        return '没有已完成的下载';
    }
  }
}
