import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/settings_controller.dart';
import 'router.dart';
import 'theme.dart';

class ChinoBoxApp extends ConsumerWidget {
  const ChinoBoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);

    return MaterialApp.router(
      title: 'ChinoBox',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: settings.themeMode,
      routerConfig: appRouter,
    );
  }
}
