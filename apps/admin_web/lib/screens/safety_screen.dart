import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_controller.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shared_widgets.dart';

class SafetyScreen extends ConsumerStatefulWidget {
  const SafetyScreen({super.key});
  @override
  ConsumerState<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends ConsumerState<SafetyScreen> {
  String? selected;
  Timer? reportedChatPoll;
  bool refreshingChats = false;
  String? chatRefreshError;

  @override
  void initState() {
    super.initState();
    final session = auth.value;
    if (session?.role == AdminRole.lgu && (session?.connected ?? false)) {
      reportedChatPoll = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_refreshReportedChats()),
      );
    }
  }

  @override
  void dispose() {
    reportedChatPoll?.cancel();
    super.dispose();
  }

  Future<void> _refreshReportedChats() async {
    final session = auth.value;
    if (!mounted ||
        refreshingChats ||
        session?.role != AdminRole.lgu ||
        !(session?.connected ?? false)) {
      return;
    }
    setState(() => refreshingChats = true);
    try {
      await ref.read(adminProvider.notifier).refreshReportedChats(session!);
      if (mounted && chatRefreshError != null) {
        setState(() => chatRefreshError = null);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => chatRefreshError =
              'Reported conversations could not be refreshed.',
        );
      }
    } finally {
      if (mounted) setState(() => refreshingChats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminProvider);
    final session = auth.value!;
    final reports = ref.read(adminProvider.notifier).visibleReports(session);
    final complaints = ref
        .read(adminProvider.notifier)
        .visibleComplaints(session);
    final reportedChats = ref
        .read(adminProvider.notifier)
        .visibleReportedChats(session);
    if (selected != null && !reports.any((report) => report.id == selected)) {
      selected = null;
    }
    final active =
        reports.where((report) => report.id == selected).firstOrNull ??
        reports.firstOrNull;
    final list = Material(
      type: MaterialType.transparency,
      child: reports.isEmpty
          ? const EmptyState(message: 'No safety reports in this scope.')
          : Column(
              children: [
                for (final report in reports)
                  _ReportTile(
                    report: report,
                    selected: report.id == active?.id,
                    onTap: () => setState(() => selected = report.id),
                  ),
              ],
            ),
    );
    final detail = active == null
        ? const Panel(child: EmptyState(message: 'Select a report.'))
        : _SafetyDetail(active);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeading(
          title: 'Safety reports',
          subtitle:
              'Review, acknowledge, investigate, and document responses without implying emergency-service dispatch.',
        ),
        const SizedBox(height: 22),
        ReviewWorkspace(
          queue: list,
          detail: detail,
          showDetail: selected != null,
          onBack: () => setState(() => selected = null),
        ),
        const SizedBox(height: 18),
        // Its own nav tab felt like too much weight for a non-emergency
        // channel -- owner's call, folded in here as a compact secondary
        // panel instead. Visible to both LGU and TODA (visibleComplaints()
        // already scopes it, same as the reports above) -- unlike reported
        // conversations, which stays LGU-only just below.
        _ComplaintsSection(complaints: complaints),
        if (session.role == AdminRole.lgu) ...[
          const SizedBox(height: 18),
          _ReportedConversationSection(
            reportedChats: reportedChats,
            connected: state.connected,
            refreshing: refreshingChats,
            refreshError: chatRefreshError,
            onRefresh: _refreshReportedChats,
          ),
        ],
      ],
    );
  }
}

class _ReportedConversationSection extends StatelessWidget {
  const _ReportedConversationSection({
    required this.reportedChats,
    required this.connected,
    required this.refreshing,
    required this.refreshError,
    required this.onRefresh,
  });

  final List<ReportedTripChat> reportedChats;
  final bool connected;
  final bool refreshing;
  final String? refreshError;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 10,
          children: [
            Text(
              'Reported conversations · LGU only',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            OutlinedButton.icon(
              onPressed: connected && !refreshing ? onRefresh : null,
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(refreshing ? 'Refreshing…' : 'Refresh reports'),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          'Only conversations explicitly reported and shared with participant consent are visible. Ordinary trip messages remain private.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (refreshError != null) ...[
          const SizedBox(height: 9),
          Text(
            refreshError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.adminColor(AdminColors.danger),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (reportedChats.isEmpty)
          const EmptyState(message: 'No consented conversation reports.')
        else
          for (final report in reportedChats)
            _ReportedConversationCard(report: report),
      ],
    ),
  );
}

class _ReportedConversationCard extends StatelessWidget {
  const _ReportedConversationCard({required this.report});

