import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_dialog.dart';
import '../../core/widgets/auth_footer.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/demo_user.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeatPassword = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  bool _obscureRepeat = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _password.dispose();
    _repeatPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty ||
        _mobile.text.trim().isEmpty ||
        !_email.text.contains('@') ||
        _password.text.length < 8) {
      setState(
        () => _error =
            'Complete every field and use at least 8 password characters.',
      );
      return;
    }
    if (_repeatPassword.text != _password.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .signUp(
            displayName: _name.text,
            mobileNumber: _mobile.text,
            email: _email.text,
            password: _password.text,
          );
      if (!mounted) return;
      if (result.requiresEmailConfirmation) {
        await showDialog<void>(
          context: context,
          builder: (context) => ArangDialog(
            icon: const Icon(
              Icons.mark_email_read_outlined,
              color: AppColors.green,
            ),
            title: 'Check your email',
            content: const Text(
              'Open the confirmation message from Supabase Auth, then return to sign in.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        if (mounted) context.go('/login');
        return;
      }
      final user = result.user;
      if (user != null) {
        context.go(user.role == DemoRole.driver ? '/driver' : '/home');
      }
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                      ),
                    ),
                    // Centered header, matching the reference prototype --
                    // this was a left-aligned AppBar title before.
                    Text(
                      'Create Account',
                      textAlign: TextAlign.center,
                      style: AppTypography.display,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Center(
                      child: SizedBox(
                        width: 300,
                        child: Text(
                          'Commuter sign-up — book tricycle rides across '
                          'Calamba.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LabeledTextField(
                            label: 'Full Name',
                            hintText: 'Juan dela Cruz',
                            controller: _name,
                            icon: Icons.person_outline,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          LabeledTextField(
                            label: 'Mobile Number',
                            hintText: '0917 123 4567',
                            controller: _mobile,
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          LabeledTextField(
                            label: 'Email Address',
                            hintText: 'you@example.com',
                            controller: _email,
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newUsername],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          LabeledTextField(
                            label: 'Password',
                            hintText: 'Create a password',
                            controller: _password,
                            icon: Icons.lock_outline,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              style: IconButton.styleFrom(
                                fixedSize: const Size.square(42),
                                iconSize: 19,
                                backgroundColor: Colors.transparent,
                                side: BorderSide.none,
                              ),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Padding(
                            padding: EdgeInsets.only(left: 2),
                            child: Text(
                              'At least 8 characters',
                              style: AppTypography.caption,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          LabeledTextField(
                            label: 'Repeat Password',
                            hintText: 'Re-enter your password',
                            controller: _repeatPassword,
                            icon: Icons.lock_outline,
                            obscureText: _obscureRepeat,
                            onSubmitted: (_) => _submit(),
                            autofillHints: const [AutofillHints.newPassword],
                            suffixIcon: IconButton(
                              tooltip: _obscureRepeat
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => _obscureRepeat = !_obscureRepeat,
                              ),
                              style: IconButton.styleFrom(
                                fixedSize: const Size.square(42),
                                iconSize: 19,
                                backgroundColor: Colors.transparent,
                                side: BorderSide.none,
                              ),
                              icon: Icon(
                                _obscureRepeat
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.danger),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: Text(
                              _submitting
                                  ? 'Creating account…'
                                  : 'Create Account',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.amberFill,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                      ),
                      child: const Text(
                        'TODA driver? Driver accounts are registered by the '
                        'LGU/TODA office. Ask your TODA officer for your '
                        'activation code — there is no driver signup in the '
                        'app.',
                        style: AppTypography.caption,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AuthSwitchLink(
                      question: 'Already have an account?',
                      actionLabel: 'Log In',
                      onTap: () => context.go('/login'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const AuthLegalNotice(actionVerb: 'creating an account'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
