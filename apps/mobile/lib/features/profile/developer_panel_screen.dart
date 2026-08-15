import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';

class DeveloperPanelScreen extends ConsumerStatefulWidget {
  const DeveloperPanelScreen({super.key});

  @override
  ConsumerState<DeveloperPanelScreen> createState() =>
      _DeveloperPanelScreenState();
}

class _DeveloperPanelScreenState extends ConsumerState<DeveloperPanelScreen> {
  final _balanceController = TextEditingController(text: '350');

  @override
  void dispose() {
    _balanceController.dispose();
    super.dispose();
  }

  void _setBalance() {
    final pesos = int.tryParse(_balanceController.text.trim());
    if (pesos == null || pesos < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a whole-peso amount of 0 or more.'),
        ),
      );
      return;
    }
    ref.read(demoStateProvider).setWalletBalanceForDemo(pesos * 100);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Demo balance set to P$pesos.00.')));
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text(
          'This restores all seeded demo values and signs out the current account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset Demo Data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref.read(demoStateProvider).reset();
    context.go('/login');
  }

  void _completeCurrentTrip() {
    final state = ref.read(demoStateProvider);
    final booking = state.activeBooking;
    if (booking == null || booking.status != BookingStatus.inProgress) return;
    booking
      ..completeTrip()
      ..receiptReference = 'DEMO-DEV-COMPLETE-001';
    state.bookingChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Current demo trip completed. No funds moved.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Demo Tools')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final canComplete =
                state.activeBooking?.status == BookingStatus.inProgress;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: const BoxDecoration(
                    color: AppColors.amberFill,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadii.lg),
                    ),
                  ),
                  child: const Text(
                    'Session-only controls for a live academic defence. These are not production features.',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Wallet', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Set digital balance',
                        style: AppTypography.h2,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _balanceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          prefixText: 'P ',
                          hintText: 'Whole pesos',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton(
                        onPressed: _setBalance,
                        child: const Text('Set Demo Balance'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Forced outcomes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        title: const Text('Force no drivers available'),
                        value: state.forceNoDriversAvailable,
                        onChanged: state.setForceNoDriversAvailable,
                      ),
                      const Divider(),
                      SwitchListTile.adaptive(
                        title: const Text('Force payment failure'),
                        value: state.forcePaymentFailure,
                        onChanged: state.setForcePaymentFailure,
                      ),
                      const Divider(),
                      SwitchListTile.adaptive(
                        title: const Text('Force ETA fallback'),
                        value: state.forceEtaFallback,
                        onChanged: state.setForceEtaFallback,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: canComplete ? _completeCurrentTrip : null,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Complete Current Trip'),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  canComplete
                      ? 'Completes the active trip without moving funds.'
                      : 'Available only while a trip is in progress.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerDark,
                    side: const BorderSide(color: AppColors.dangerBorder),
                  ),
                  onPressed: _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset Demo Data'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
