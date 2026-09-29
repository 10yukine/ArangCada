import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_data.dart';
import '../search/destination_search_screen.dart';
import 'notification_settings_tile.dart';

class SavedPlacesScreen extends ConsumerStatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  ConsumerState<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends ConsumerState<SavedPlacesScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    final place = await Navigator.of(context).push<DemoPlace>(
      MaterialPageRoute(
        builder: (_) => const DestinationSearchScreen(selectOnly: true),
      ),
    );
    if (place == null || !mounted) return;
    await _update(() => ref.read(savedPlacesRepositoryProvider).save(place));
  }

  Future<void> _update(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update saved places. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(savedPlacesRepositoryProvider).places;
    return _DetailScaffold(
      title: 'Saved places',
      children: [
        const Text('Saved on this device for your account.'),
        const SizedBox(height: AppSpacing.sm),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        if (_busy) const LinearProgressIndicator(),
        if (places.isEmpty)
          EmptyStateCard(
            icon: Icons.bookmark_border,
            title: 'No saved places',
            message:
                'Save a frequent pickup or destination for quicker booking.',
            actionLabel: 'Add a saved place',
            onAction: _busy ? null : _add,
          ),
        for (final place in places)
          ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: Text(place.name),
            subtitle: Text(place.address),
            trailing: IconButton(
              tooltip: 'Remove ${place.name}',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy
                  ? null
                  : () => _update(
                      () => ref
                          .read(savedPlacesRepositoryProvider)
                          .remove(place.id),
                    ),
            ),
            onTap: _busy
                ? null
                : () {
                    ref.read(demoStateProvider).setDestination(place);
                    context.go('/home/ride-options');
                  },
          ),
        if (places.isNotEmpty)
          FilledButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.add),
            label: const Text('Add a saved place'),
          ),
      ],
    );
  }
}

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  static const _demoToolsRoute = '/profile/demo-tools';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DetailScaffold(
      title: 'Settings',
      children: [
        // Notification *settings* live here. The notification list itself is
        // reached from the dashboard bell, so the profile has no duplicate
        // notifications row.
        Text('Notifications', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.xs),
        const SectionCard(
          padding: EdgeInsets.zero,
          child: NotificationSettingsTile(),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Manage alerts and sounds in your phone’s notification settings. '
          'These settings apply to this device.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Security', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.xs),
        Builder(
          builder: (context) {
            // A seeded @arangcada.demo account has no Supabase session --
            // HybridAuthRepository routes it entirely through
            // MockAuthRepository -- so reauthenticate() finds no current
            // user and throws "Sign in again to continue.", a message that
            // makes no sense to someone who very much is signed in and can
            // do nothing about it on this screen. Disable the entry point
            // instead of shipping a dead-end error, matching how the Demo
            // account's other screens (e.g. updateDisplayName) route around
            // capabilities a local test account cannot perform.
            final isDemo =
                ref.watch(demoStateProvider).currentUser?.isDemoAccount ??
                false;
            return SectionCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.lock_outline,
                  color: isDemo ? AppColors.textDisabled : AppColors.primary,
                ),
                title: Text(
                  'Password',
                  style: isDemo
                      ? AppTypography.body.copyWith(
                          color: AppColors.textDisabled,
                        )
                      : null,
                ),
                subtitle: Text(
                  isDemo
                      ? 'Not available for demo accounts.'
                      : 'Change your account password.',
                ),
                trailing: isDemo ? null : const Icon(Icons.chevron_right),
                onTap: isDemo
                    ? null
                    : () => context.push('/profile/change-password'),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Account', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.xs),
        Builder(
          builder: (context) {
            // Demo accounts are shared fixtures with no Supabase account.
            final isDemo =
                ref.watch(demoStateProvider).currentUser?.isDemoAccount ??
                false;
            return SectionCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.delete_outline,
                  color: isDemo ? AppColors.textDisabled : AppColors.danger,
                ),
                title: Text(
                  'Delete account',
                  style: isDemo
                      ? AppTypography.body.copyWith(
                          color: AppColors.textDisabled,
                        )
                      : null,
                ),
                subtitle: Text(
                  isDemo
                      ? 'Not available for demo accounts.'
                      : 'Permanently delete your account and personal data.',
                ),
                trailing: isDemo ? null : const Icon(Icons.chevron_right),
                onTap: isDemo
                    ? null
                    : () => context.push('/profile/delete-account'),
              ),
            );
          },
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
                'Force driver match, incoming requests and other outcomes '
                'for a walkthrough.',
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
