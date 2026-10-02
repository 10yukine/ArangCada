import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../admin_controller.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

// =============================================================================
// Reset password -- public route opened from the "Forgot password?" email.
// =============================================================================
//
// main() exchanges the link for a short-lived recovery session while the app
// starts (redeemResetLink) and records that it did. This page is the only
// thing that session is used for: set a new password, then sign out so the
// person signs in normally. Without that exchange the page shows "expired",
// even to an administrator who is signed in. AdminApp skips its
// usual session restore on this route, so a reset link never drops anyone
// straight into the console without choosing a new password first.

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final formKey = GlobalKey<FormState>();
  final errors = FieldErrorReset();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool passwordHidden = true;
  bool confirmHidden = true;
  bool submitting = false;
  bool done = false;
  String? error;

  @override
  void dispose() {
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!errors.validate(formKey)) return;
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await repository.completePasswordReset(password.text);
      passwordRecovery.value = false;
      if (mounted) setState(() => done = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'The password could not be changed. The link may have expired -- request a new one from the sign-in page.',
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repository = ref.watch(adminRepositoryProvider);
    // Not hasSession alone: that is also true for an ordinary signed-in
    // administrator, who must give the current password to change it.
    final hasRecoverySession =
        passwordRecovery.value && (repository?.hasSession ?? false);

    final Widget body;
    if (done) {
      body = _Message(
        icon: Icons.check_circle_outline,
        tone: AdminColors.success,
        title: 'Password updated',
        message:
            'Sign in with your new password. If you use the ArangCada mobile app, open it and sign in there.',
        action: 'Go to sign in',
        onAction: () => context.go('/login'),
      );
    } else if (!hasRecoverySession) {
      body = _Message(
        icon: Icons.link_off,
        tone: AdminColors.warning,
        title: 'This reset link has expired',
        message:
            'Reset links work once, for a limited time, in the same browser where the reset was requested. Request a new link from the sign-in page.',
        action: 'Back to sign in',
        onAction: () => context.go('/login'),
      );
    } else {
      body = Panel(
        child: Form(
          key: formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose a new password',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'You will sign in again afterwards.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.adminColor(AdminColors.muted),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  errorBuilder: adminFieldError,
                  controller: password,
                  obscureText: passwordHidden,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: passwordHidden
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () =>
                          setState(() => passwordHidden = !passwordHidden),
                      icon: Icon(
                        passwordHidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  onChanged: (_) => errors.edited(password, formKey),
                  validator: errors.guard(password, adminPasswordProblem),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  errorBuilder: adminFieldError,
                  controller: confirmPassword,
                  obscureText: confirmHidden,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: confirmHidden
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () =>
                          setState(() => confirmHidden = !confirmHidden),
                      icon: Icon(
                        confirmHidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  onChanged: (_) => errors.edited(confirmPassword, formKey),
                  validator: errors.guard(
                    confirmPassword,
                    (value) => (value ?? '').isEmpty
                        ? 'Enter the new password again'
                        : value != password.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                AdminPasswordRequirements(
                  password: password,
                  repeat: confirmPassword,
                ),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.adminColor(AdminColors.danger),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update password'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.adminColor(AdminColors.background),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandTile(size: 64),
                const SizedBox(height: 14),
                Text(
                  'Reset your password',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });
  final IconData icon;
  final Color tone;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.adminColor(tone).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: context.adminColor(tone)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.adminColor(AdminColors.muted),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}
