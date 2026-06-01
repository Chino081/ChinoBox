import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/detail/detail_page.dart';
import '../features/home/home_shell_page.dart';
import '../features/listing/browse_page.dart';
import '../features/player/player_page.dart';
import '../features/search/search_page.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeShellPage(),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => SearchPage(
        sourceId: state.uri.queryParameters['source'],
        initialQuery: state.uri.queryParameters['q'] ?? '',
      ),
    ),
    GoRoute(
      path: '/browse',
      builder: (context, state) => BrowsePage(
        sourceId: state.uri.queryParameters['source'],
        title: state.uri.queryParameters['title'] ?? '分类浏览',
        path: state.uri.queryParameters['path'] ?? '',
      ),
    ),
    GoRoute(
      path: '/detail',
      builder: (context, state) => DetailPage(
        sourceId: state.uri.queryParameters['source'] ?? '',
        url: state.uri.queryParameters['url'] ?? '',
      ),
    ),
    GoRoute(
      path: '/player',
      pageBuilder: (context, state) => MaterialPage(
        fullscreenDialog: true,
        child: PlayerPage.fromQuery(state.uri.queryParameters),
      ),
    ),
  ],
);

String detailLocation({
  required String sourceId,
  required String url,
}) {
  return Uri(
    path: '/detail',
    queryParameters: {'source': sourceId, 'url': url},
  ).toString();
}

String playerLocation(Map<String, String> params) {
  return Uri(path: '/player', queryParameters: params).toString();
}
