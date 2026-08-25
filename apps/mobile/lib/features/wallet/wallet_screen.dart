import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/dashboard_back_button.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/wallet_transaction.dart';
import 'wallet_sheets.dart';

/// Flat sections separated by dividers and negative space, matching Earnings
/// and Profile -- a balance and a transaction list don't need a bordered box
/// to read as their own group.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  void _showTransactions(
    BuildContext context,
    List<WalletTransaction> transactions,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transactions',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (transactions.isEmpty)
                const EmptyStateCard(
                  icon: Icons.receipt_long_outlined,
                  title: 'No wallet transactions',
                  message:
                      'Sandbox top-ups and ride payments will appear here.',
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: transactions.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) =>
                        _TransactionTile(transactions[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    final wallet = ref.watch(walletRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const DashboardBackButton(isDriver: false),
        title: const Text('Wallet'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Digital balance',
                        style: AppTypography.label.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    // Status chip rather than a "Demo" label in the field
                    // name: the screen reads like a product, and the
                    // sandbox nature is still stated, once.
                    const ArangBadge('SANDBOX', tone: ArangBadgeTone.amber),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  formatCentavos(wallet.balanceCentavos),
                  style: AppTypography.display,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(demoFundsDisclosure),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'ArangCada does not hold or custody funds. Production '
                  'digital balances are provider-held.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => showTopUpSheet(context, ref),
                        icon: const Icon(Icons.add_card),
                        label: const Text('Top Up'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _showTransactions(context, wallet.transactions),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Transactions'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Transaction history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (wallet.transactions.isEmpty)
                  EmptyStateCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'No wallet transactions',
                    message:
                        'Sandbox top-ups and ride payments will appear here.',
                    actionLabel: 'Top Up',
                    onAction: () => showTopUpSheet(context, ref),
                  )
                else ...[
                  const Divider(height: 1),
                  for (final transaction in wallet.transactions) ...[
                    _TransactionTile(transaction),
                    const Divider(height: 1),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile(this.transaction);

  final WalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final icon = switch (transaction.kind) {
      WalletTransactionKind.topUp => Icons.add_card,
      WalletTransactionKind.ridePayment => Icons.electric_rickshaw_outlined,
      WalletTransactionKind.refund => Icons.replay,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AppRowIcon(icon),
      title: Text(transaction.title),
      subtitle: Text(
        '${transaction.status} · ${transaction.id}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${transaction.amountCentavos > 0 ? '+' : ''}'
        '${formatCentavos(transaction.amountCentavos)}',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: transaction.amountCentavos > 0
              ? AppColors.green
              : AppColors.ink,
        ),
      ),
    );
  }
}
