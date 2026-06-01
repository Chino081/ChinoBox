import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/poster_card.dart';
import '../content/data/content_repository.dart';
import '../content/domain/content_models.dart';
import '../source/domain/source_catalog.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({
    required this.sourceId,
    required this.url,
    super.key,
  });

  final String sourceId;
  final String url;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  late Future<MediaDetail> _future;

  @override
  void initState() {
    super.initState();
    _future =
        ref.read(contentRepositoryProvider).detail(widget.sourceId, widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final source = sourceById(widget.sourceId);
    return Scaffold(
      appBar: AppBar(title: Text(source.name)),
      body: FutureBuilder<MediaDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _DetailError(
              message: snapshot.error.toString(),
              onRetry: () => setState(() {
                _future = ref
                    .read(contentRepositoryProvider)
                    .detail(widget.sourceId, widget.url);
              }),
            );
          }
          final detail = snapshot.data;
          if (detail == null) return const EmptyState(message: '详情为空');
          return _DetailBody(sourceId: widget.sourceId, detail: detail);
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.sourceId, required this.detail});

  final String sourceId;
  final MediaDetail detail;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  Future<bool>? _favoriteFuture;

  @override
  void initState() {
    super.initState();
    _favoriteFuture = ref.read(contentRepositoryProvider).isFavorite(
          widget.sourceId,
          widget.detail.url,
        );
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 680;
            final poster = ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 10 / 14,
                child: detail.poster.isEmpty
                    ? ColoredBox(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: const Icon(Icons.movie_outlined, size: 48),
                      )
                    : Image.network(detail.poster, fit: BoxFit.cover),
              ),
            );
            final info = _InfoBlock(
              sourceId: widget.sourceId,
              detail: detail,
              favoriteFuture: _favoriteFuture!,
              onFavoriteChanged: () {
                setState(() {
                  _favoriteFuture =
                      ref.read(contentRepositoryProvider).isFavorite(
                            widget.sourceId,
                            widget.detail.url,
                          );
                });
              },
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 210, child: poster),
                  const SizedBox(width: 20),
                  Expanded(child: info),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: SizedBox(width: 180, child: poster)),
                const SizedBox(height: 16),
                info,
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (detail.groups.isNotEmpty)
          for (var i = 0; i < detail.groups.length; i++)
            _EpisodeGroupView(
              sourceId: widget.sourceId,
              detail: detail,
              groupIndex: i,
              group: detail.groups[i],
            ),
        if (detail.groups.isEmpty)
          const EmptyState(
              message: '未找到剧集列表', icon: Icons.playlist_remove_rounded),
        if (detail.recommendations.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '相关推荐',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: detail.recommendations.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return PosterCard(
                  item: detail.recommendations[index],
                  sourceId: widget.sourceId,
                  compact: true,
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoBlock extends ConsumerWidget {
  const _InfoBlock({
    required this.sourceId,
    required this.detail,
    required this.favoriteFuture,
    required this.onFavoriteChanged,
  });

  final String sourceId;
  final MediaDetail detail;
  final Future<bool> favoriteFuture;
  final VoidCallback onFavoriteChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.title,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (detail.score.isNotEmpty)
              Chip(label: Text('评分 ${detail.score}')),
            for (final meta in detail.metadata.take(6)) Chip(label: Text(meta)),
          ],
        ),
        if (detail.summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(detail.summary),
        ],
        const SizedBox(height: 12),
        FutureBuilder<bool>(
          future: favoriteFuture,
          builder: (context, snapshot) {
            final isFavorite = snapshot.data ?? false;
            return FilledButton.tonalIcon(
              onPressed: () async {
                await ref
                    .read(contentRepositoryProvider)
                    .toggleFavorite(detail, sourceId);
                onFavoriteChanged();
              },
              icon: Icon(isFavorite
                  ? Icons.bookmark_remove_rounded
                  : Icons.bookmark_add_outlined),
              label: Text(isFavorite ? '取消收藏' : '收藏'),
            );
          },
        ),
      ],
    );
  }
}

class _EpisodeGroupView extends ConsumerWidget {
  const _EpisodeGroupView({
    required this.sourceId,
    required this.detail,
    required this.groupIndex,
    required this.group,
  });

  final String sourceId;
  final MediaDetail detail;
  final int groupIndex;
  final EpisodeGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final episode in group.episodes)
                  OutlinedButton(
                    onPressed: () async {
                      await _openEpisode(context, ref, episode);
                    },
                    child: Text(episode.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEpisode(
      BuildContext context, WidgetRef ref, Episode episode) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final items = await ref
          .read(contentRepositoryProvider)
          .playItems(sourceId, episode.url);
      if (context.mounted) Navigator.of(context).pop();
      if (!context.mounted) return;
      if (items.length == 1) {
        context.push(_locationFor(episode, items.first));
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => ListView.builder(
          shrinkWrap: true,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: const Icon(Icons.play_circle_outline_rounded),
              title:
                  Text(item.title.isEmpty ? '播放地址 ${index + 1}' : item.title),
              subtitle: Text(item.type.name.toUpperCase()),
              onTap: () {
                Navigator.of(context).pop();
                context.push(_locationFor(episode, item));
              },
            );
          },
        ),
      );
    } catch (error) {
      if (context.mounted) Navigator.of(context).pop();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  String _locationFor(Episode episode, PlayItem play) {
    return playerLocation({
      'source': sourceId,
      'title': detail.title,
      'poster': detail.poster,
      'detailUrl': detail.url,
      'episodeTitle': episode.title,
      'episodeUrl': episode.url,
      'playUrl': play.url,
      if (play.headers.isNotEmpty)
        'playHeaders': base64Url.encode(utf8.encode(jsonEncode(play.headers))),
    });
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 36),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
