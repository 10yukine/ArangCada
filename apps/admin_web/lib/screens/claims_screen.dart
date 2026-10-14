import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_controller.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shared_widgets.dart';

/// Student/Senior Citizen/PWD discount claims, LGU-only: commuters have no
/// TODA affiliation, so there is no per-TODA scope for a claim to belong to
/// (see AdminController.visibleFareClassClaims).
class ClaimsScreen extends ConsumerStatefulWidget {
  const ClaimsScreen({super.key});
  @override
  ConsumerState<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends ConsumerState<ClaimsScreen> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    ref.watch(adminProvider);
    final session = auth.value!;
    if (session.role != AdminRole.lgu) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Discount claims',
            subtitle:
                'Student, senior citizen, and PWD discount claims are reviewed city-wide.',
          ),
          SizedBox(height: 22),
          Panel(
            child: EmptyState(
              message:
                  'Discount claims are reviewed by an LGU administrator, not a TODA desk. Commuters do not belong to a TODA.',
            ),
          ),
        ],
      );
    }
    final claims = ref
        .read(adminProvider.notifier)
        .visibleFareClassClaims(session);
    final pending = [
      for (final claim in claims)
        if (claim.status == 'pending_review') claim,
    ];
    final reviewed = [
      for (final claim in claims)
        if (claim.status != 'pending_review') claim,
    ];
    if (selected != null && !claims.any((claim) => claim.id == selected)) {
      selected = null;
    }
    final active =
        claims.where((claim) => claim.id == selected).firstOrNull ??
        pending.firstOrNull ??
        reviewed.firstOrNull;
    // The queue and the detail sit inside ReviewWorkspace's IntrinsicHeight,
    // where a LayoutBuilder of their own cannot go, so the room they have is
    // worked out here.
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            constraints.maxWidth >= ReviewWorkspace.sideBySideFrom;
        final roomy = constraints.maxWidth >= 520;
        Widget tile(FareClassClaim claim) => _ClaimTile(
          claim: claim,
          // On its own the queue is a list to open, not a selection.
          selected: sideBySide && claim.id == active?.id,
          opens: !sideBySide,
          statusBeside: roomy && !sideBySide,
          onTap: () => setState(() => selected = claim.id),
        );
        final queue = Panel(
          padding: const EdgeInsets.all(10),
          child: claims.isEmpty
              ? const EmptyState(message: 'No discount claims yet.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _QueueLabel('Needs review', pending.length),
                    if (pending.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                        child: Text(
                          'Nothing is waiting for review.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    for (final claim in pending) tile(claim),
                    if (reviewed.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _QueueLabel('Reviewed', reviewed.length),
                      for (final claim in reviewed) tile(claim),
                    ],
                  ],
                ),
        );
        final detail = active == null
            ? const Panel(child: EmptyState(message: 'Select a claim.'))
            : _ClaimDetail(active, statusBeside: roomy);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeading(
              title: 'Discount claims',
              subtitle:
                  'Review student, senior citizen, and PWD identification. Approved discounts apply to the next booking.',
            ),
            const SizedBox(height: 22),
            ReviewWorkspace(
              queue: queue,
              detail: detail,
              showDetail: selected != null,
              onBack: () => setState(() => selected = null),
            ),
          ],
        );
      },
    );
  }
}

class _QueueLabel extends StatelessWidget {
  const _QueueLabel(this.label, this.count);
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
    child: Text(
      '${label.toUpperCase()} · $count',
      semanticsLabel: '$label, $count',
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({
    required this.claim,
    required this.selected,
    required this.opens,
    required this.statusBeside,
    required this.onTap,
  });
  final FareClassClaim claim;
  final bool selected;

  /// Tapping leaves the queue for the claim, so the row points onward.
  final bool opens;
  final bool statusBeside;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? context.adminColor(AdminColors.primaryTint)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: _ClaimSummary(
                claim: claim,
                detail:
                    '${fareClassRequestedClassLabel(claim.requestedClass)} · ${shortTime(claim.created)}',
                statusBeside: statusBeside,
              ),
            ),
            if (opens) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: context.adminColor(AdminColors.muted),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Who is claiming which discount, with the status beside the name when
/// there is room and under it when there is not.
class _ClaimSummary extends StatelessWidget {
  const _ClaimSummary({
    required this.claim,
    required this.detail,
    required this.statusBeside,
    this.nameStyle,
  });
  final FareClassClaim claim;
  final String detail;
  final bool statusBeside;
  final TextStyle? nameStyle;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final status = StatusPill(
      fareClassClaimStatusLabel(claim.status),
      tone: fareClassClaimTone(claim.status),
    );
    return Row(
      crossAxisAlignment: statusBeside
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.adminColor(AdminColors.surface),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            switch (claim.requestedClass) {
              'senior_citizen' => Icons.elderly,
              'pwd' => Icons.accessible,
              _ => Icons.school_outlined,
            },
            size: 20,
            color: context.adminColor(AdminColors.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                claim.claimantName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: nameStyle ?? textTheme.titleMedium,
              ),
              Text(detail, style: textTheme.bodySmall),
              if (!statusBeside) ...[const SizedBox(height: 8), status],
            ],
          ),
        ),
        if (statusBeside) ...[const SizedBox(width: 12), status],
      ],
    );
  }
}

