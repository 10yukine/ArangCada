import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/ph_mobile.dart';
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
  int _step = 0;

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeatPassword = TextEditingController();

  bool _submitting = false;
  bool _obscure = true;
  bool _obscureRepeat = true;
  bool _agreedToLegal = false;
  String? _error;

  /// Content top padding ensures title/indicators start neatly below
  /// the pinned back button (top: 8, height: 48 => Y: 56).
  static const double _padTop = 64.0;
  static const double _padBottom = AppSpacing.md;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _mobile.dispose();
    _email.dispose();
    _password.dispose();
    _repeatPassword.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (_step > 0) {
      setState(() {
        _step--;
        _error = null;
      });
    } else {
      context.pop();
    }
  }

  void _nextFromStep0() {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _error = 'Please enter both your first and last name.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step = 1;
    });
  }

  void _nextFromStep1() {
    final mobile = normalizePhMobile(_mobile.text);
    if (!mobile.isValid) {
      setState(() => _error = mobile.error);
      return;
    }
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step = 2;
    });
  }

  Future<void> _submit() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_repeatPassword.text != _password.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (!_agreedToLegal) {
      setState(
        () => _error =
            'You must agree to the Terms of Service and Privacy Policy.',
      );
      return;
    }

    final mobile = normalizePhMobile(_mobile.text);
    if (!mobile.isValid) {
      setState(() => _error = mobile.error);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // Re-join the separated first and last names into the user's full display name.
      final fullName = '${_firstName.text.trim()} ${_lastName.text.trim()}';
      final result = await ref
          .read(authRepositoryProvider)
          .signUp(
            displayName: fullName,
            mobileNumber: mobile.e164!,
            email: _email.text.trim(),
            password: _password.text,
          );
      if (!mounted) return;

      // No session means the project still demands an emailed confirmation
      // link before the account may act. Turn off "Confirm email" in Supabase.
      if (result.requiresEmailConfirmation) {
        setState(
          () => _error =
              'Your account was created, but this project still requires email '
              'confirmation. Turn off "Confirm email" in Supabase, then sign in.',
        );
        return;
      }

      // Verification is a 6-digit SMS code rather than an emailed link.
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
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: _content(context)),
              Positioned(
                top: AppSpacing.xs,
                left: AppSpacing.sm,
                child: IconButton(
                  onPressed: _handleBack,
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
      ),
    );
  }

  Widget _content(BuildContext context) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        _padTop,
        AppSpacing.xl,
        _padBottom,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _stepProgressBar(),
                const SizedBox(height: AppSpacing.md),
                _stepHeader(),
                const SizedBox(height: AppSpacing.md),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: KeyedSubtree(
                    key: ValueKey<int>(_step),
                    child: _currentStepCard(context),
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
    );
  }

  Widget _stepProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _step == 0
                  ? 'STEP 1 OF 3: IDENTITY'
                  : _step == 1
                      ? 'STEP 2 OF 3: CONTACT'
                      : 'STEP 3 OF 3: SECURITY',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              '${_step + 1} of 3',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: List.generate(3, (index) {
            final isCompletedOrCurrent = index <= _step;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(
                  right: index < 2 ? AppSpacing.xs : 0,
                ),
                decoration: BoxDecoration(
                  color: isCompletedOrCurrent
                      ? AppColors.primary
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _stepHeader() {
    final title = _step == 0
        ? 'Create Account'
        : _step == 1
            ? 'Contact Details'
            : 'Set Password';
    final subtitle = _step == 0
        ? 'Commuter sign-up — book tricycle rides across Calamba.'
        : _step == 1
            ? 'We will send a 6-digit SMS verification code to your phone.'
            : 'Create a secure password to protect your account.';

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.display,
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: SizedBox(
            width: 320,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _currentStepCard(BuildContext context) {
    switch (_step) {
      case 0:
        return _step0Card(context);
      case 1:
        return _step1Card(context);
      case 2:
      default:
        return _step2Card(context);
    }
  }

  /// Step 1 (Identity): First Name and Last Name are explicitly separated into
  /// distinct input fields for clearer, structured data capture and autofill support.
  /// They are validated individually and concatenated into a single display name
  /// on final submission.
  Widget _step0Card(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledTextField(
            label: 'First Name',
            hintText: 'Juan',
            controller: _firstName,
            icon: Icons.person_outline,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledTextField(
            label: 'Last Name',
            hintText: 'dela Cruz',
            controller: _lastName,
            icon: Icons.person_outline,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _nextFromStep0(),
            autofillHints: const [AutofillHints.familyName],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _nextFromStep0,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _step1Card(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledTextField(
            label: 'Mobile Number',
            hintText: '0917 123 4567',
            controller: _mobile,
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledTextField(
            label: 'Email Address',
            hintText: 'you@example.com',
            controller: _email,
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _nextFromStep1(),
            autofillHints: const [AutofillHints.email],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _nextFromStep1,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _step2Card(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledTextField(
            label: 'Password',
            hintText: 'Create a password',
            controller: _password,
            icon: Icons.lock_outline,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
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
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            autofillHints: const [AutofillHints.newPassword],
            suffixIcon: IconButton(
              tooltip: _obscureRepeat ? 'Show password' : 'Hide password',
              onPressed: () =>
                  setState(() => _obscureRepeat = !_obscureRepeat),
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
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _agreedToLegal,
                    onChanged: (value) =>
                        setState(() => _agreedToLegal = value ?? false),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: AuthLegalNotice(
                  prefixText: 'I agree to the ',
                  textAlign: TextAlign.start,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: Text(
              _submitting ? 'Creating account…' : 'Create Account',
            ),
          ),
        ],
      ),
    );
  }
}
