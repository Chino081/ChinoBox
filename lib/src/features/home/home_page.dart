import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../shared/widgets/async_state_view.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/source_badge.dart';
import '../content/data/content_repository.dart';
import '../content/data/parser_registry.dart';
import '../content/domain/content_models.dart';
import '../settings/settings_controller.dart';
import '../source/data/domain_resolver.dart';
import '../source/domain/source_catalog.dart';
import 'source_switch_sheet.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _domainChecked = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final source = sourceById(settings.sourceId);
    final home = ref.watch(homeProvider);

    if (!_domainChecked) {
      _domainChecked = true;
      ref.listen<AsyncValue<HomePayload>>(homeProvider, (prev, next) {
        if (next.hasValue && !next.isLoading) {
          final sources = visibleSourceCatalog()
              .where((s) => s.hasReleasePage)
              .toList();
          if (sources.isNotEmpty) {
            unawaited(DomainResolver.instance.checkAll(sources, settings));
          }
        }
      });
    }

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
                if (data.banners.isNotEmpty &&
                    (Platform.isAndroid || Platform.isIOS))
                  _BannerCarousel(banners: data.banners, sourceId: source.id),
                if (data.rssItems.isNotEmpty)
                  _RssSection(items: data.rssItems),
                for (final section in data.sections)
                  if (!section.isBanner) ...[
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
    final groups = parser.categories;
    if (groups.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              group.title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.options.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final option = group.options[index];
                return ActionChip(
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
          ),
        ],
      ],
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

class _RssSection extends StatelessWidget {
  const _RssSection({required this.items});

  final List<RssItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '最新更新',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ...items.take(8).map((item) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text(item.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: item.pubDate != null
                      ? Text(_relativeTime(item.pubDate!))
                      : null,
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => launchUrl(Uri.parse(item.link)),
                ),
              )),
        ],
      ),
    );
  }

  static String _relativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }
}

class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel({required this.banners, required this.sourceId});

  final List<MediaItem> banners;
  final String sourceId;

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || widget.banners.length < 2) return;
      _current = (_current + 1) % widget.banners.length;
      _controller.animateToPage(
        _current,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.banners.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (context, index) {
                  final item = widget.banners[index];
                  return GestureDetector(
                    onTap: () => context.push(
                      detailLocation(
                        sourceId: widget.sourceId,
                        url: item.url,
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.poster.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: item.poster,
                            fit: BoxFit.cover,
                            memCacheWidth: 640,
                            errorWidget: (_, __, ___) => ColoredBox(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                            ),
                          )
                        else
                          ColoredBox(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black54],
                              ),
                            ),
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (widget.banners.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.banners.length, (i) {
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _current
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}
