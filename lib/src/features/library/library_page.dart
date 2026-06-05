import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../shared/widgets/empty_state.dart';
import '../content/data/content_repository.dart';
import '../content/domain/content_models.dart';
import '../download/download_page.dart';
import '../source/domain/source_catalog.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({required this.isActive, super.key});

  final bool isActive;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late Future<List<FavoriteEntry>> _favorites;
  late Future<List<HistoryEntry>> _history;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _reload();
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      setState(_reload);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    final repo = ref.read(contentRepositoryProvider);
    _favorites = repo.favorites();
    _history = repo.history();
  }

  void _refresh() {
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏历史'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '收藏'),
            Tab(text: '历史'),
            Tab(text: '下载'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FutureBuilder<List<FavoriteEntry>>(
            future: _favorites,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const EmptyState(message: '还没有收藏内容');
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _FavoriteTile(
                  item: items[index],
                  onDismissed: () {
                    final removed = items[index];
                    ref.read(contentRepositoryProvider).removeFavorite(removed.id);
                    _refresh();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已删除收藏「${removed.title}」'),
                        action: SnackBarAction(
                          label: '撤销',
                          onPressed: () {
                            ref.read(contentRepositoryProvider).restoreFavorite(removed);
                            _refresh();
                          },
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          FutureBuilder<List<HistoryEntry>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return const EmptyState(message: '还没有播放历史');
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _HistoryTile(
                  item: items[index],
                  onDismissed: () {
                    final removed = items[index];
                    ref.read(contentRepositoryProvider).removeHistory(removed.id);
                    _refresh();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已删除播放记录「${removed.title}」'),
                        action: SnackBarAction(
                          label: '撤销',
                          onPressed: () {
                            ref.read(contentRepositoryProvider).saveHistory(removed);
                            _refresh();
                          },
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const DownloadPage(),
        ],
      ),
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({required this.item, required this.onDismissed});

  final FavoriteEntry item;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDismissed(),
      child: Card(
        child: ListTile(
          leading: _Thumb(url: item.poster),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(sourceById(item.sourceId).name),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context
              .push(detailLocation(sourceId: item.sourceId, url: item.detailUrl)),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item, required this.onDismissed});

  final HistoryEntry item;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final progress = item.duration <= 0 ? 0.0 : item.position / item.duration;
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDismissed(),
      child: Card(
        child: ListTile(
          leading: _Thumb(url: item.poster),
          title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${sourceById(item.sourceId).name} · ${item.episodeTitle}'),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0).toDouble()),
            ],
          ),
          trailing: const Icon(Icons.play_arrow_rounded),
          onTap: () => context.push(playerLocation({
            'source': item.sourceId,
            'title': item.title,
            'poster': item.poster,
            'detailUrl': item.detailUrl,
            'episodeTitle': item.episodeTitle,
            'episodeUrl': item.episodeUrl,
            'playUrl': item.playUrl,
            if (item.playHeaders.isNotEmpty)
              'playHeaders':
                  base64Url.encode(utf8.encode(jsonEncode(item.playHeaders))),
          })),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 64,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: url.isEmpty
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.movie_outlined),
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 96,
                errorWidget: (_, __, ___) => ColoredBox(
                  color:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.movie_outlined),
                ),
              ),
      ),
    );
  }
}
