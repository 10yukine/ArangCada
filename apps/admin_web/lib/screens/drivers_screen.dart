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
          // LGU-initiated enrollment (Spec 20) -- the LGU inputs the
          // driver's email; the flow itself decides whether that email
          // gets an invite or promotes an existing account. Replaces the
          // old passive "Applications submitted in the driver app" pill,
          // which encoded the wrong model: nothing in this app has ever
          // let a driver self-apply.
          action: !state.connected
              ? FilledButton.icon(
                  onPressed: () => _showEnrollment(context, ref),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Enroll driver'),
                )
              : auth.value!.role == AdminRole.lgu
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
        Material(
          type: MaterialType.transparency,
          child: Column(
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
                  return Wrap(spacing: 12, runSpacing: 12, children: fields);
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
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showDriver(context, ref, driver),
                              ),
                              const Divider(height: 1),
                            ],
                          ],
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
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
                                      OutlinedButton(
                                        onPressed: () =>
                                            _showDriver(context, ref, driver),
                                        child: const Text('Review'),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
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
              'Enrolled → Documents submitted → Under review → Approved. Rejected, suspended, and expired records require follow-up before returning to service.',
            ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// Driver enrollment by email (Spec 20) -- LGU-initiated, mirrors the admin
// invite system (Spec 19) closely.
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

Future<void> _showEnrollment(BuildContext context, WidgetRef ref) async {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final plate = TextEditingController();
  String toda = auth.value!.toda ?? 'Brgy. Real';
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Enroll a driver'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: (value) => (value?.trim().length ?? 0) >= 3
                        ? null
                        : 'Enter the driver name.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: toda,
                    decoration: const InputDecoration(labelText: 'TODA'),
                    items: [
                      for (final item
                          in auth.value!.role == AdminRole.toda
                              ? [auth.value!.toda!]
                              : ['Brgy. Real', 'Parian', 'Canlubang'])
                        DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: (value) => setDialogState(() => toda = value!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                    ),
                    validator: (value) =>
                        (value?.replaceAll(RegExp(r'\D'), '').length ?? 0) >= 10
                        ? null
                        : 'Enter a valid mobile number.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: plate,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Plate / body number',
                    ),
                    validator: (value) => (value?.trim().length ?? 0) >= 3
                        ? null
                        : 'Enter the plate or body number.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Create enrollment'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true && context.mounted) {
    final driver = ref
        .read(adminProvider.notifier)
        .enrollDriver(
          name: name.text,
          toda: toda,
          phone: phone.text,
          plate: plate.text,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Enrollment ${driver.enrollmentCode} created.')),
    );
  }
  name.dispose();
  phone.dispose();
  plate.dispose();
}

Future<void> _showDriver(
  BuildContext context,
  WidgetRef ref,
  Driver driver,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(driver.name)),
          StatusPill(
            driverStatusLabel(driver.status),
            tone: driverTone(driver.status),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 24,
                runSpacing: 14,
                children: [
                  LabelValue('Enrollment', driver.enrollmentCode),
                  LabelValue('TODA', driver.toda),
                  LabelValue('Phone', driver.phone),
                  LabelValue('Plate', driver.plate),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Submitted documents',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final item in const [
                ('drivers_license', 'Driver’s license'),
                ('mtop_franchise', 'MTOP / franchise permit'),
                ('toda_membership', 'TODA membership endorsement'),
                ('or_cr', 'Vehicle OR / CR registration'),
                ('barangay_clearance', 'Barangay clearance (optional)'),
                ('vehicle_photo', 'Vehicle photo (optional)'),
              ].indexed)
                _DriverDocumentRow(
                  driver: driver,
                  documentType: item.$2.$1,
                  label: item.$2.$2,
                  demoIndex: item.$1,
                  connected: auth.value?.connected ?? false,
                ),
              const SizedBox(height: 12),
              Text(
                auth.value?.connected ?? false
                    ? 'Uploaded on the driver’s behalf after their paper submission is checked in person. Only this administrator’s view mints a signed link to a file -- never a public URL, and it expires in 5 minutes.'
                    : 'Local demo mode has no Storage bucket or RPC to call -- upload, view, and review are disabled here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (auth.value?.role == AdminRole.lgu &&
            driver.status == DriverStatus.suspended)
          OutlinedButton(
            onPressed: () => _applyDriverAction(
              context,
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
              context,
              ref,
              driver,
              DriverStatus.suspended,
            ),
            child: const Text('Suspend'),
          ),
        if (auth.value?.role == AdminRole.lgu)
          OutlinedButton(
            onPressed: () => _confirmDriverAction(
              context,
              ref,
              driver,
              DriverStatus.rejected,
            ),
            child: const Text('Reject'),
          ),
        FilledButton(
          onPressed:
              driver.approvedDocuments < 4 ||
                  driver.status == DriverStatus.suspended
              ? null
              : () => _applyDriverAction(
                  context,
                  ref,
                  driver,
                  DriverStatus.approved,
                  'Required driver documents reviewed and accepted',
                ),
          child: const Text('Approve'),
        ),
      ],
    ),
  );
}

class _DriverDocumentRow extends ConsumerStatefulWidget {
  const _DriverDocumentRow({
    required this.driver,
    required this.documentType,
    required this.label,
    required this.demoIndex,
    required this.connected,
  });

  final Driver driver;
  final String documentType;
  final String label;
  final int demoIndex;
  final bool connected;

  @override
  ConsumerState<_DriverDocumentRow> createState() => _DriverDocumentRowState();
}

class _DriverDocumentRowState extends ConsumerState<_DriverDocumentRow> {
  bool _busy = false;

  String? get _status => widget.connected
      ? widget.driver.documentStatuses[widget.documentType]
      : widget.demoIndex < widget.driver.documents
      ? 'approved'
      : null;

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
    final path = widget.connected
        ? widget.driver.documentPaths[widget.documentType]
        : null;
    final approved = status == 'approved';
    final rejected = status == 'rejected';
    final description = switch (status) {
      'approved' => 'Approved',
      'pending' => 'Pending review',
      'rejected' => 'Rejected',
      _ => 'Missing',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                approved
                    ? Icons.check_circle
                    : rejected
                    ? Icons.cancel
                    : Icons.radio_button_unchecked,
                color: approved
                    ? context.adminColor(AdminColors.success)
                    : rejected
                    ? context.adminColor(AdminColors.danger)
                    : context.adminColor(AdminColors.muted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          if (path != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: _DriverDocumentPhoto(path: path),
            ),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy || !widget.connected ? null : _upload,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(path == null ? 'Upload' : 'Replace'),
                ),
                if (widget.connected &&
                    status == 'pending' &&
                    path != null) ...[
                  FilledButton(
                    onPressed: _busy ? null : () => _review(approve: true),
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _review(approve: false),
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
            height: 100,
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
            height: 160,
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
