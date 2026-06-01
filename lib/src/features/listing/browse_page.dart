import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/poster_card.dart';
import '../content/data/content_repository.dart';
import '../content/domain/content_models.dart';
import '../settings/settings_controller.dart';
import '../source/domain/source_catalog.dart';

class BrowsePage extends ConsumerStatefulWidget {
  const BrowsePage({
    required this.title,
    required this.path,
    this.sourceId,
    super.key,
  });

  final String? sourceId;
  final String title;
  final String path;

  @override
  ConsumerState<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends ConsumerState<BrowsePage> {
  var _page = 1;
  var _items = <MediaItem>[];
  late Future<List<MediaItem>> _future;

  String get _sourceId =>
      widget.sourceId ?? ref.read(settingsControllerProvider).sourceId;

  @override
  void initState() {
    super.initState();
    _future = _load(reset: true);
  }

  Future<List<MediaItem>> _load({required bool reset}) async {
    if (reset) {
      _page = 1;
      _items = [];
    }
    final data = await ref
        .read(contentRepositoryProvider)
        .browse(_sourceId, widget.path, _page);
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
      appBar: AppBar(title: Text('${source.name} · ${widget.title}')),
      body: FutureBuilder<List<MediaItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _BrowseError(
              message: snapshot.error.toString(),
              onRetry: () =>
                  setState(() => _future = _load(reset: _items.isEmpty)),
            );
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) return const EmptyState(message: '暂无内容');
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              childAspectRatio: 0.54,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
            ),
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == items.length) {
                return Center(
                  child: IconButton.filledTonal(
                    tooltip: '加载更多',
                    onPressed: () {
                      setState(() {
                        _page += 1;
                        _future = _load(reset: false);
                      });
                    },
                    icon: const Icon(Icons.expand_more_rounded),
                  ),
                );
              }
              return PosterCard(item: items[index], sourceId: _sourceId);
            },
          );
        },
      ),
    );
  }
}

class _BrowseError extends StatelessWidget {
  const _BrowseError({required this.message, required this.onRetry});

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