class _ClaimDetail extends ConsumerWidget {
  const _ClaimDetail(this.claim, {required this.statusBeside});
  final FareClassClaim claim;
  final bool statusBeside;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final danger = context.adminColor(AdminColors.danger);
    final pending = claim.status == 'pending_review';
    final rejected = claim.status == 'rejected';
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ClaimSummary(
            claim: claim,
            detail:
                '${fareClassRequestedClassLabel(claim.requestedClass)} discount · Submitted ${shortTime(claim.created)}',
            statusBeside: statusBeside,
            nameStyle: textTheme.headlineSmall,
          ),
          if (claim.rejectionReason != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.adminColor(AdminColors.dangerTint),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rejection reason',
                    style: textTheme.titleSmall?.copyWith(color: danger),
                  ),
                  const SizedBox(height: 4),
                  Text(claim.rejectionReason!),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          Text('Submitted ID', style: textTheme.titleLarge),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.adminColor(AdminColors.surface),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _ClaimPhoto(claim: claim),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: context.adminColor(AdminColors.muted),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Only administrators can open this photo. The link is private and expires in 5 minutes.',
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (pending || rejected) ...[
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (pending) ...[
                  FilledButton.icon(
                    onPressed: () =>
                        _decide(context, ref, claim, approve: true),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _decide(context, ref, claim, approve: false),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                  ),
                ],
                if (rejected)
                  OutlinedButton.icon(
                    onPressed: () => _delete(context, ref),
                    style: OutlinedButton.styleFrom(foregroundColor: danger),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete claim'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    FareClassClaim claim, {
    required bool approve,
  }) async {
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject this claim?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Required. The commuter sees this in the app.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, controller.text.trim().isNotEmpty),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      reason = controller.text.trim();
      controller.dispose();
      if (confirmed != true || !context.mounted) return;
    }
    try {
      await ref
          .read(adminProvider.notifier)
          .reviewFareClassClaim(
            claimId: claim.id,
            approve: approve,
            rejectionReason: reason,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Claim approved.' : 'Claim rejected.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This claim could not be updated.')),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // Taken before the wait: once the claim is gone this panel may be too.
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(adminProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Delete this rejected claim?'),
          content: SizedBox(
            width: 420,
            child: Text(
              'The claim and the submitted ID photo are removed for good. '
              '${claim.claimantName} will no longer see the rejection in '
              'the app, and can still submit a new claim.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete claim'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await controller.deleteFareClassClaim(claim);
      messenger.showSnackBar(const SnackBar(content: Text('Claim deleted.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This claim could not be deleted.')),
      );
    }
  }
}

class _ClaimPhoto extends ConsumerStatefulWidget {
  const _ClaimPhoto({required this.claim});
  final FareClassClaim claim;
  @override
  ConsumerState<_ClaimPhoto> createState() => _ClaimPhotoState();
}

class _ClaimPhotoState extends ConsumerState<_ClaimPhoto> {
  late Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = ref
        .read(adminProvider.notifier)
        .fareClassClaimPhotoUrl(widget.claim.idPhotoPath);
  }

  @override
  void didUpdateWidget(covariant _ClaimPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.claim.idPhotoPath != widget.claim.idPhotoPath) {
      _url = ref
          .read(adminProvider.notifier)
          .fareClassClaimPhotoUrl(widget.claim.idPhotoPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox(
            height: 80,
            child: Center(child: Text('Could not load the submitted photo.')),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            // Tall enough to read the print on an ID card.
            constraints: const BoxConstraints(maxHeight: 420),
            child: Image.network(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const SizedBox(
                height: 80,
                child: Center(
                  child: Text('Could not load the submitted photo.'),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
