import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/fare_class_claim.dart';

/// Where a fare concession is claimed.
///
/// A discount is not a preference, so it is not a picker at booking time. It
/// is claimed against an ID and applies only once an administrator approves
/// it; until then the commuter is billed the standard published rate.
///
/// Manual admin review only -- automatic ID reading (OCR matched against the
/// account holder's name) is still future work, unchanged. Submitting here
/// records the commuter's claim and an ID photo for a human to review; see
/// `submit_fare_class_claim`/`review_fare_class_claim`,
/// .pipeline/specs.md Spec 14.
class DiscountEligibilityScreen extends ConsumerStatefulWidget {
  const DiscountEligibilityScreen({super.key});

  @override
  ConsumerState<DiscountEligibilityScreen> createState() =>
      _DiscountEligibilityScreenState();
}

class _DiscountEligibilityScreenState
    extends ConsumerState<DiscountEligibilityScreen> {
  static const _claimable = <FareClassRequestedClass>[
    FareClassRequestedClass.student,
    FareClassRequestedClass.seniorCitizen,
    FareClassRequestedClass.pwd,
  ];

  bool _loading = true;
  String? _loadError;
  FareClassClaim? _claim;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final claim = await ref.read(authRepositoryProvider).latestFareClassClaim();
      if (!mounted) return;
      setState(() {
        _claim = claim;
        _loading = false;
      });
    } on DemoAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final claim = _claim;
    final verified = claim?.status == FareClassClaimStatus.approved;
    final pending = claim?.status == FareClassClaimStatus.pendingReview;

    return Scaffold(
      appBar: AppBar(title: const Text('Discount eligibility')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    if (_loadError != null) ...[
                      ArangCard(
                        color: AppColors.dangerFill,
                        child: Text(
                          _loadError!,
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _StatusCard(claim: claim),
                    const SizedBox(height: AppSpacing.md),
                    if (verified)
                      ArangCard(
                        child: Text(
                          '${claim!.requestedClass.label} is verified. A '
                          'revoked or changed discount is handled by an '
                          'administrator, not from this screen.',
                          style: AppTypography.caption.copyWith(height: 1.45),
                        ),
                      )
                    else if (pending)
                      ArangCard(
                        child: Text(
                          'Your ${claim!.requestedClass.label} claim is '
                          'being reviewed by an administrator. You are '
                          'billed the standard rate until it is decided.',
                          style: AppTypography.caption.copyWith(height: 1.45),
                        ),
                      )
                    else ...[
                      if (claim?.status == FareClassClaimStatus.rejected) ...[
                        ArangCard(
                          color: AppColors.dangerFill,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${claim!.requestedClass.label} claim '
                                'rejected',
                                style: AppTypography.label.copyWith(
                                  color: AppColors.danger,
                                ),
                              ),
                              if (claim.rejectionReason != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  claim.rejectionReason!,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.danger,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                'Submit a fresh, clearer photo to try again.',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.danger,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      const ArangSectionHead('Claim a discounted fare'),
                      Text(
                        'Discounted fares are set by City Ordinance No. 743, '
                        's. 2022 for Students, Senior Citizens and Persons '
                        'with Disability. Submit a photo of your ID for an '
                        'administrator to review.',
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
                                subtitle: 'Photo of a valid ID required',
                                iconBackground: AppColors.neutralFill,
                                iconForeground: AppColors.textSecondary,
                                showDivider: option != _claimable.last,
                                onTap: () => _submit(context, option),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    const _HowItWorks(),
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
      ),
    );
  }

  static IconData _iconFor(FareClassRequestedClass value) => switch (value) {
    FareClassRequestedClass.student => Icons.school_outlined,
    FareClassRequestedClass.seniorCitizen => Icons.elderly_outlined,
    FareClassRequestedClass.pwd => Icons.accessible_outlined,
  };

  static String _documentFor(FareClassRequestedClass value) => switch (value) {
    FareClassRequestedClass.student => 'school ID for the current term',
    FareClassRequestedClass.seniorCitizen => 'Senior Citizen ID',
    FareClassRequestedClass.pwd => 'PWD ID',
  };

  Future<void> _submit(
    BuildContext context,
    FareClassRequestedClass option,
  ) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      isDismissible: true,
      builder: (context) => _ClaimSheet(
        option: option,
        documentLabel: _documentFor(option),
      ),
    );

    if (result != true || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${option.label} claim submitted for review.',
        ),
      ),
    );
    await _refresh();
  }
}

/// The photo-capture-and-submit sheet. Kept as its own StatefulWidget rather
/// than a closure so picking a photo and showing an upload error can update
/// the sheet in place without touching the screen behind it.
class _ClaimSheet extends ConsumerStatefulWidget {
  const _ClaimSheet({required this.option, required this.documentLabel});

  final FareClassRequestedClass option;
  final String documentLabel;

  @override
  ConsumerState<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<_ClaimSheet> {
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _submitting = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = file;
        _photoBytes = bytes;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the camera or gallery.');
    }
  }

  Future<void> _submit() async {
    final photo = _photo;
    final bytes = _photoBytes;
    if (photo == null || bytes == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final auth = ref.read(authRepositoryProvider);
    try {
      final dotIndex = photo.name.lastIndexOf('.');
      final extension = dotIndex == -1
          ? 'jpg'
          : photo.name.substring(dotIndex + 1).toLowerCase();
      final path = await auth.uploadFareClassIdPhoto(
        bytes: bytes,
        fileExtension: extension,
      );
      await auth.submitFareClassClaim(
        requestedClass: widget.option,
        idPhotoPath: path,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DemoAuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.option.label} discount', style: AppTypography.displaySm),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Take a clear photo of your ${widget.documentLabel}. The name '
            'on the ID must match your ArangCada account.',
            style: AppTypography.caption.copyWith(height: 1.45),
          ),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: _submitting ? null : () => _pick(ImageSource.camera),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.neutralFill,
                borderRadius: BorderRadius.circular(AppRadii.card),
                border: Border.all(color: AppColors.borderStrong),
              ),
              child: _photoBytes == null
                  ? const Column(
                      children: [
                        Icon(
                          Icons.photo_camera_outlined,
                          size: 30,
                          color: AppColors.textMuted,
                        ),
                        SizedBox(height: AppSpacing.xs),
                        Text('Tap to take a photo', style: AppTypography.caption),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.card - 2),
                      child: Image.memory(
                        _photoBytes!,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _submitting ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Choose from gallery'),
            ),
          ),
          if (_error != null) ...[
            Text(
              _error!,
              style: AppTypography.bodySm.copyWith(color: AppColors.danger),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            'An administrator reviews your ID manually. No ID is read or '
            'matched automatically in this build.',
            style: AppTypography.caption.copyWith(height: 1.45),
          ),
          const SizedBox(height: AppSpacing.md),
          ArangButton(
            label: _submitting ? 'Submitting...' : 'Submit claim',
            onPressed: (_photoBytes == null || _submitting) ? null : _submit,
          ),
          const SizedBox(height: AppSpacing.xs),
          ArangButton(
            label: 'Cancel',
            variant: ArangButtonVariant.ghost,
            onPressed: _submitting
                ? null
                : () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.claim});

  final FareClassClaim? claim;

  @override
  Widget build(BuildContext context) {
    final verified = claim?.status == FareClassClaimStatus.approved;
    final pending = claim?.status == FareClassClaimStatus.pendingReview;

    final Color color = verified
        ? AppColors.greenFill
        : pending
        ? AppColors.amberFill
        : AppColors.surface;
    final IconData icon = verified
        ? Icons.verified_outlined
        : pending
        ? Icons.hourglass_top_outlined
        : Icons.badge_outlined;
    final Color foreground = verified
        ? AppColors.green
        : pending
        ? AppColors.amberText
        : AppColors.textSecondary;

    final String title = verified
        ? '${claim!.requestedClass.label} fare applied'
        : pending
        ? '${claim!.requestedClass.label} claim pending review'
        : 'Standard fare applied';
    final String subtitle = verified
        ? 'Your bookings use the published discounted rates.'
        : pending
        ? 'You are billed the standard rate while this is reviewed.'
        : 'You are billed the standard published rate.';

    return ArangCard(
      color: color,
      child: Row(
        children: [
          ArangRowIcon(
            icon,
            background: verified || pending ? AppColors.surface : AppColors.neutralFill,
            foreground: foreground,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.label),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.caption.copyWith(height: 1.4)),
              ],
            ),
          ),
          if (verified)
            const ArangBadge('Verified', tone: ArangBadgeTone.green)
          else if (pending)
            const ArangBadge('Pending', tone: ArangBadgeTone.amber),
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
          const Text('How verification works', style: AppTypography.h2),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'A submitted ID photo is reviewed manually by an ArangCada '
            'administrator, not read automatically. Your fare stays at the '
            'standard rate until it is approved, and only then does the '
            'discounted rate apply to your next booking.',
            style: AppTypography.caption.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
