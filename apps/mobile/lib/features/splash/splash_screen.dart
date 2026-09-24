import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/arangcada_mark.dart';
import '../../data/providers/repository_providers.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restoration = ref.watch(sessionRestorationProvider);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Centered at the exact window center, identical to Android 12+ native splash
          Center(
            child: SizedBox(
              width: 172,
              height: 172,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.primaryFill,
                          Color(0x00E4F0FE),
                        ],
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                  const ArangCadaMark(badge: true, showName: false),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: AppSpacing.xl,
                  left: AppSpacing.xl,
                  right: AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (restoration.hasError) ...[
                      const Text(
                        'We couldn’t restore your account. Check your connection and try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(sessionRestorationProvider),
                        child: const Text('Try again'),
                      ),
                    ] else
                      const SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: AppColors.inputFill,
                          semanticsLabel: 'Restoring your account',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
