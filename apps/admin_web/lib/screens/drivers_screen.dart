import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../admin_controller.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shared_widgets.dart';

class DriversScreen extends ConsumerWidget {
  const DriversScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final controller = ref.read(adminProvider.notifier);
    final drivers = controller.visibleDrivers(auth.value!);
    const statuses = [
      'All statuses',
      'Needs review',
      'Enrolled',
      'Documents submitted',
      'Under review',
      'Approved',
      'Rejected',
      'Suspended',
      'Expired',
    ];
    final todas = [
      'All TODAs',
      ...{
        for (final driver in controller.scopedDrivers(auth.value!)) driver.toda,
        for (final boundary in state.boundaries)
          if (auth.value!.role == AdminRole.lgu ||
              boundary.name == auth.value!.toda)
            boundary.name,
      },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: 'Driver verification',
          subtitle:
              'Enroll drivers, review submitted records, and preserve an auditable lifecycle.',
          // LGU-initiated enrollment -- the LGU inputs the
          // driver's email; the flow itself decides whether that email
          // gets an invite or promotes an existing account. Replaces the
          // old passive "Applications submitted in the driver app" pill,
          // which encoded the wrong model: nothing in this app has ever
          // let a driver self-apply.
          action: auth.value!.role == AdminRole.lgu
              ? FilledButton.icon(
                  onPressed: () => _showDriverEnrollment(
                    context,
                    ref,
                    state.todaZoneOptions,
                  ),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Enroll driver'),
                )
              : const StatusPill(
                  'Enrollment is managed by an LGU administrator',
                ),
        ),
        const SizedBox(height: 22),
        if (state.connected && auth.value!.role == AdminRole.lgu) ...[
          const _PendingDriverInvitesPanel(),
          const SizedBox(height: 18),
        ],
        Panel(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final fields = [
                    SizedBox(
                      width: constraints.maxWidth < 640
                          ? constraints.maxWidth
                          : 280,
                      child: TextField(
                        onChanged: controller.setDriverQuery,
                        decoration: const InputDecoration(
                          labelText: 'Search drivers',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth < 640
                          ? constraints.maxWidth
                          : 210,
                      child: DropdownButtonFormField<String>(
                        initialValue: state.driverStatus,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          for (final item in statuses)
                            DropdownMenuItem(
                              value: item,
                              child: Text(
                                item,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            controller.setDriverStatus(value!),
                      ),
                    ),
                    if (auth.value!.role == AdminRole.lgu)
                      SizedBox(
                        width: constraints.maxWidth < 640
                            ? constraints.maxWidth
                            : 190,
                        child: DropdownButtonFormField<String>(
                          initialValue: state.driverToda,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'TODA'),
                          items: [
                            for (final item in todas)
                              DropdownMenuItem(
                                value: item,
                                child: Text(
                                  item,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              controller.setDriverToda(value!),
                        ),
                      ),
                  ];
                  if (constraints.maxWidth >= 640) {
                    return Wrap(spacing: 12, runSpacing: 12, children: fields);
                  }
                  // Phones: search stays visible, the dropdowns fold away
                  // behind a Filters button (they took ~200 px above the
                  // list). A badge counts the filters in effect.
                  return _PhoneDriverFilters(
                    search: fields.first,
                    filters: fields.sublist(1),
                    active:
                        (state.driverStatus != 'All statuses' ? 1 : 0) +
                        (state.driverToda != 'All TODAs' ? 1 : 0),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              if (drivers.isEmpty)
                const EmptyState(message: 'No drivers match these filters.')
              else
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth < 640
                      ? Column(
                          children: [
                            for (final driver in drivers) ...[
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                title: Text(driver.name),
                                subtitle: Text(
                                  '${driver.toda} · ${driver.plate}\n${driverStatusLabel(driver.status)} · ${driver.documents}/4 documents',
                                ),
                                isThreeLine: true,
                                trailing: TextButton(
                                  onPressed: () =>
                                      _showDriver(context, ref, driver),
                                  child: const Text('Manage'),
                                ),
                                onTap: () => _showDriver(context, ref, driver),
                              ),
                              const Divider(height: 1),
                            ],
                          ],
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: DataTable(
                              columnSpacing: 28,
                              dataRowMinHeight: state.compactDensity ? 48 : 60,
                              dataRowMaxHeight: state.compactDensity ? 48 : 60,
                              columns: const [
                                DataColumn(label: Text('Driver')),
                                DataColumn(label: Text('TODA')),
                                DataColumn(label: Text('Plate')),
                                DataColumn(label: Text('Documents')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Action')),
                              ],
                              rows: [
                                for (final driver in drivers)
                                  DataRow(
                                    cells: [
                                      DataCell(
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              driver.name,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                            ),
                                            Text(
                                              driver.enrollmentCode,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      DataCell(Text(driver.toda)),
                                      DataCell(Text(driver.plate)),
                                      DataCell(Text('${driver.documents}/4')),
                                      DataCell(
                                        StatusPill(
                                          driverStatusLabel(driver.status),
                                          tone: driverTone(driver.status),
                                        ),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            OutlinedButton(
                                              onPressed: () => _showDriver(
                                                context,
                                                ref,
                                                driver,
                                              ),
                                              child: const Text('Manage'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('How driver verification works'),
          childrenPadding: EdgeInsets.only(bottom: 16),
          children: [
            Text(
              'Enrolled → Documents submitted → Under review → Approved. Suspended and expired records require follow-up before returning to service.',
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Driver enrollment by email -- LGU-initiated, mirrors the admin
// invite system closely.
// =============================================================================

class _PendingDriverInvitesPanel extends ConsumerStatefulWidget {
  const _PendingDriverInvitesPanel();
  @override
  ConsumerState<_PendingDriverInvitesPanel> createState() =>
      _PendingDriverInvitesPanelState();
}

class _PendingDriverInvitesPanelState
    extends ConsumerState<_PendingDriverInvitesPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    final session = auth.value;
    if (!mounted ||
        session == null ||
        session.role != AdminRole.lgu ||
        !session.connected) {
      return;
    }
    try {
      await ref.read(adminProvider.notifier).refreshDriverInvites();
    } catch (_) {
      // Stays empty -- nothing more specific to show here, same swallow-
      // and-retry-next-visit shape SafetyScreen's own poll already uses.
    }
  }

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(adminProvider).driverInvites;
    if (invites.isEmpty) return const SizedBox.shrink();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pending driver invites',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Not yet accepted. Inviting the same email again supersedes the link below.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          for (final invite in invites)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invite.email,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${invite.toda ?? 'Unknown TODA'} -- sent ${shortTime(invite.created)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _revoke(context, ref, invite),
                    child: const Text('Revoke'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    DriverInvite invite,
  ) async {
    try {
      await ref.read(adminProvider.notifier).revokeDriverInvite(invite.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invite to ${invite.email} revoked.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This invite could not be revoked.')),
      );
    }
  }
}

Future<void> _showDriverEnrollment(
  BuildContext context,
  WidgetRef ref,
  List<(String id, String name)> todaZoneOptions,
) async {
  final enrolled = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        _DriverEnrollmentDialog(todaZoneOptions: todaZoneOptions),
  );
  if (enrolled == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Driver enrolled.')));
  }
}

class _DriverEnrollmentDialog extends ConsumerStatefulWidget {
  const _DriverEnrollmentDialog({required this.todaZoneOptions});
  final List<(String id, String name)> todaZoneOptions;

  @override
  ConsumerState<_DriverEnrollmentDialog> createState() =>
      _DriverEnrollmentDialogState();
}

class _DriverEnrollmentDialogState
    extends ConsumerState<_DriverEnrollmentDialog> {
  final _emailFormKey = GlobalKey<FormState>();
  final _detailFormKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _confirmEmail = TextEditingController();
  final _bodyNumber = TextEditingController();
  bool _checking = false;
  bool _submitting = false;
  // null = step 1 (email not checked yet). Non-null = step 2, and whether
  // it is empty decides which of the two branches step 2 shows.
  List<DriverCandidate>? _candidates;
  String? _todaZoneId;

  @override
  void initState() {
    super.initState();
    if (widget.todaZoneOptions.isNotEmpty) {
      _todaZoneId = widget.todaZoneOptions.first.$1;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _confirmEmail.dispose();
    _bodyNumber.dispose();
    super.dispose();
  }

  Future<void> _checkEmail() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _checking = true);
    try {
      final candidates = await ref
          .read(adminProvider.notifier)
          .previewDriverCandidate(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _checking = false;
        _candidates = candidates;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError ? error.message : 'Could not check this email.',
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_detailFormKey.currentState!.validate()) return;
    final todaZoneId = _todaZoneId;
    if (todaZoneId == null) return;
    final found = _candidates!.isNotEmpty;
    setState(() => _submitting = true);
    try {
      if (found) {
        await ref
            .read(adminProvider.notifier)
            .promoteCommuterToDriver(
              email: _email.text.trim(),
              confirmValue: _confirmEmail.text.trim(),
              todaZoneId: todaZoneId,
              bodyNumber: _bodyNumber.text.trim().isEmpty
                  ? null
                  : _bodyNumber.text.trim(),
            );
      } else {
        await ref
            .read(adminProvider.notifier)
            .sendDriverInvite(
              email: _email.text.trim(),
              todaZoneId: todaZoneId,
              bodyNumber: _bodyNumber.text.trim().isEmpty
                  ? null
                  : _bodyNumber.text.trim(),
            );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : found
                ? 'This driver could not be enrolled.'
                : 'The invite could not be sent.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_candidates == null) {
      return AlertDialog(
        title: const Text('Enroll a driver'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _emailFormKey,
            child: TextFormField(
              errorBuilder: adminFieldError,
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: "Driver's email address",
              ),
              validator: (value) => (value?.trim().contains('@') ?? false)
                  ? null
                  : 'Enter a valid email address.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _checking ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _checking ? null : _checkEmail,
            child: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
        ],
      );
    }

    final found = _candidates!.isNotEmpty;
    return AlertDialog(
      title: Text(
        found ? 'This email already has an account' : 'Enroll a new driver',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _detailFormKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (found) ...[
                  for (final candidate in _candidates!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${candidate.maskedName} -- ${candidate.accountRole}, '
                        'joined ${candidate.joinedOn}, ${candidate.tripCount} trip(s)',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  Text(
                    'Re-type the email to confirm this is the right account -- '
                    'promoting the wrong one cannot be undone from here.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    errorBuilder: adminFieldError,
                    controller: _confirmEmail,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Confirm email',
                    ),
                    validator: (value) =>
                        value?.trim().toLowerCase() ==
                            _email.text.trim().toLowerCase()
                        ? null
                        : 'Must match the email above exactly.',
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Text(
                    'No account exists for ${_email.text.trim()} yet -- an invite '
                    'will be emailed to create one.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _todaZoneId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'TODA'),
                  items: [
                    for (final zone in widget.todaZoneOptions)
                      DropdownMenuItem(value: zone.$1, child: Text(zone.$2)),
                  ],
                  onChanged: (value) => setState(() => _todaZoneId = value),
                  validator: (value) => value == null ? 'Select a TODA.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  errorBuilder: adminFieldError,
                  controller: _bodyNumber,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Body number (optional)',
                    hintText: 'Matched against the TODA roster if given',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => setState(() => _candidates = null),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(found ? 'Promote to driver' : 'Send invite'),
        ),
      ],
    );
  }
}

Future<void> _showDriver(
  BuildContext screenContext,
  WidgetRef ref,
  Driver initialDriver,
) async {
  await showDialog<void>(
    context: screenContext,
    builder: (dialogContext) => Consumer(
      builder: (consumerContext, ref, _) {
        final state = ref.watch(adminProvider);
        final driver = state.drivers.firstWhere(
          (d) => d.id == initialDriver.id,
          orElse: () => initialDriver,
        );
        final theme = Theme.of(consumerContext);
        final expiry = driver.licenseExpiresOn == null
            ? 'Not recorded'
            : '${driver.licenseExpiresOn!.year}-'
                  '${driver.licenseExpiresOn!.month.toString().padLeft(2, '0')}-'
                  '${driver.licenseExpiresOn!.day.toString().padLeft(2, '0')}';
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Driver record · ${driver.enrollmentCode}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(
                driverStatusLabel(driver.status),
                tone: driverTone(driver.status),
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: consumerContext.adminColor(AdminColors.background),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final column = (box.maxWidth - 16) / 2;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 10,
                          children: [
                            LabelValue(
                              'Enrollment',
                              driver.enrollmentCode,
                              width: column,
                            ),
                            LabelValue('TODA', driver.toda, width: column),
                            LabelValue('Phone', driver.phone, width: column),
                            LabelValue('Plate', driver.plate, width: column),
                            LabelValue(
                              'Body number',
                              driver.bodyNumber ?? 'Not recorded',
                              width: column,
                            ),
                            LabelValue('License expiry', expiry, width: column),
                            OutlinedButton.icon(
                              onPressed: () => _showManageDriverRecord(
                                screenContext,
                                ref,
                                driver,
                                ref.read(adminProvider).todaZoneOptions,
                                canReassign: auth.value?.role == AdminRole.lgu,
                              ),
                              icon: const Icon(
                                Icons.manage_accounts_outlined,
                                size: 16,
                              ),
                              label: const Text('Manage details'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Submitted documents',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${driver.approvedDocuments} of 4 required approved',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: consumerContext.adminColor(AdminColors.border),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        for (final item in const [
                          ('drivers_license', 'Driver’s license'),
                          ('mtop_franchise', 'MTOP / franchise permit'),
                          ('toda_membership', 'TODA membership endorsement'),
                          ('or_cr', 'Vehicle OR / CR registration'),
                          (
                            'barangay_clearance',
                            'Barangay clearance (optional)',
                          ),
                          ('vehicle_photo', 'Vehicle photo (optional)'),
                        ].indexed) ...[
                          if (item.$1 > 0) const Divider(height: 1),
                          _DriverDocumentRow(
                            driver: driver,
                            documentType: item.$2.$1,
                            label: item.$2.$2,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Uploaded on the driver’s behalf after their paper submission is checked in person. Only this administrator’s view mints a signed link to a file -- never a public URL, and it expires in 5 minutes.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed:
                            driver.approvedDocuments < 4 ||
                                driver.status == DriverStatus.approved ||
                                driver.status == DriverStatus.suspended
                            ? null
                            : () => _applyDriverAction(
                                screenContext,
                                ref,
                                driver,
                                DriverStatus.approved,
                                'Required driver documents reviewed and accepted',
                              ),
                        child: const Text('Approve'),
                      ),
                      if (auth.value?.role == AdminRole.lgu &&
                          driver.status == DriverStatus.suspended)
                        OutlinedButton(
                          onPressed: () => _applyDriverAction(
                            screenContext,
                            ref,
                            driver,
                            DriverStatus.approved,
                            'Reinstated after administrator review',
                          ),
                          child: const Text('Reinstate'),
                        )
                      else if (auth.value?.role == AdminRole.lgu)
                        OutlinedButton(
                          onPressed: () => _confirmDriverAction(
                            screenContext,
                            ref,
                            driver,
                            DriverStatus.suspended,
                          ),
                          child: const Text('Suspend'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

Future<void> _showManageDriverRecord(
  BuildContext context,
  WidgetRef ref,
  Driver driver,
  List<(String id, String name)> zones, {
  required bool canReassign,
}) async {
  final updated = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _ManageDriverRecordDialog(
      driver: driver,
      zones: zones,
      canReassign: canReassign,
    ),
  );
  if (updated == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Driver record updated.')));
  }
}

class _ManageDriverRecordDialog extends ConsumerStatefulWidget {
  const _ManageDriverRecordDialog({
    required this.driver,
    required this.zones,
    required this.canReassign,
  });

  final Driver driver;
  final List<(String id, String name)> zones;
  final bool canReassign;

  @override
  ConsumerState<_ManageDriverRecordDialog> createState() =>
      _ManageDriverRecordDialogState();
}

class _ManageDriverRecordDialogState
    extends ConsumerState<_ManageDriverRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;
  late final TextEditingController _plate;
  late final TextEditingController _bodyNumber;
  String? _zoneId;
  DateTime? _licenseExpiresOn;
  bool _clearExpiry = false;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final driver = widget.driver;
    _firstName = TextEditingController(text: driver.effectiveFirstName);
    _lastName = TextEditingController(text: driver.effectiveLastName);
    _phone = TextEditingController(text: driver.phone);
    _plate = TextEditingController(
      text: driver.plate == 'Not recorded' ? '' : driver.plate,
    );
    _bodyNumber = TextEditingController(text: driver.bodyNumber ?? '');
    _zoneId = widget.zones.any((zone) => zone.$1 == driver.todaZoneId)
        ? driver.todaZoneId
        : null;
    _licenseExpiresOn = driver.licenseExpiresOn;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _plate.dispose();
    _bodyNumber.dispose();
    super.dispose();
  }

  Future<void> _pickLicenseExpiry() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _licenseExpiresOn ?? now,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      helpText: 'Select license expiry date',
    );
    if (selected != null && mounted) {
      setState(() {
        _licenseExpiresOn = selected;
        _clearExpiry = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(adminProvider.notifier)
          .updateDriverRecord(
            driverId: widget.driver.id,
            firstName: _firstName.text,
            lastName: _lastName.text,
            plateNumber: _plate.text,
            bodyNumber: _bodyNumber.text,
            todaZoneId: _zoneId,
            licenseExpiresOn: _licenseExpiresOn,
            clearLicenseExpiry: _clearExpiry,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.toString().replaceFirst(
          RegExp(r'^Exception:s*'),
          '',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiryLabel = _licenseExpiresOn == null
        ? 'Not recorded'
        : '${_licenseExpiresOn!.year.toString().padLeft(4, '0')}-'
              '${_licenseExpiresOn!.month.toString().padLeft(2, '0')}-'
              '${_licenseExpiresOn!.day.toString().padLeft(2, '0')}';
    return AlertDialog(
      title: const Text('Manage driver details'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          errorBuilder: adminFieldError,
                          controller: _firstName,
                          decoration: const InputDecoration(
                            labelText: 'First name',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter the driver’s first name.'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          errorBuilder: adminFieldError,
                          controller: _lastName,
                          decoration: const InputDecoration(
                            labelText: 'Last name',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter the driver’s last name.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    errorBuilder: adminFieldError,
                    controller: _phone,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      helperText:
                          'The driver must verify a phone change by OTP from their account.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          errorBuilder: adminFieldError,
                          controller: _plate,
                          decoration: const InputDecoration(
                            labelText: 'Plate number',
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          errorBuilder: adminFieldError,
                          controller: _bodyNumber,
                          decoration: const InputDecoration(
                            labelText: 'Body number',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (widget.canReassign && widget.zones.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: _zoneId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'TODA'),
                      items: [
                        for (final zone in widget.zones)
                          DropdownMenuItem(
                            value: zone.$1,
                            child: Text(zone.$2),
                          ),
                      ],
                      onChanged: (value) => setState(() => _zoneId = value),
                      validator: (value) =>
                          value == null ? 'Choose a TODA.' : null,
                    )
                  else
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'TODA'),
                      child: Text(widget.driver.toda),
                    ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'License expiry',
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(expiryLabel)),
                        TextButton(
                          onPressed: _pickLicenseExpiry,
                          child: const Text('Choose date'),
                        ),
                        if (_licenseExpiresOn != null)
                          IconButton(
                            tooltip: 'Clear license expiry',
                            onPressed: () => setState(() {
                              _licenseExpiresOn = null;
                              _clearExpiry = true;
                            }),
                            icon: const Icon(Icons.clear),
                          ),
                      ],
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save changes'),
        ),
      ],
    );
  }
}

class _DriverDocumentRow extends ConsumerStatefulWidget {
  const _DriverDocumentRow({
    required this.driver,
    required this.documentType,
    required this.label,
  });

  final Driver driver;
  final String documentType;
  final String label;

  @override
  ConsumerState<_DriverDocumentRow> createState() => _DriverDocumentRowState();
}

class _DriverDocumentRowState extends ConsumerState<_DriverDocumentRow> {
  bool _busy = false;

  String? get _status => widget.driver.documentStatuses[widget.documentType];

  Future<void> _upload() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      final dotIndex = picked.name.lastIndexOf('.');
      final extension = dotIndex == -1
          ? 'jpg'
          : picked.name.substring(dotIndex + 1).toLowerCase();
      await ref
          .read(adminProvider.notifier)
          .uploadDriverDocument(
            driverId: widget.driver.id,
            documentType: widget.documentType,
            bytes: bytes,
            fileExtension: extension,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Document uploaded.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not upload that document.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review({required bool approve}) async {
    final documentId = widget.driver.documentIds[widget.documentType];
    if (documentId == null) return;
    String? reason;
    if (!approve) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject this document?'),
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
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(adminProvider.notifier)
          .reviewDriverDocument(
            documentId: documentId,
            approve: approve,
            rejectionReason: reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Document approved.' : 'Document rejected.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This document could not be updated.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final path = widget.driver.documentPaths[widget.documentType];
    final approved = status == 'approved';
    final rejected = status == 'rejected';
    final description = switch (status) {
      'approved' => 'Approved',
      'pending' => 'Pending review',
      'rejected' => 'Rejected',
      _ => 'Missing',
    };
    final tone = switch (status) {
      'approved' => StatusTone.success,
      'pending' => StatusTone.warning,
      'rejected' => StatusTone.danger,
      _ => StatusTone.neutral,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final icon = Icon(
                approved
                    ? Icons.check_circle
                    : rejected
                    ? Icons.cancel
                    : Icons.radio_button_unchecked,
                size: 20,
                color: approved
                    ? context.adminColor(AdminColors.success)
                    : rejected
                    ? context.adminColor(AdminColors.danger)
                    : context.adminColor(AdminColors.muted),
              );
              final label = Text(
                widget.label,
                style: Theme.of(context).textTheme.titleSmall,
              );
              final controls = [
                StatusPill(description, tone: tone),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: _busy ? null : _upload,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(40, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.upload_file, size: 17),
                  label: Text(path == null ? 'Upload' : 'Replace'),
                ),
              ];
              // Narrow (phone): status and upload go under the name, which
              // otherwise wrapped a letter per line.
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        icon,
                        const SizedBox(width: 10),
                        Expanded(child: label),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 30, top: 4),
                      child: Row(children: controls),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Expanded(child: label),
                  ...controls,
                ],
              );
            },
          ),
          if (path != null)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  _DriverDocumentPhoto(path: path),
                  if (status == 'pending') ...[
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _busy ? null : () => _review(approve: true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(40, 38),
                      ),
                      child: const Text('Approve'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _review(approve: false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(40, 38),
                      ),
                      child: const Text('Reject'),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DriverDocumentPhoto extends ConsumerStatefulWidget {
  const _DriverDocumentPhoto({required this.path});
  final String path;
  @override
  ConsumerState<_DriverDocumentPhoto> createState() =>
      _DriverDocumentPhotoState();
}

class _DriverDocumentPhotoState extends ConsumerState<_DriverDocumentPhoto> {
  late Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = ref.read(adminProvider.notifier).driverDocumentPhotoUrl(widget.path);
  }

  @override
  void didUpdateWidget(covariant _DriverDocumentPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _url = ref
          .read(adminProvider.notifier)
          .driverDocumentPhotoUrl(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 96,
            width: 96,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox(
            height: 40,
            child: Center(child: Text('Could not load this document.')),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            height: 96,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
        );
      },
    );
  }
}

Future<void> _applyDriverAction(
  BuildContext dialogContext,
  WidgetRef ref,
  Driver driver,
  DriverStatus status,
  String reason,
) async {
  try {
    await ref
        .read(adminProvider.notifier)
        .updateDriver(driver.id, status, reason);
    if (dialogContext.mounted) Navigator.pop(dialogContext);
  } catch (_) {
    if (!dialogContext.mounted) return;
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      const SnackBar(
        content: Text(
          'The requested driver action was not accepted by the server.',
        ),
      ),
    );
  }
}

Future<void> _confirmDriverAction(
  BuildContext dialogContext,
  WidgetRef ref,
  Driver driver,
  DriverStatus status,
) async {
  final reason = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: dialogContext,
    builder: (context) => AlertDialog(
      title: Text('${driverStatusLabel(status)} ${driver.name}?'),
      content: TextField(
        controller: reason,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Reason',
          hintText: 'Required for the audit trail',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, reason.text.trim().isNotEmpty),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (confirmed == true && dialogContext.mounted) {
    await _applyDriverAction(dialogContext, ref, driver, status, reason.text);
  }
  reason.dispose();
}

class _PhoneDriverFilters extends StatefulWidget {
  const _PhoneDriverFilters({
    required this.search,
    required this.filters,
    required this.active,
  });

  final Widget search;
  final List<Widget> filters;
  final int active;

  @override
  State<_PhoneDriverFilters> createState() => _PhoneDriverFiltersState();
}

class _PhoneDriverFiltersState extends State<_PhoneDriverFilters> {
  // Open when arriving with a filter already set (e.g. from the dashboard's
  // "Driver applications"), so the narrowed list is never a surprise.
  late bool _open = widget.active > 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: widget.search),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: widget.active > 0 && !_open,
            label: Text('${widget.active}'),
            child: IconButton.filledTonal(
              tooltip: _open ? 'Hide filters' : 'Show filters',
              isSelected: _open,
              onPressed: () => setState(() => _open = !_open),
              icon: const Icon(Icons.tune),
            ),
          ),
        ],
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _open
            ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(runSpacing: 12, children: widget.filters),
              )
            : const SizedBox(width: double.infinity),
      ),
    ],
  );
}
