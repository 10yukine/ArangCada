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
/// (see AdminController.visibleFareClassClaims). See .pipeline/specs.md
/// Spec 14.
class ClaimsScreen extends ConsumerStatefulWidget {
  const ClaimsScreen({super.key});
  @override
  ConsumerState<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends ConsumerState<ClaimsScreen> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    final session = auth.value!;
    if (session.role != AdminRole.lgu) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Discount claims',
            subtitle:
                'Student/Senior Citizen/PWD fare-class claims are reviewed city-wide.',
          ),
          SizedBox(height: 22),
          Panel(
            child: EmptyState(
              message:
                  'Discount claims are reviewed by an LGU administrator, not a TODA desk -- commuters have no TODA affiliation to scope this by.',
            ),
          ),
        ],
      );
    }
    final claims = ref.read(adminProvider.notifier).visibleFareClassClaims(session);
    if (claims.isNotEmpty && !claims.any((claim) => claim.id == selected)) {
      selected = claims.first.id;
    }
    final active = claims.where((claim) => claim.id == selected).firstOrNull;
    final list = Panel(
      padding: const EdgeInsets.all(10),
      child: claims.isEmpty
          ? const EmptyState(message: 'No discount claims pending review.')
          : Column(
              children: [
                for (final claim in claims)
                  _ClaimTile(
                    claim: claim,
                    selected: claim.id == selected,
                    onTap: () => setState(() => selected = claim.id),
                  ),
              ],
            ),
    );
    final detail = active == null
        ? const Panel(child: EmptyState(message: 'Select a claim.'))
        : _ClaimDetail(active);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Discount claims',
          subtitle:
              "Student/Senior Citizen/PWD fare-class claims -- manual ID review, not automatic reading. Approving flips the commuter's billing to the discounted rate on their next booking.",
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 950
              ? Column(children: [list, const SizedBox(height: 14), detail])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 380, child: list),
                    const SizedBox(width: 16),
                    Expanded(child: detail),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({
    required this.claim,
    required this.selected,
    required this.onTap,
  });
  final FareClassClaim claim;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected ? AdminColors.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fareClassRequestedClassLabel(claim.requestedClass),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusPill(
                  fareClassClaimStatusLabel(claim.status),
                  tone: fareClassClaimTone(claim.status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              claim.claimantName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              shortTime(claim.created),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ClaimDetail extends ConsumerWidget {
  const _ClaimDetail(this.claim);
  final FareClassClaim claim;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = claim.status == 'pending_review';
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fareClassRequestedClassLabel(claim.requestedClass),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Submitted ${shortTime(claim.created)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(
                fareClassClaimStatusLabel(claim.status),
                tone: fareClassClaimTone(claim.status),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LabelValue('Claimant', claim.claimantName),
          if (claim.rejectionReason != null) ...[
            const SizedBox(height: 18),
            Text('Rejection reason', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(claim.rejectionReason!),
          ],
          const SizedBox(height: 22),
          Text('Submitted ID', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _ClaimPhoto(claim: claim),
          const SizedBox(height: 8),
          Text(
            "Only this administrator's view mints a signed link to this file -- it is never a public URL, and it expires in 5 minutes.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (pending) ...[
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => _decide(context, ref, claim, approve: true),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: () => _decide(context, ref, claim, approve: false),
                  child: const Text('Reject'),
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
              hintText: 'Required -- shown to no one but the audit trail',
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
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            snapshot.data!,
            height: 260,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              height: 80,
              child: Center(child: Text('Could not load the submitted photo.')),
            ),
          ),
        );
      },
    );
  }
}
