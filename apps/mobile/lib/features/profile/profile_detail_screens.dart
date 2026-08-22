import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../core/widgets/arang_dialog.dart';

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

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  static const _demoToolsRoute = '/profile/demo-tools';

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ArangDialog(
        title: 'Clear local app data?',
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
        // Notification *settings* live here. The notification list itself is
        // reached from the dashboard bell, so the profile has no duplicate
        // notifications row.
        Text('Notifications', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.xs),
        SectionCard(
          padding: EdgeInsets.zero,
          child: const Column(children: [
            _NotificationToggle(
              title: 'Ride updates',
              subtitle: 'Driver assigned, arrival, and trip completion.',
              initial: true,
            ),
            Divider(height: 1, color: AppColors.dividerLight),
            _NotificationToggle(
              title: 'Chat messages',
              subtitle: 'New messages during an active ride.',
              initial: true,
            ),
            Divider(height: 1, color: AppColors.dividerLight),
            _NotificationToggle(
              title: 'Announcements',
              subtitle: 'Fare matrix changes and TODA advisories.',
              initial: false,
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Preferences are stored on this device only; the prototype does not '
          'send push notifications.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Data', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.xs),
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
        // Only the seeded @arangcada.demo accounts see this. It replaces the
        // old hidden 5-tap on the About screen's version string with a
        // discoverable path -- that shortcut still works too.
        if (ref.watch(demoStateProvider).currentUser?.isDemoAccount ??
            false) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('Demo', style: AppTypography.h2),
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: const BoxDecoration(
              color: AppColors.amberFill,
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
            ),
            child: const Text(
              'Visible because this is a seeded demo account. Session-only '
              'controls for a live walkthrough or defence -- never shown on a '
              'real account.',
              style: AppTypography.caption,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SectionCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.build_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Demo Tools'),
              subtitle: const Text(
                'Force driver match, incoming requests, wallet balance, and '
                'other forced outcomes for a walkthrough.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(_demoToolsRoute),
            ),
          ),
        ],
      ],
    );
  }
}

/// Device-local notification preference. Deliberately not persisted: the
/// prototype sends no push notifications, so storing the value would imply
/// an effect it does not have.
class _NotificationToggle extends StatefulWidget {
  const _NotificationToggle({
    required this.title,
    required this.subtitle,
    required this.initial,
  });

  final String title;
  final String subtitle;
  final bool initial;

  @override
  State<_NotificationToggle> createState() => _NotificationToggleState();
}

class _NotificationToggleState extends State<_NotificationToggle> {
  late bool _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: _value,
      onChanged: (next) => setState(() => _value = next),
      title: Text(widget.title),
      subtitle: Text(widget.subtitle, style: AppTypography.caption),
      activeThumbColor: AppColors.primary,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
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
