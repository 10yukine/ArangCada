import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can sign back in with either demo account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(authRepositoryProvider).signOut();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SectionCard(
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 21,
                      backgroundColor: AppColors.clayFill,
                      child: Icon(Icons.person, color: AppColors.primary),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.currentUser?.displayName ?? 'Demo commuter',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            state.currentUser?.email ?? '',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ProfileRow(
                      icon: Icons.badge_outlined,
                      label: 'Personal Information',
                      route: '/profile/personal-information',
                    ),
                    const Divider(),
                    _ProfileRow(
                      icon: Icons.bookmark_border,
                      label: 'Saved Places',
                      route: '/profile/saved-places',
                    ),
                    const Divider(),
                    _ProfileRow(
                      icon: Icons.discount_outlined,
                      label: 'Discount Eligibility',
                      route: '/profile/discount-eligibility',
                    ),
                    const Divider(),
                    _ProfileRow(
                      icon: Icons.shield_outlined,
                      label: 'Safety',
                      route: '/profile/safety',
                    ),
                    const Divider(),
                    _ProfileRow(
                      icon: Icons.notifications_outlined,
                      label: 'Notifications',
                      route: '/notifications',
                    ),
                    const Divider(),
                    _ProfileRow(
                      icon: Icons.settings_outlined,
                      label: 'App Settings',
                      route: '/profile/app-settings',
                    ),
                    const Divider(),
                    _ProfileRow(
                      icon: Icons.info_outline,
                      label: 'About ArangCada',
                      route: '/profile/about',
                    ),
                    const Divider(),
                    _ProfileRow(
                      icon: Icons.developer_mode,
                      label: 'Demo Tools',
                      route: '/profile/demo-tools',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.dangerDark,
                  side: const BorderSide(color: AppColors.dangerBorder),
                ),
                onPressed: () => _logout(context, ref),
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AppRowIcon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
  }
}
