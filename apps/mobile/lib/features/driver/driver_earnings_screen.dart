import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/section_card.dart';

class DriverEarningsScreen extends StatelessWidget {
  const DriverEarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Today'),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    formatCentavos(47800),
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const Divider(height: AppSpacing.lg),
                  const _EarningsRow(label: 'Cash rides', value: 29400),
                  const _EarningsRow(label: 'Digital rides', value: 18400),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This week',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(formatCentavos(268500)),
                  const Divider(height: AppSpacing.lg),
                  const _EarningsRow(label: 'Cash', value: 167300),
                  const _EarningsRow(label: 'Digital', value: 101200),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.sync_alt, color: AppColors.info),
                title: Text('Mock settlement status'),
                subtitle: Text(
                  'Digital earnings marked for simulated settlement · Demo only - no funds moved.',
                ),
                trailing: Chip(label: Text('Pending')),
              ),
            ),
          ],
        ),
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
