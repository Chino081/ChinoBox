import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../shared/widgets/async_state_view.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/source_badge.dart';
import '../content/data/content_repository.dart';
import '../settings/settings_controller.dart';
import '../source/domain/source_catalog.dart';
import 'source_switch_sheet.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final source = sourceById(settings.sourceId);
    final home = ref.watch(homeProvider);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showSourceSwitchSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(source.name),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more_rounded),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: source.canSearch
                ? () => context.push(
                      Uri(
                        path: '/search',
                        queryParameters: {'source': source.id},
                      ).toString(),
                    )
                : null,
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(homeProvider),
        child: AsyncStateView(
          value: home,
          onRetry: () => ref.invalidate(homeProvider),
          builder: (context, data) {
            if (data.sections.isEmpty) {
              return ListView(
                children: [
                  _SourceHeader(sourceId: source.id, notice: data.notice),
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: EmptyState(
                      message:
                          data.notice.isEmpty ? '暂无内容，换个站点或稍后重试' : data.notice,
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _SourceHeader(sourceId: source.id, notice: data.notice),
                _CategoryStrip(sourceId: source.id),
                for (final section in data.sections) ...[
                  _SectionHeader(
                      title: section.title,
                      sourceId: source.id,
                      moreUrl: section.moreUrl),
                  SizedBox(
                    height: 242,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: section.items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        return PosterCard(
                          item: section.items[index],
                          sourceId: source.id,
                          compact: true,
                        );
                      },
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SourceHeader extends StatelessWidget {
  const _SourceHeader({required this.sourceId, required this.notice});

  final String sourceId;
  final String notice;

  @override
  Widget build(BuildContext context) {
    final source = sourceById(sourceId);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    source.info,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SourceBadge(source: source),
              ],
            ),
            if (notice.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                notice,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryStrip extends ConsumerWidget {
  const _CategoryStrip({required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parser = ref.read(contentRepositoryProvider).parserFor(sourceId);
    final options =
        parser.categories.expand((group) => group.options).take(12).toList();
    if (options.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          return ActionChip(
            avatar: const Icon(Icons.grid_view_rounded, size: 18),
            label: Text(option.title),
            onPressed: () => context.push(
              Uri(
                path: '/browse',
                queryParameters: {
                  'source': sourceId,
                  'title': option.title,
                  'path': option.path,
                },
              ).toString(),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.sourceId,
    required this.moreUrl,
  });

  final String title;
  final String sourceId;
  final String moreUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (moreUrl.isNotEmpty)
            TextButton.icon(
              onPressed: () => context
                  .push(detailLocation(sourceId: sourceId, url: moreUrl)),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('更多'),
            ),
        ],
      ),
    );
  }
}
