import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/painted_calamba_map.dart';
import '../../data/providers/repository_providers.dart';

class CommuterHomeScreen extends ConsumerWidget {
  const CommuterHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            // The only non-positioned child is the header, so a loose Stack
            // would shrink to the header's height, leaving Positioned.fill to
            // paint a sliver of map behind the sheet and stranding the
            // bottom-docked sheet near the top of the screen.
            fit: StackFit.expand,
            children: [
              const Positioned.fill(
                child: PaintedCalambaMap(
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                  showNearbyDrivers: true,
                  showRoute: false,
                  showDestination: false,
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.94),
                            borderRadius: const BorderRadius.all(
                              Radius.circular(AppRadii.lg),
                            ),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Welcome back',
                                style: AppTypography.caption,
                              ),
                              Text(
                                state.currentUser?.displayName ?? 'Commuter',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.displaySm,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            tooltip: 'Notifications',
                            onPressed: () => context.push('/notifications'),
                            icon: const Icon(Icons.notifications_outlined),
                          ),
                          const Positioned(
                            right: 2,
                            top: 2,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                shape: BoxShape.circle,
                                border: Border.fromBorderSide(
                                  BorderSide(
                                    color: AppColors.surface,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: SizedBox.square(dimension: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppRadii.sheet),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1F1F1E1D),
                        blurRadius: 10,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Align(
                          child: SizedBox(
                            width: 36,
                            height: 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.disabledFill,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          'Where are you going?',
                          style: AppTypography.displaySm,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Row(
                          children: [
                            Icon(Icons.circle, size: 9, color: AppColors.green),
                            SizedBox(width: AppSpacing.xs),
                            Text(
                              '6 drivers nearby',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            const AppRowIcon(Icons.radio_button_checked),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pickup',
                                    style: AppTypography.caption,
                                  ),
                                  Text(
                                    state.pickup.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.label,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        InkWell(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(AppRadii.input),
                          ),
                          onTap: () => context.push('/home/search'),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppColors.inputFill,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(AppRadii.input),
                              ),
                              border: Border.all(color: AppColors.borderStrong),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    state.destination?.name ??
                                        'Choose destination',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        FilledButton.icon(
                          onPressed: state.destination == null
                              ? () => context.push('/home/search')
                              : () => context.push('/home/ride-options'),
                          icon: Icon(
                            state.destination == null
                                ? Icons.search
                                : Icons.directions_car_outlined,
                          ),
                          label: Text(
                            state.destination == null
                                ? 'Find a destination'
                                : 'Compare ride options',
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
      },
    );
  }
}
