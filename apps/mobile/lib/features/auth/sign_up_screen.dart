import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/ph_mobile.dart';
import '../../core/widgets/auth_footer.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/password_requirements.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/demo_user.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  /// Three form steps here, then SMS verification as step 4 on its own
  /// screen, which continues this progress bar.
  static const _stepCount = 4;

  int _step = 0;

  /// Direction of the last step change, so the new step slides in from the
  /// side the user is travelling towards (and back out the way it came).
  bool _forward = true;

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
  final _errors = <String, String>{};
  // Not tied to one field: the legal checkbox and server replies.
  String? _error;

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

  void _goTo(int step) {
    setState(() {
      _forward = step > _step;
      _step = step;
      _error = null;
      _errors.clear();
    });
  }

  void _handleBack() {
    if (_step > 0) {
      _goTo(_step - 1);
    } else {
      context.pop();
    }
  }

  void _nextFromStep0() {
    setState(() {
      _errors.clear();
      if (_firstName.text.trim().isEmpty) {
        _errors['first'] = 'Enter your first name';
      }
      if (_lastName.text.trim().isEmpty) {
        _errors['last'] = 'Enter your last name';
      }
    });
    if (_errors.isEmpty) _goTo(1);
  }

  void _nextFromStep1() {
    final mobile = normalizePhMobile(_mobile.text);
    final email = _email.text.trim();
    setState(() {
      _errors.clear();
      if (!mobile.isValid) _errors['mobile'] = mobile.error!;
      if (email.isEmpty) {
        _errors['email'] = 'Enter your email address';
      } else if (!email.contains('@') || !email.contains('.')) {
        _errors['email'] = 'Enter a valid email address, like you@example.com';
      }
    });
    if (_errors.isEmpty) _goTo(2);
  }

  Future<void> _submit() async {
    setState(() {
      _errors.clear();
      _error = null;
      final problem = passwordProblem(_password.text);
      if (problem != null) _errors['password'] = problem;
      if (_repeatPassword.text.isEmpty) {
        _errors['repeat'] = 'Enter the password again';
      } else if (_repeatPassword.text != _password.text) {
        _errors['repeat'] = 'Passwords do not match';
      }
    });
    if (_errors.isNotEmpty) return;
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
              'Check your email to continue. If you already have an account, '
              'log in with your existing password.',
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
    } on ExistingAccountException {
      if (mounted) context.go('/login', extra: _email.text.trim());
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  VoidCallback? get _primaryAction => switch (_step) {
    0 => _nextFromStep0,
    1 => _nextFromStep1,
    _ => _submitting ? null : _submit,
  };

  String get _primaryLabel => switch (_step) {
    0 || 1 => 'Continue',
    _ => _submitting ? 'Creating account…' : 'Create Account',
  };

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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  _topBar(),
                  Expanded(child: _content(context)),
                  _bottomActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Back and progress share one row, so the bar reads as "how far along"
  /// rather than as another heading competing with the title.
  Widget _topBar() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xl,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: AppColors.ink,
              side: BorderSide.none,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Semantics(
              label: 'Step ${_step + 1} of $_stepCount',
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: (_step + 1) / _stepCount),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    color: AppColors.primary,
                    backgroundColor: AppColors.primaryFill,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: AutofillGroup(
        child: AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : AppMotion.sheet,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) {
            // The incoming step enters from the direction of travel; the
            // outgoing one (animation running in reverse) leaves the
            // opposite way. A short distance keeps it calm, not dizzying.
            final incoming = child.key == ValueKey<int>(_step);
            final dx = (_forward == incoming ? 1 : -1) * 0.12;
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: Offset(dx, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_step),
            child: _stepBody(context),
          ),
        ),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    final (title, subtitle, fields) = switch (_step) {
      0 => (
        "Let's get you riding",
        'So your driver knows who to pick up.',
        _nameFields(),
      ),
      1 => (
        'Nice to meet you, ${_firstName.text.trim()}!',
        "We'll text a 6-digit code to confirm it.",
        _contactFields(),
      ),
      _ => (
        'Almost there',
        'Set a password to keep your account safe.',
        _passwordFields(),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Step ${_step + 1} of $_stepCount',
          style: AppTypography.label.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(title, style: AppTypography.display),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: AppTypography.bodySm.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        ...fields,
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: AppTypography.bodySm.copyWith(color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  /// Bottom-pinned so the next action sits in the same place on every step
  /// and rides above the keyboard.
  Widget _bottomActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: _primaryAction, child: Text(_primaryLabel)),
          // Hidden while typing: with the keyboard up it only covers the
          // field being filled in (seen on a Galaxy S20 FE).
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            AuthSwitchLink(
              question: 'Already have an account?',
              actionLabel: 'Log In',
              onTap: () => context.go('/login'),
            ),
        ],
      ),
    );
  }

  /// First and last name are captured separately for autofill and joined
  /// into the display name on submission.
  List<Widget> _nameFields() => [
    LabeledTextField(
      label: 'First Name',
      hintText: 'Juan',
      controller: _firstName,
      icon: Icons.person_outline,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.givenName],
      errorText: _errors['first'],
      onChanged: (_) => setState(() => _errors.remove('first')),
    ),
    const SizedBox(height: AppSpacing.md),
    LabeledTextField(
      label: 'Last Name',
      hintText: 'dela Cruz',
      controller: _lastName,
      icon: Icons.person_outline,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _nextFromStep0(),
      autofillHints: const [AutofillHints.familyName],
      errorText: _errors['last'],
      onChanged: (_) => setState(() => _errors.remove('last')),
    ),
  ];

  List<Widget> _contactFields() => [
    LabeledTextField(
      label: 'Mobile Number',
      hintText: '0917 123 4567',
      controller: _mobile,
      icon: Icons.phone_outlined,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.telephoneNumber],
      autofocus: true,
      errorText: _errors['mobile'],
      onChanged: (_) => setState(() => _errors.remove('mobile')),
    ),
    const SizedBox(height: AppSpacing.md),
    LabeledTextField(
      label: 'Email Address',
      hintText: 'you@example.com',
      controller: _email,
      icon: Icons.email_outlined,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _nextFromStep1(),
      autofillHints: const [AutofillHints.email],
      errorText: _errors['email'],
      onChanged: (_) => setState(() => _errors.remove('email')),
    ),
  ];

  List<Widget> _passwordFields() => [
    LabeledTextField(
      label: 'Password',
      hintText: 'Create a password',
      controller: _password,
      icon: Icons.lock_outline,
      obscureText: _obscure,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.newPassword],
      autofocus: true,
      errorText: _errors['password'],
      onChanged: (_) => setState(() => _errors.remove('password')),
      suffixIcon: _visibilityToggle(
        obscured: _obscure,
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    ),
    const SizedBox(height: AppSpacing.md),
    LabeledTextField(
      label: 'Repeat Password',
      hintText: 'Re-enter your password',
      controller: _repeatPassword,
      icon: Icons.lock_outline,
      obscureText: _obscureRepeat,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      autofillHints: const [AutofillHints.newPassword],
      errorText: _errors['repeat'],
      onChanged: (_) => setState(() => _errors.remove('repeat')),
      suffixIcon: _visibilityToggle(
        obscured: _obscureRepeat,
        onPressed: () => setState(() => _obscureRepeat = !_obscureRepeat),
      ),
    ),
    const SizedBox(height: AppSpacing.sm),
    // Live checks: people see each requirement tick off as they type
    // instead of learning about a typo only after tapping Create Account.
    PasswordRequirements(password: _password, repeat: _repeatPassword),
    const SizedBox(height: AppSpacing.lg),
    InkWell(
      onTap: () => setState(() => _agreedToLegal = !_agreedToLegal),
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Row(
        children: [
          Checkbox(
            value: _agreedToLegal,
            visualDensity: VisualDensity.compact,
            onChanged: (value) =>
                setState(() => _agreedToLegal = value ?? false),
          ),
          const SizedBox(width: AppSpacing.xxs),
          const Expanded(
            child: AuthLegalNotice(
              prefixText: 'I agree to the ',
              textAlign: TextAlign.start,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    ),
  ];

  Widget _visibilityToggle({
    required bool obscured,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: obscured ? 'Show password' : 'Hide password',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(42),
        iconSize: 19,
        backgroundColor: Colors.transparent,
        side: BorderSide.none,
      ),
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    );
  }
}