  final ReportedTripChat report;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      border: Border.all(color: context.adminColor(AdminColors.border)),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(report.reason, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        Text(
          'Reported by ${report.reporterName} · ${report.toda} · consent confirmed ${shortTime(report.consentedAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (report.messages.isEmpty)
          const Text('The reported conversation contained no saved messages.')
        else
          for (final message in report.messages)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.adminColor(AdminColors.surface),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${message.senderRole} · ${message.senderName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(message.body),
                  if (message.createdAt != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      shortTime(message.createdAt!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
      ],
    ),
  );
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.report,
    required this.selected,
    required this.onTap,
  });
  final SafetyReport report;
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
          color: selected
              ? context.adminColor(AdminColors.primaryTint)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (report.priority == 'critical') ...[
                  Icon(
                    Icons.priority_high,
                    size: 18,
                    color: context.adminColor(AdminColors.danger),
                  ),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    safetyReportLabel(report.id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  reportStatusLabel(report.status),
                  tone: reportTone(report.status),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(report.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(
              '${report.toda} · ${shortTime(report.created)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SafetyDetail extends ConsumerWidget {
  const _SafetyDetail(this.report);
  final SafetyReport report;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
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
                    safetyReportLabel(report.id),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${report.toda} · submitted ${shortTime(report.created)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            StatusPill(
              reportStatusLabel(report.status),
              tone: reportTone(report.status),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(report.summary, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 18),
        Wrap(
          spacing: 22,
          runSpacing: 12,
          children: [
            LabelValue('Rider', report.rider),
            LabelValue('Driver', report.driver),
            LabelValue('TODA', report.toda),
            if (report.priority == 'critical')
              const LabelValue('Priority', 'Critical SOS'),
            if (report.latitude != null && report.longitude != null)
              LabelValue(
                'Reported location',
                '${report.latitude!.toStringAsFixed(5)}, ${report.longitude!.toStringAsFixed(5)}',
              ),
          ],
        ),
        const SizedBox(height: 22),
        Text('Response log', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final note in report.notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 19,
                  color: context.adminColor(AdminColors.success),
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(note)),
              ],
            ),
          ),
        const SizedBox(height: 18),
        if (auth.value?.role != AdminRole.lgu)
          const StatusPill('Read-only · LGU manages safety report status')
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton(
                onPressed: report.status == ReportStatus.resolved
                    ? null
                    : () => _updateReport(context, ref, ReportStatus.resolved),
                child: const Text('Mark resolved'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _updateReport(context, ref, ReportStatus.acknowledged),
                child: const Text('Acknowledge'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _updateReport(context, ref, ReportStatus.investigating),
                child: const Text('Investigate'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _updateReport(context, ref, ReportStatus.escalated),
                child: const Text('Escalate'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _updateReport(context, ref, ReportStatus.dismissed),
                child: const Text('Dismiss'),
              ),
            ],
          ),
      ],
    ),
  );

  Future<void> _updateReport(
    BuildContext context,
    WidgetRef ref,
    ReportStatus status,
  ) async {
    final note = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set status to ${reportStatusLabel(status)}?'),
        content: TextField(
          controller: note,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Response note',
            hintText: 'Add context for the audit trail',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      try {
        await ref
            .read(adminProvider.notifier)
            .transitionReport(report.id, status, note.text);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${report.id} is now ${reportStatusLabel(status).toLowerCase()}.',
            ),
          ),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This safety report could not be updated.'),
          ),
        );
      }
    }
    note.dispose();
  }
}

// Folded into Safety reports as a compact secondary panel (owner's call,
// Spec 19 follow-up) -- see _ComplaintsSection below. _ComplaintTile and
// _ComplaintDetail stay, reused there unchanged.
class _ComplaintsSection extends StatelessWidget {
  const _ComplaintsSection({required this.complaints});
  final List<Complaint> complaints;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Complaints', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'Non-emergency issues either party filed about the other -- '
          'driver lateness, disputed fares, and similar. Not for danger; '
          'see the reports above for that.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (complaints.isEmpty)
          const EmptyState(message: 'No complaints in this scope.')
        else
          for (final complaint in complaints)
            _ComplaintTile(
              complaint: complaint,
              selected: false,
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SingleChildScrollView(
                      child: _ComplaintDetail(complaint),
                    ),
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}

class _ComplaintTile extends StatelessWidget {
  const _ComplaintTile({
    required this.complaint,
    required this.selected,
    required this.onTap,
  });
  final Complaint complaint;
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
          color: selected
              ? context.adminColor(AdminColors.primaryTint)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    complaintCategoryLabel(complaint.category),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusPill(
                  reportStatusLabel(complaint.status),
                  tone: reportTone(complaint.status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${complaint.complainantName} about ${complaint.respondentName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              '${complaint.toda} · ${shortTime(complaint.created)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ComplaintDetail extends ConsumerWidget {
  const _ComplaintDetail(this.complaint);
  final Complaint complaint;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
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
                    complaintCategoryLabel(complaint.category),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${complaint.toda} · submitted ${shortTime(complaint.created)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            StatusPill(
              reportStatusLabel(complaint.status),
              tone: reportTone(complaint.status),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          complaint.description,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 22,
          runSpacing: 12,
          children: [
            LabelValue(
              complaint.complainantRole == 'driver' ? 'Driver' : 'Commuter',
              complaint.complainantName,
            ),
            LabelValue(
              complaint.complainantRole == 'driver' ? 'Commuter' : 'Driver',
              complaint.respondentName,
            ),
            LabelValue('TODA', complaint.toda),
          ],
        ),
        const SizedBox(height: 22),
        Text('Response log', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final note in complaint.notes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 19,
                  color: context.adminColor(AdminColors.success),
                ),
                const SizedBox(width: 9),
                Expanded(child: Text(note)),
              ],
            ),
          ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: complaint.status == ReportStatus.resolved
                  ? null
                  : () => _updateComplaint(context, ref, ReportStatus.resolved),
              child: const Text('Mark resolved'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _updateComplaint(context, ref, ReportStatus.acknowledged),
              child: const Text('Acknowledge'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _updateComplaint(context, ref, ReportStatus.investigating),
              child: const Text('Investigate'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _updateComplaint(context, ref, ReportStatus.dismissed),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _updateComplaint(
    BuildContext context,
    WidgetRef ref,
    ReportStatus status,
  ) async {
    final note = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set status to ${reportStatusLabel(status)}?'),
        content: TextField(
          controller: note,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Response note',
            hintText: 'Add context for the audit trail',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      try {
        await ref
            .read(adminProvider.notifier)
            .transitionComplaint(complaint.id, status, note.text);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Complaint is now ${reportStatusLabel(status).toLowerCase()}.',
            ),
          ),
        );
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This complaint could not be updated.')),
        );
      }
    }
    note.dispose();
  }
}
