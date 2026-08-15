import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';

class PersonalInformationScreen extends ConsumerWidget {
  const PersonalInformationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(demoStateProvider).currentUser;
    return _DetailScaffold(
      title: 'Personal Information',
      children: [
        SectionCard(
          child: Column(
            children: [
              _InfoRow(label: 'Full name', value: user?.displayName ?? '—'),
              const Divider(height: AppSpacing.lg),
              _InfoRow(label: 'Email', value: user?.email ?? '—'),
              const Divider(height: AppSpacing.lg),
              const _InfoRow(label: 'Account type', value: 'Demo commuter'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This prototype uses fictional demo account data only.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class SavedPlacesScreen extends StatelessWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: 'Saved Places',
      children: [
        EmptyStateCard(
          icon: Icons.bookmark_border,
          title: 'No saved places',
          message: 'Save a frequent pickup or destination for quicker booking.',
          actionLabel: 'Add a Saved Place',
          onAction: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved places are not persisted in this demo.'),
            ),
          ),
        ),
      ],
    );
  }
}

class DiscountEligibilityScreen extends StatelessWidget {
  const DiscountEligibilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DetailScaffold(
      title: 'Discount Eligibility',
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose your fare class when comparing ride options.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Student, Senior Citizen, and PWD selections use the published discounted fare rows. Eligibility verification may be required in production.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SafetySettingsScreen extends StatelessWidget {
  const SafetySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _DetailScaffold(
      title: 'Safety',
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'During an active ride',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Press and hold the SOS control to record a demo safety alert for ArangCada administrators.',
              ),
              SizedBox(height: AppSpacing.md),
              Text(
                'The prototype does not contact police, 911, or emergency services.',
                style: TextStyle(color: AppColors.dangerDark),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text(
          'This restores the seeded balance, transactions, trip, rating, and developer overrides. You will be signed out.',
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
    if (confirmed != true || !context.mounted) return;
    ref.read(demoStateProvider).reset();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DetailScaffold(
      title: 'App Settings',
      children: [
        SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restart_alt, color: AppColors.danger),
            title: const Text('Reset Demo Data'),
            subtitle: const Text(
              'Restore the offline demo to its initial state.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _reset(context, ref),
          ),
        ),
      ],
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: children,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}
