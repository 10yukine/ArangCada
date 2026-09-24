import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class ArangCadaApp extends ConsumerWidget {
  const ArangCadaApp({super.key});

  static const _systemOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemOverlayStyle,
      child: MaterialApp.router(
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
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: _systemOverlayStyle,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: clampedScaler),
              child: child!,
            ),
          );
        },
      ),
    );
  }
}
