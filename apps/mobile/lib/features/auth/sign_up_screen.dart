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
    // Normalise before anything else touches the number. Supabase needs E.164,
    // and a number that fails here must be rejected at the form -- if a bad
    // number reaches the gateway the account is created but the code goes
    // nowhere, stranding the user with no way to verify.
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

      // No session means the project still demands an emailed confirmation
      // link before the account may act. The SMS flow cannot run without one:
      // updateUser(phone:) has no signed-in user to attach a number to, and
      // /verify-phone bounces straight back to /login because the router sends
      // a null user anywhere that is not an auth path. That bounce is silent
      // and looks exactly like a rejected registration, so say what happened
      // instead of navigating into a dead end.
      //
      // Verification here is deliberately the SMS code and not an emailed link
      // (a Filipino holds one or two SIMs but unlimited email addresses), so
      // reaching this branch is a project misconfiguration, not a user error.
      // requiresEmailConfirmation was already being computed and thrown away.
      if (result.requiresEmailConfirmation) {
        setState(
          () => _error =
              'Your account was created, but this project still requires email '
              'confirmation. Turn off "Confirm email" in Supabase, then sign in.',
        );
        return;
      }

      // Since 31 Aug 2026 verification is a 6-digit SMS code rather than an
      // emailed link. Send it now so the verify screen opens with a code
      // already on its way, then let the router redirect take over: it watches
      // DemoState and routes an unverified account to /verify-phone on its own.
      //
      // A failure here is deliberately NOT fatal. The account exists at this
      // point, so bouncing the user back to registration would orphan it. The
      // verify screen has a Resend button; surface the reason and continue.
      // Carried to the next screen rather than shown on this one. Setting it
      // here displayed the reason on a form that is destroyed by the very next
      // line, so a send that failed looked exactly like a send that worked.
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
        // The back button is chrome, not content: it is pinned to the top-left
        // of the screen and deliberately kept outside the centred column, so
        // vertically centring the form does not drag navigation down with it.
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
        // Clamping, not Never. The form fits a phone with the keyboard closed,
        // and the minHeight below already makes the child exactly viewport
        // height in that case -- so there is no scroll extent and no rubber
        // banding, which is what NeverScrollableScrollPhysics was reaching for.
        //
        // But the Scaffold shrinks its body by the keyboard inset, so once the
        // keyboard opens `constraints.maxHeight` drops and the form no longer
        // fits. Disabling scrolling outright meant the lower fields could not
        // be reached at all: focusing "Repeat Password" put the caret behind
        // the keyboard with no way to bring it into view. Clamping also lets
        // Flutter auto-scroll the focused field into view, which it cannot do
        // inside a scrollable that refuses to move.
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          _padTop,
          AppSpacing.xl,
          _padBottom,
        ),
        // A bare Center does nothing inside a scroll view: the view sizes
        // itself to its child, so there is no spare height to centre within.
        // Forcing the child to at least fill the viewport (minus the padding
        // the view already added) is what creates that slack.
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
