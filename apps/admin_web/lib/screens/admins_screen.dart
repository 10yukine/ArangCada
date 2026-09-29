import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_controller.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

// =============================================================================
// Admins (Spec 19) -- LGU/TODA admin accounts, invite by email
// =============================================================================

class AdminsScreen extends ConsumerStatefulWidget {
  const AdminsScreen({super.key});
  @override
  ConsumerState<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends ConsumerState<AdminsScreen> {
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
      await ref.read(adminProvider.notifier).refreshAdminAccounts(session);
    } catch (_) {
      // The two lists below simply stay empty -- there is nothing more
      // specific to show here, matching how _refreshReportedChats
      // (SafetyScreen) also swallows a transient load failure and relies on
      // the next poll/visit rather than a standing error banner.
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = auth.value!;
    if (session.role != AdminRole.lgu) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Admins',
            subtitle: 'LGU and TODA administrator accounts.',
          ),
          SizedBox(height: 22),
          Panel(
            child: EmptyState(
              message:
                  'Administrator accounts are managed by an LGU administrator, not a TODA desk.',
            ),
          ),
        ],
      );
    }

    final state = ref.watch(adminProvider);
    final lgu = state.adminAccounts
        .where((account) => account.role == AdminRole.lgu)
        .toList();
    final toda = state.adminAccounts
        .where((account) => account.role == AdminRole.toda)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeading(
          title: 'Admins',
          subtitle:
              'Invite and review LGU and TODA administrator accounts by email.',
          action: FilledButton.icon(
            onPressed: state.connected
                ? () => _showInvite(context, ref, state.todaZoneOptions)
                : null,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Invite admin'),
          ),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final lguPanel = _AdminAccountList(
              title: 'LGU administrators',
              accounts: lgu,
            );
            final todaPanel = _AdminAccountList(
              title: 'TODA administrators',
              accounts: toda,
            );
            return constraints.maxWidth < 950
                ? Column(
                    children: [lguPanel, const SizedBox(height: 14), todaPanel],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: lguPanel),
                      const SizedBox(width: 16),
                      Expanded(child: todaPanel),
                    ],
                  );
          },
        ),
        if (state.adminInvites.isNotEmpty) ...[
          const SizedBox(height: 22),
          _PendingInvitesPanel(invites: state.adminInvites),
        ],
      ],
    );
  }
}

class _AdminAccountList extends ConsumerWidget {
  const _AdminAccountList({required this.title, required this.accounts});
  final String title;
  final List<AdminAccount> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        if (accounts.isEmpty)
          const EmptyState(message: 'No accounts yet.')
        else
          for (final account in accounts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          account.toda == null
                              ? account.email
                              : '${account.email} -- ${account.toda}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          account.invitedByName == null
                              ? 'Pre-existing account (not invited)'
                              : 'Invited by ${account.invitedByName}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: context.adminColor(AdminColors.muted),
                              ),
                        ),
                      ],
                    ),
                  ),
                  // Nobody removes themselves, so an LGU admin always remains.
                  if (account.id != auth.value?.userId)
                    TextButton(
                      onPressed: () => _remove(context, ref, account),
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ),
      ],
    ),
  );

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    AdminAccount account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${account.name}?'),
        content: const SizedBox(
          width: 420,
          child: Text(
            'They lose access to the admin console right away and their '
            'pending invites stop working. Their account stays as an ordinary '
            'ArangCada account, which they can delete from the app.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove administrator'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(adminProvider.notifier).removeAdmin(account.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${account.name} is no longer an administrator.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : 'This administrator could not be removed.',
          ),
        ),
      );
    }
  }
}

class _PendingInvitesPanel extends ConsumerWidget {
  const _PendingInvitesPanel({required this.invites});
  final List<AdminInvite> invites;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pending invites', style: Theme.of(context).textTheme.titleLarge),
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
                        invite.scope == AdminRole.toda
                            ? 'TODA${invite.toda != null ? ' -- ${invite.toda}' : ''} -- sent ${shortTime(invite.created)}'
                            : 'LGU -- sent ${shortTime(invite.created)}',
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

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    AdminInvite invite,
  ) async {
    try {
      await ref.read(adminProvider.notifier).revokeAdminInvite(invite.id);
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

Future<void> _showInvite(
  BuildContext context,
  WidgetRef ref,
  List<(String id, String name)> todaZoneOptions,
) async {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  String scope = 'lgu';
  String? todaZoneId = todaZoneOptions.isEmpty
      ? null
      : todaZoneOptions.first.$1;
  bool sending = false;

  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
        actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invite an administrator'),
            const SizedBox(height: 4),
            Text(
              'They receive a one-time link by email to create their account.',
              style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                color: dialogContext.adminColor(AdminColors.muted),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: email,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (value) => (value?.trim().contains('@') ?? false)
                        ? null
                        : 'Enter a valid email address.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: scope,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Scope',
                      prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'lgu',
                        child: Text('LGU administrator -- all TODAs'),
                      ),
                      DropdownMenuItem(
                        value: 'toda',
                        child: Text('TODA administrator -- one TODA'),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => scope = value!),
                  ),
                  if (scope == 'toda') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: todaZoneId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'TODA'),
                      items: [
                        for (final zone in todaZoneOptions)
                          DropdownMenuItem(
                            value: zone.$1,
                            child: Text(zone.$2),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => todaZoneId = value),
                      validator: (value) =>
                          value == null ? 'Select a TODA.' : null,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: sending
                ? null
                : () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: sending
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setDialogState(() => sending = true);
                    try {
                      await ref
                          .read(adminProvider.notifier)
                          .sendAdminInvite(
                            email: email.text.trim(),
                            scope: scope,
                            todaZoneId: scope == 'toda' ? todaZoneId : null,
                          );
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (error) {
                      setDialogState(() => sending = false);
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              error is StateError
                                  ? error.message
                                  : 'The invite could not be sent.',
                            ),
                          ),
                        );
                      }
                    }
                  },
            child: sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send invite'),
          ),
        ],
      ),
    ),
  );
  email.dispose();
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invite sent.')));
  }
}
