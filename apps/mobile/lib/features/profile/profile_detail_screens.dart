import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/demo_user.dart';

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
              _InfoRow(
                label: 'Account type',
                value: user?.role == DemoRole.driver ? 'Driver' : 'Commuter',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Profile details are provided by the signed-in account.',
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
              content: Text(
                'Saved places are stored locally in this prototype.',
              ),
            ),
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
                'Press and hold the SOS control to record a safety alert locally for ArangCada administrators.',
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
        title: const Text('Clear local app data?'),
        content: const Text(
          'This clears local balance, transactions, trip, rating, and testing overrides. You will be signed out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Local Data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(authRepositoryProvider).signOut();
    ref.read(chatRepositoryProvider).clearSession();
    ref.read(demoStateProvider).reset();
    if (context.mounted) context.go('/login');
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
            title: const Text('Clear Local Data'),
            subtitle: const Text(
              'Clear locally simulated trip and wallet data.',
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
