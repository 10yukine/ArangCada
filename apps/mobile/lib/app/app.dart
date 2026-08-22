import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class ArangCadaApp extends ConsumerWidget {
  const ArangCadaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ArangCada',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        // Respect the system text-scale setting (accessibility requires
        // this stays adjustable) but clamp its upper end so a large-text
        // setting cannot overflow the app's fixed-height pill buttons and
        // 48 px minimum tap targets. 1.3x still reads noticeably larger.
        final clampedScaler = MediaQuery.textScalerOf(
          context,
        ).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: clampedScaler),
          child: child!,
        );
      },
    );
  }
}
