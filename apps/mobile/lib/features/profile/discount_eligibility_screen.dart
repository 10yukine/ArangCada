import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';

/// Where a fare concession is claimed.
///
/// A discount is not a preference, so it is not a picker at booking time. It
/// is claimed against an ID and applies only once verified; until then the
/// commuter is billed Regular.
///
/// The intended production check is server-side: OCR reads the submitted ID,
/// the extracted name is matched against the account holder, and an
/// administrator resolves anything ambiguous. **None of that exists yet.**
/// Nothing on this screen may claim an ID was read, matched, or approved by a
/// machine — submitting only records the commuter's intent to claim.
class DiscountEligibilityScreen extends ConsumerWidget {
  const DiscountEligibilityScreen({super.key});

  static const _claimable = <UserFareClass>[
    UserFareClass.student,
    UserFareClass.seniorCitizen,
    UserFareClass.pwd,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final current = state.userFareClass;
        final verified = current != UserFareClass.regular;

        return Scaffold(
          appBar: AppBar(title: const Text('Discount eligibility')),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _StatusCard(fareClass: current, verified: verified),
                const SizedBox(height: AppSpacing.md),
                const ArangSectionHead('Claim a discounted fare'),
                Text(
                  'Discounted fares are set by City Ordinance No. 743, s. 2022 '
                  'for Students, Senior Citizens and Persons with Disability. '
                  'Submit a photo of your ID to claim one.',
                  style: AppTypography.caption.copyWith(height: 1.45),
                ),
                const SizedBox(height: AppSpacing.sm),
                ArangCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final option in _claimable)
                        ArangRow(
                          icon: _iconFor(option),
                          title: option.label,
                          subtitle: current == option
                              ? 'Verified — discounted fares applied'
                              : 'Photo of a valid ID required',
                          iconBackground: current == option
                              ? AppColors.greenFill
                              : AppColors.neutralFill,
                          iconForeground: current == option
                              ? AppColors.green
                              : AppColors.textSecondary,
                          showDivider: option != _claimable.last,
                          trailing: current == option
                              ? const ArangBadge(
                                  'Verified',
                                  tone: ArangBadgeTone.green,
                                )
                              : null,
                          onTap: () => _submit(context, ref, option),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const _HowItWorks(),
                const SizedBox(height: AppSpacing.md),
                if (verified)
                  ArangButton(
                    label: 'Remove discount claim',
                    variant: ArangButtonVariant.dangerGhost,
                    onPressed: () =>
                        state.setUserFareClass(UserFareClass.regular),
                  ),
                const SizedBox(height: AppSpacing.sm),
                ArangButton(
                  label: 'View fare matrix',
                  variant: ArangButtonVariant.ghost,
                  onPressed: () => context.push('/fare-matrix'),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        );
      },
    );
  }

  static IconData _iconFor(UserFareClass value) => switch (value) {
    UserFareClass.student => Icons.school_outlined,
    UserFareClass.seniorCitizen => Icons.elderly_outlined,
    UserFareClass.pwd => Icons.accessible_outlined,
    UserFareClass.regular => Icons.person_outline,
  };

  Future<void> _submit(
    BuildContext context,
    WidgetRef ref,
    UserFareClass option,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${option.label} discount', style: AppTypography.displaySm),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Take a clear photo of your ${_documentFor(option)}. The name on '
              'the ID must match your ArangCada account.',
              style: AppTypography.caption.copyWith(height: 1.45),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.neutralFill,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 30,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text('Photo capture is not wired up yet',
                      style: AppTypography.caption),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Submitting records your claim for review. No ID is read or '
              'checked automatically in this build.',
              style: AppTypography.caption.copyWith(height: 1.45),
            ),
            const SizedBox(height: AppSpacing.md),
            ArangButton(
              label: 'Submit claim',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpacing.xs),
            ArangButton(
              label: 'Cancel',
              variant: ArangButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;
    ref.read(demoStateProvider).setUserFareClass(option);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${option.label} discount applied for this prototype.'),
      ),
    );
  }

  static String _documentFor(UserFareClass value) => switch (value) {
    UserFareClass.student => 'school ID for the current term',
    UserFareClass.seniorCitizen => 'Senior Citizen ID',
    UserFareClass.pwd => 'PWD ID',
    UserFareClass.regular => 'ID',
  };
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.fareClass, required this.verified});

  final UserFareClass fareClass;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return ArangCard(
      color: verified ? AppColors.greenFill : AppColors.surface,
      child: Row(
        children: [
          ArangRowIcon(
            verified ? Icons.verified_outlined : Icons.badge_outlined,
            background: verified ? AppColors.surface : AppColors.neutralFill,
            foreground: verified ? AppColors.green : AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verified
                      ? '${fareClass.label} fare applied'
                      : 'Regular fare applied',
                  style: AppTypography.label,
                ),
                const SizedBox(height: 2),
                Text(
                  verified
                      ? 'Your bookings use the published discounted rates.'
                      : 'You are billed the standard published rate.',
                  style: AppTypography.caption.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return ArangCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How verification will work', style: AppTypography.h2),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Once the backend is connected, a submitted ID is read '
            'automatically and the name on it is matched against your account '
            'name. Anything unclear goes to an ArangCada administrator, and '
            'the discount applies only after it is approved.\n\n'
            'In this prototype no ID is read and nothing is sent anywhere; '
            'submitting simply applies the class locally so the fare can be '
            'demonstrated.',
            style: AppTypography.caption.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
