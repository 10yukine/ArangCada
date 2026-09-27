import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/dashboard_back_button.dart';
import '../../data/providers/repository_providers.dart';

/// Cash earnings from this driver's completed server trips only.
class DriverEarningsScreen extends ConsumerWidget {
  const DriverEarningsScreen({super.key});

  int? _fare(Map<String, dynamic> trip) {
    final pesos = trip['final_fare'];
    return pesos is num ? (pesos * 100).round() : null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    final rides = ref.watch(liveRideRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const DashboardBackButton(isDriver: true),
        title: const Text('Earnings'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([state, rides]),
          builder: (context, _) {
            if (rides == null) {
              return const Center(
                child: Text(
                  'Connect your driver account to see real earnings.',
                ),
              );
            }
            final completed = rides.trips
                .where((trip) => trip['status'] == 'completed')
                .toList();
            final now = DateTime.now();
            final today = completed.where((trip) {
              final date = DateTime.tryParse(
                trip['completed_at'] as String? ?? '',
              )?.toLocal();
              return date != null &&
                  date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
            }).toList();
            int total(List<Map<String, dynamic>> trips) =>
                trips.fold(0, (sum, trip) => sum + (_fare(trip) ?? 0));
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(
                  'Cash earnings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text('Based on completed trips in your account.'),
                const SizedBox(height: AppSpacing.lg),
                Text('Today', style: Theme.of(context).textTheme.titleMedium),
                Text(
                  formatCentavos(total(today)),
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                Text(
                  '${today.length} completed ${today.length == 1 ? 'trip' : 'trips'}',
                ),
                const Divider(height: AppSpacing.xl),
                Text(
                  'All completed trips',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  formatCentavos(total(completed)),
                  style: Theme.of(context).textTheme.headlineMedium,
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
                if (completed.isEmpty)
                  const Text('No completed trips yet.')
                else
                  for (final trip in completed.take(3))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${trip['pickup_label'] ?? 'Pickup'} → ${trip['destination_label'] ?? 'Destination'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _fare(trip) == null
                            ? 'Fare unavailable'
                            : formatCentavos(_fare(trip)!),
                      ),
                    ),
                const Divider(height: AppSpacing.xl),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.account_balance_wallet_outlined),
                  title: Text('Digital payments'),
                  subtitle: Text('In development. Rides currently use cash.'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
