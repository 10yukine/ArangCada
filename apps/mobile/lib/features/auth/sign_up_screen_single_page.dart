import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/auth_footer.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/section_card.dart';
import '../../core/format/ph_mobile.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/demo_user.dart';

/// Backup of the single-page Sign Up screen retained as a back-out option.
class SignUpScreenSinglePage extends ConsumerStatefulWidget {
  const SignUpScreenSinglePage({super.key});

  @override
  ConsumerState<SignUpScreenSinglePage> createState() => _SignUpScreenSinglePageState();
}

class _SignUpScreenSinglePageState extends ConsumerState<SignUpScreenSinglePage> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeatPassword = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;
  bool _obscureRepeat = true;
  bool _agreedToLegal = false;
  String? _error;

  static const _padTop = AppSpacing.lg;
  static const _padBottom = AppSpacing.md;

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
    final mobile = normalizePhMobile(_mobile.text);
    if (!mobile.isValid) {
      setState(() => _error = mobile.error);
      return;
    }
    if (_repeatPassword.text != _password.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (!_agreedToLegal) {
      setState(() => _error = 'You must agree to the Terms of Service and Privacy Policy.');
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
            mobileNumber: mobile.e164!,
            email: _email.text,
            password: _password.text,
          );
      if (!mounted) return;

      if (result.requiresEmailConfirmation) {
        setState(
          () => _error =
              'Your account was created, but this project still requires email '
              'confirmation. Turn off "Confirm email" in Supabase, then sign in.',
        );
        return;
      }

      String? sendFailure;
      try {
        await ref.read(authRepositoryProvider).sendPhoneOtp(mobile.e164!);
      } on DemoAuthException catch (error) {
        sendFailure = error.message;
      }

      if (!mounted) return;
      final user = result.user;
      if (user != null && !user.needsPhoneVerification) {
        context.go(user.role == DemoRole.driver ? '/driver' : '/home');
      } else {
        context.go('/verify-phone', extra: sendFailure);
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
        child: Stack(
          children: [
            Positioned.fill(child: _form(context)),
            Positioned(
              top: AppSpacing.xs,
              left: AppSpacing.sm,
              child: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: AppColors.ink,
                  side: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          _padTop,
          AppSpacing.xl,
          _padBottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - _padTop - _padBottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    const SizedBox(height: AppSpacing.md),
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
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _agreedToLegal,
                                  onChanged: (value) => setState(() => _agreedToLegal = value ?? false),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              const Expanded(
                                child: AuthLegalNotice(prefixText: 'I agree to the '),
                              ),
                            ],
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
                    const SizedBox(height: AppSpacing.xs),
                    AuthSwitchLink(
                      question: 'Already have an account?',
                      actionLabel: 'Log In',
                      onTap: () => context.go('/login'),
                    ),
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
