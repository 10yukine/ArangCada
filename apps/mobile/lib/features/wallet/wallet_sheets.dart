import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/payment_repository.dart';

/// Shown on every payment surface. Truthful without shouting: the balance
/// is real-looking but no provider is connected and no money moves.
const demoFundsDisclosure = 'Sandbox payment · no funds moved.';

enum InsufficientBalanceAction { topUp, useCash }

Future<void> showTopUpSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: AppMotion.sheet,
      reverseDuration: AppMotion.sheet,
    ),
    showDragHandle: true,
    builder: (context) => const _TopUpSheet(),
  );
}

Future<InsufficientBalanceAction?> showInsufficientBalanceSheet(
  BuildContext context,
  InsufficientBalanceException exception,
) {
  return showModalBottomSheet<InsufficientBalanceAction>(
    context: context,
    sheetAnimationStyle: const AnimationStyle(
      duration: AppMotion.sheet,
      reverseDuration: AppMotion.sheet,
    ),
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Insufficient digital balance',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            _AmountRow(
              label: 'Available',
              value: formatCentavos(exception.availableCentavos),
            ),
            _AmountRow(
              label: 'Fare',
              value: formatCentavos(exception.requiredCentavos),
            ),
            _AmountRow(
              label: 'Shortfall',
              value: formatCentavos(exception.shortfallCentavos),
              valueColor: AppColors.danger,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, InsufficientBalanceAction.topUp),
              child: const Text('Top Up'),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(AppSizes.buttonHeight),
              ),
              onPressed: () =>
                  Navigator.pop(context, InsufficientBalanceAction.useCash),
              child: const Text('Use Cash Instead'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TopUpSheet extends ConsumerStatefulWidget {
  const _TopUpSheet();

  @override
  ConsumerState<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends ConsumerState<_TopUpSheet> {
  final _customController = TextEditingController();
  int? _selectedCentavos = 10000;
  bool _processing = false;
  bool _completed = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  int? get _amountCentavos {
    final custom = int.tryParse(_customController.text.trim());
    if (_customController.text.trim().isNotEmpty) {
      return custom == null || custom <= 0 ? null : custom * 100;
    }
    return _selectedCentavos;
  }

  Future<void> _completeTopUp() async {
    if (_completed) return;
    final amount = _amountCentavos;
    if (amount == null) {
      setState(() => _processing = false);
      return;
    }
    _completed = true;
    await ref.read(walletRepositoryProvider).topUp(amount);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.green),
        title: const Text('Top-up complete'),
        content: Text(
          '${formatCentavos(amount)} was added to the sandbox balance.\n\n'
          '$demoFundsDisclosure\n'
          'Reference: SBX-TOPUP-20260815-001',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top up sandbox balance',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(demoFundsDisclosure),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final amount in const [10000, 20000, 30000, 50000])
                  ChoiceChip(
                    label: Text(formatCentavos(amount)),
                    selected:
                        _customController.text.isEmpty &&
                        _selectedCentavos == amount,
                    side: BorderSide(
                      color:
                          _customController.text.isEmpty &&
                              _selectedCentavos == amount
                          ? AppColors.coral
                          : AppColors.borderStrong,
                    ),
                    onSelected: _processing
                        ? null
                        : (_) => setState(() {
                            _selectedCentavos = amount;
                            _customController.clear();
                          }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _customController,
              enabled: !_processing,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Custom amount',
                prefixText: '₱',
                hintText: 'Enter whole pesos',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_processing)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: AppMotion.screen,
                onEnd: _completeTopUp,
                builder: (context, value, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: value),
                    const SizedBox(height: AppSpacing.xs),
                    const Text('Processing sandbox top-up…'),
                  ],
                ),
              )
            else
              FilledButton(
                onPressed: _amountCentavos == null
                    ? null
                    : () => setState(() => _processing = true),
                child: const Text('Add to Balance'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}
