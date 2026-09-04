import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/arang_dialog.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/dashboard_back_button.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/demo_user.dart';

/// One profile screen for both roles.
///
/// Commuter and driver deliberately share this widget rather than each
/// owning a copy: the two screens are supposed to look and behave the same,
/// and two copies drift the moment one is edited. The driver's only
/// difference is an extra LGU-governed section, expressed as a flag rather
/// than a second screen.
///
/// Editing lives on the pencil in the header, not on a "Personal
/// Information" row. Notifications are reached from the dashboard bell, and
/// notification *settings* live in App Settings, so there is no
/// notifications row here.
///
/// Rows sit flat on the page background, separated by hairline dividers,
/// rather than grouped inside bordered cards -- matching the reference
/// prototype's flatter list style. A card would only be justified here if it
/// communicated hierarchy; a single settings list does not need one.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ArangDialog(
        title: 'Log out?',
        content: const Text('You can sign back in with your account.'),
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
    ref.read(chatRepositoryProvider).clearSession();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    final isDriver = state.currentUser?.role == DemoRole.driver;

    return Scaffold(
      appBar: AppBar(
        leading: DashboardBackButton(isDriver: isDriver),
        title: const Text('Profile'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final user = state.currentUser;

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: _ProfileHeader(
                    name:
                        user?.displayName ?? (isDriver ? 'Driver' : 'Commuter'),
                    subtitle: isDriver
                        ? 'Body no. 024 · Calamba TODA'
                        : (user?.email ?? ''),
                    isDriver: isDriver,
                  ),
                ),
                if (isDriver) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: _SectionLabel('LGU & TODA records'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _ProfileRow(
                    icon: Icons.description_outlined,
                    label: 'Franchise & documents',
                    onTap: () =>
                        _governedNotice(context, 'Franchise & documents'),
                    trailing: const ArangBadge(
                      'Verified',
                      tone: ArangBadgeTone.green,
                    ),
                  ),
                  const Divider(height: 1),
                  _ProfileRow(
                    icon: Icons.groups_outlined,
                    label: 'TODA membership',
                    onTap: () => _governedNotice(context, 'TODA membership'),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: _SectionLabel('Account'),
                ),
                const SizedBox(height: AppSpacing.xs),
                // A driver's places and fare-discount status are the
                // rider's concerns, not theirs -- they run under a fixed
                // TODA fare, not a discount card they carry.
                if (!isDriver) ...[
                  _ProfileRow(
                    icon: Icons.bookmark_border,
                    label: 'Saved Places',
                    onTap: () => context.push('/profile/saved-places'),
                  ),
                  const Divider(height: 1),
                ],
                // Drivers only. A commuter already has a "View fare matrix"
                // card on their home screen, so a second entry point here was
                // pure duplication -- and it was the row that pushed this list
                // past one screen, forcing a scroll to reach Sign out.
                //
                // A driver has no such card, so removing it for them would
                // take away their only route to the LGU rates.
                if (isDriver) ...[
                  _ProfileRow(
                    icon: Icons.discount_outlined,
                    label: 'Fare matrix',
                    onTap: () => context.push('/fare-matrix'),
                  ),
                  const Divider(height: 1),
                ],
                if (!isDriver) ...[
                  _ProfileRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Discount Eligibility',
                    onTap: () => context.push('/profile/discount-eligibility'),
                  ),
                  const Divider(height: 1),
                ],
                _ProfileRow(
                  icon: Icons.support_agent_outlined,
                  label: 'Support',
                  onTap: () => context.push('/profile/support'),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.settings_outlined,
                  label: 'App Settings',
                  onTap: () => context.push('/profile/app-settings'),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.info_outline,
                  label: 'About ArangCada',
                  onTap: () => context.push('/profile/about'),
                ),
                const Divider(height: 1),
                // Same flat row as everything above it -- only the red icon
                // and label mark it as destructive. No separate pill/card
                // button, no chevron (it's a terminal action, not a drill
                // down).
                _ProfileRow(
                  icon: Icons.logout,
                  label: 'Sign out',
                  danger: true,
                  showChevron: false,
                  onTap: () => _logout(context, ref),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            );
          },
        ),
      ),
    );
  }

  void _governedNotice(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what is managed by the LGU/TODA office.')),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.subtitle,
    required this.isDriver,
  });

  final String name;
  final String subtitle;
  final bool isDriver;

  /// The pencil replaces the old "Personal Information" row on both sides.
  /// For a driver most fields are LGU-issued and read-only, so the sheet
  /// says so rather than offering inputs that would not be honoured.
  void _edit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
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
              Text('Edit profile', style: AppTypography.displaySm),
              const SizedBox(height: AppSpacing.xs),
              Text(
                isDriver
                    ? 'Your name, body number, plate, TODA, and franchise are '
                          'issued by the LGU/TODA office and cannot be changed '
                          'here. Only your photo can be updated.'
                    : 'Update the details shown on your ArangCada account.',
                style: AppTypography.bodySm.copyWith(height: 1.45),
              ),
              const SizedBox(height: AppSpacing.lg),
              ArangButton(
                label: 'Change photo',
                icon: Icons.photo_camera_outlined,
                variant: ArangButtonVariant.ghost,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Photo change is a demo-only action.'),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              ArangButton(
                label: isDriver ? 'Close' : 'Edit account details',
                onPressed: () {
                  Navigator.pop(sheetContext);
                  if (isDriver) return;
                  context.push('/profile/edit');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ArangAvatar(
          name: name,
          size: 52,
          background: isDriver ? AppColors.primary : AppColors.primaryFill,
          foreground: isDriver ? Colors.white : AppColors.primaryText,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption,
              ),
              if (isDriver) ...[
                const SizedBox(height: 6),
                const ArangBadge('Verified', tone: ArangBadgeTone.green),
              ],
            ],
          ),
        ),
        ArangIconButton(
          icon: Icons.edit_outlined,
          tooltip: 'Edit profile',
          onPressed: () => _edit(context),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.label.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.danger = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AppRowIcon(icon, danger: danger),
      title: Text(
        label,
        style: danger ? const TextStyle(color: AppColors.danger) : null,
      ),
      trailing: showChevron || trailing != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailing != null) ...[
                  trailing!,
                  const SizedBox(width: AppSpacing.xs),
                ],
                if (showChevron) const Icon(Icons.chevron_right),
              ],
            )
          : null,
      onTap: onTap,
    );
  }
}
