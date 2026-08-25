import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/dashboard_back_button.dart';
import '../../core/widgets/status_badge.dart';

/// Mirrors the approved driver's earnings screen while retaining the stronger
/// cash/digital breakdown and honest sandbox-settlement disclosure.
class DriverEarningsScreen extends StatelessWidget {
  const DriverEarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const DashboardBackButton(isDriver: true),
        title: const Text('Earnings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          children: [
            const _TodayEarnings(total: 47800, tripCount: 9),
            const SizedBox(height: AppSpacing.sm),
            const Row(
              children: [
                Expanded(
                  child: _EarningsMetric(label: 'This week', value: 268500),
                ),
                SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _EarningsMetric(label: 'Avg per trip', value: 5311),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent trips',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/driver/trips'),
                  child: const Text('Trip history'),
                ),
              ],
            ),
            const _RecentTrips(),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Payment breakdown',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            const _EarningsRow(label: 'Cash rides', value: 29400),
            const _EarningsRow(label: 'Digital rides', value: 18400),
            const _EarningsRow(label: "This week's cash", value: 167300),
            const _EarningsRow(label: "This week's digital", value: 101200),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppRowIcon(Icons.sync_alt),
              title: Text('Settlement status'),
              subtitle: Text(
                'Digital earnings settle through the payment provider once connected. '
                'Sandbox only - no funds moved.',
              ),
              trailing: StatusBadge(
                'Pending',
                variant: StatusBadgeVariant.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayEarnings extends StatelessWidget {
  const _TodayEarnings({required this.total, required this.tripCount});

  final int total;
  final int tripCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.neutralFill,
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          children: [
            Text(
              'Today',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              formatCentavos(total),
              style: AppTypography.display.copyWith(fontSize: 32),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '$tripCount trips · 6.5 hrs online',
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _EarningsMetric extends StatelessWidget {
  const _EarningsMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.caption),
            const SizedBox(height: 2),
            Text(formatCentavos(value), style: AppTypography.h2),
          ],
        ),
      ),
    );
  }
}

class _RecentTrips extends StatelessWidget {
  const _RecentTrips();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.dividerLight),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: const Column(
        children: [
          _RecentTripRow(time: '1:45 PM', name: 'Rico C.', fare: 1500),
          Divider(height: 1),
          _RecentTripRow(time: '11:20 AM', name: 'Nena V.', fare: 6000),
          Divider(height: 1),
          _RecentTripRow(time: '9:05 AM', name: 'Ana S.', fare: 6000),
        ],
      ),
    );
  }
}

class _RecentTripRow extends StatelessWidget {
  const _RecentTripRow({
    required this.time,
    required this.name,
    required this.fare,
  });

  final String time;
  final String name;
  final int fare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$time · $name',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(formatCentavos(fare), style: AppTypography.bodySm),
        ],
      ),
    );
  }
}

class _EarningsRow extends StatelessWidget {
  const _EarningsRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(formatCentavos(value)),
        ],
      ),
    );
  }
}
