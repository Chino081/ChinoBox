import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../features/content/domain/content_models.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    required this.item,
    required this.sourceId,
    this.compact = false,
    super.key,
  });

  final MediaItem item;
  final String sourceId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () =>
          context.push(detailLocation(sourceId: sourceId, url: item.url)),
      child: SizedBox(
        width: compact ? 118 : 142,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 10 / 14,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _PosterImage(url: item.poster),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (item.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

class WideMediaTile extends StatelessWidget {
  const WideMediaTile({
    required this.item,
    required this.sourceId,
    super.key,
  });

  final MediaItem item;
  final String sourceId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        leading: SizedBox(
          width: 56,
          height: 76,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _PosterImage(url: item.poster),
          ),
        ),
        title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [item.subtitle, item.summary].where((e) => e.isNotEmpty).join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () =>
            context.push(detailLocation(sourceId: sourceId, url: item.url)),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.movie_creation_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
