import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_simulation.dart';
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

  void _showForceResult(bool advanced, String successMessage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          advanced ? successMessage : 'That transition is not available now.',
        ),
      ),
    );
  }

  void _forceDriverMatch() {
    final state = ref.read(demoStateProvider);
    final advanced = ref
        .read(demoSimulationServiceProvider)
        .forceDriverMatch(state);
    _showForceResult(advanced, 'A driver was matched to the current ride.');
  }

  void _forceDriverArrival() {
    final state = ref.read(demoStateProvider);
    final advanced = ref
        .read(demoSimulationServiceProvider)
        .forceDriverArrival(state);
    _showForceResult(advanced, 'The driver was moved to the pickup point.');
  }

  void _forceTripCompletion() {
    final state = ref.read(demoStateProvider);
    final advanced = ref
        .read(demoSimulationServiceProvider)
        .forceTripCompletion(state);
    _showForceResult(advanced, 'Current demo trip completed. No funds moved.');
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
            final bookingStatus = state.activeBooking?.status;
            final canMatch = bookingStatus == BookingStatus.searching;
            final canArrive =
                bookingStatus == BookingStatus.matched ||
                bookingStatus == BookingStatus.approaching;
            final canComplete = bookingStatus == BookingStatus.inProgress;
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
                Text(
                  'Manual advancement',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                SectionCard(
                  child: Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: canMatch ? _forceDriverMatch : null,
                        icon: const Icon(Icons.person_search_outlined),
                        label: const Text('Force driver match'),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: canArrive ? _forceDriverArrival : null,
                        icon: const Icon(Icons.pin_drop_outlined),
                        label: const Text('Force driver arrival'),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      OutlinedButton.icon(
                        onPressed: canComplete ? _forceTripCompletion : null,
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Force trip completion'),
                      ),
                    ],
                  ),
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
