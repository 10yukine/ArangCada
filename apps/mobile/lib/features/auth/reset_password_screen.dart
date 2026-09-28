import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';

/// Opened by the password-reset email link (ph.calamba.arangcada://
/// reset-password). Supabase has already exchanged the link for a recovery
/// session, so no current password is asked for. Either way out ends signed
/// out on the login screen: the recovery session is not a normal sign-in.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool updated}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } finally {
      passwordRecoveryPending.value = false;
    }
    if (updated) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Password updated. Log in with your new password.'),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_next.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (_repeat.text != _next.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updatePassword(_next.text);
      await _finish(updated: true);
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final toggle = IconButton(
      tooltip: _obscure ? 'Show password' : 'Hide password',
      onPressed: () => setState(() => _obscure = !_obscure),
      icon: Icon(
        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('New password'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Choose a new password',
                    style: AppTypography.displaySm,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'You opened a password reset link. Set a new password, '
                    'then log in with it.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LabeledTextField(
                    label: 'New password',
                    hintText: 'At least 8 characters',
                    controller: _next,
                    icon: Icons.lock_outline,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    suffixIcon: toggle,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LabeledTextField(
                    label: 'Repeat new password',
                    hintText: 'Re-enter your new password',
                    controller: _repeat,
                    icon: Icons.lock_outline,
                    obscureText: _obscure,
                    onSubmitted: (_) => _save(),
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ArangButton(
                    label: _saving ? 'Saving...' : 'Save new password',
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: _saving ? null : () => _finish(updated: false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
