import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/wallet_transaction.dart';
import 'wallet_sheets.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    final wallet = ref.watch(walletRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Demo digital balance',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        formatCentavos(wallet.balanceCentavos),
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(demoFundsDisclosure),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'ArangCada does not hold or custody funds. Production '
                        'digital balances are provider-held.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: () => showTopUpSheet(context, ref),
                        icon: const Icon(Icons.add_card),
                        label: const Text('Top Up'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Transaction history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final transaction in wallet.transactions) ...[
                  SectionCard(
                    child: ListTile(
                      leading: AppRowIcon(
                        transaction.kind == WalletTransactionKind.topUp
                            ? Icons.add_card
                            : Icons.electric_rickshaw_outlined,
                      ),
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
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
