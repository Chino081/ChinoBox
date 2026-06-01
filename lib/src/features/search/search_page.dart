import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/poster_card.dart';
import '../content/data/content_repository.dart';
import '../content/domain/content_models.dart';
import '../settings/settings_controller.dart';
import '../source/domain/source_catalog.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({
    required this.initialQuery,
    this.sourceId,
    super.key,
  });

  final String? sourceId;
  final String initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  var _query = '';
  var _page = 1;
  var _items = <MediaItem>[];
  Future<List<MediaItem>>? _future;

  String get _sourceId {
    return widget.sourceId ?? ref.read(settingsControllerProvider).sourceId;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _query = widget.initialQuery.trim();
    if (_query.isNotEmpty) _search(reset: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search({required bool reset}) {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _query = query;
      _future = _load(reset: reset);
    });
  }

  Future<List<MediaItem>> _load({required bool reset}) async {
    if (reset) {
      _page = 1;
      _items = [];
    }
    final data = await ref
        .read(contentRepositoryProvider)
        .search(_sourceId, _query, _page);
    if (reset) {
      _items = data;
    } else {
      _items = [..._items, ...data];
    }
    return _items;
  }

  @override
  Widget build(BuildContext context) {
    final source = sourceById(_sourceId);
    return Scaffold(
      appBar: AppBar(title: Text('${source.name} 搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: _query.isEmpty,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '请输入检索关键字',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: () => _search(reset: true),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
              onSubmitted: (_) => _search(reset: true),
            ),
          ),
          Expanded(
            child: _future == null
                ? const EmptyState(
                    message: '输入片名、番名或关键词开始搜索', icon: Icons.search_rounded)
                : FutureBuilder<List<MediaItem>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return _ErrorView(
                          message: snapshot.error.toString(),
                          onRetry: () => _search(reset: _items.isEmpty),
                        );
                      }
                      final data = snapshot.data ?? [];
                      if (data.isEmpty) {
                        return const EmptyState(message: '没有找到相关内容');
                      }
                      return _ResultList(
                        sourceId: _sourceId,
                        items: data,
                        onLoadMore: () {
                          setState(() => _page += 1);
                          _search(reset: false);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.sourceId,
    required this.items,
    required this.onLoadMore,
  });

  final String sourceId;
  final List<MediaItem> items;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useGrid = width >= 700;
    if (!useGrid) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == items.length) {
            return Center(
              child: TextButton.icon(
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more_rounded),
                label: const Text('加载更多'),
              ),
            );
          }
          return WideMediaTile(item: items[index], sourceId: sourceId);
        },
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        childAspectRatio: 0.54,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) =>
          PosterCard(item: items[index], sourceId: sourceId),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

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
