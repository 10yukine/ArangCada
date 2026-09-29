import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/ph_mobile.dart';
import '../../core/widgets/arangcada_mark.dart';
import '../../core/widgets/auth_footer.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/demo_user.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({this.existingAccountEmail, super.key});

  final String? existingAccountEmail;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _identifierError;
  String? _passwordError;
  bool _submitting = false;
  bool _obscurePassword = true;

  static const _padVertical = AppSpacing.md;

  @override
  void initState() {
    super.initState();
    _identifierController.text = widget.existingAccountEmail ?? '';
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    // Anything with an @ is an email; otherwise it must be a PH mobile
    // number, so people can log in without typing an address.
    final mobile = identifier.contains('@')
        ? null
        : normalizePhMobile(identifier);
    setState(() {
      _identifierError = identifier.isEmpty
          ? 'Enter your mobile number or email'
          : mobile != null && !mobile.isValid
          ? 'Enter your email or a Philippine mobile number, like 0917 123 4567'
          : null;
      _passwordError = password.isEmpty ? 'Enter your password' : null;
    });
    if (_identifierError != null || _passwordError != null) return;

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final auth = ref.read(authRepositoryProvider);
      final DemoUser user;
      if (mobile == null) {
        user = await auth.signIn(email: identifier, password: password);
      } else {
        user = await auth.signInWithPhone(
          phone: mobile.e164!,
          password: password,
        );
      }
      if (!mounted) return;
      context.go(user.role == DemoRole.commuter ? '/home' : '/driver');
    } on DemoAuthException catch (error) {
      // Sign-in never says which part was wrong, so the message sits under
      // the password, where the fix usually is.
      if (mounted) setState(() => _passwordError = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: _padVertical,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - (_padVertical * 2),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.existingAccountEmail != null) ...[
                          Text(
                            'Sign in with your existing password to continue. '
                            'You can add your mobile number after signing in.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        const Center(child: ArangCadaMark(badge: true)),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Tricycle rides across Calamba City,\nanchored to your local TODA.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.lg,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadii.lg),
                            border: Border.all(color: AppColors.border),
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.shadowLight,
                                blurRadius: 16,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LabeledTextField(
                                label: '',
                                hintText: 'Mobile number or email address',
                                controller: _identifierController,
                                icon: Icons.person_outline,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [
                                  AutofillHints.email,
                                  AutofillHints.username,
                                ],
                                textInputAction: TextInputAction.next,
                                errorText: _identifierError,
                                onChanged: (_) {
                                  if (_identifierError != null) {
                                    setState(() => _identifierError = null);
                                  }
                                },
                              ),
                              const SizedBox(height: AppSpacing.md),
                              LabeledTextField(
                                label: '',
                                hintText: 'Password',
                                controller: _passwordController,
                                icon: Icons.lock_outline,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _submit(),
                                errorText: _passwordError,
                                onChanged: (_) {
                                  if (_passwordError != null) {
                                    setState(() => _passwordError = null);
                                  }
                                },
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  style: IconButton.styleFrom(
                                    fixedSize: const Size.square(42),
                                    iconSize: 19,
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide.none,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () =>
                                      context.push('/forgot-password'),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              FilledButton(
                                onPressed: _submitting ? null : _submit,
                                child: Text(
                                  _submitting ? 'Logging in…' : 'Log In',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AuthSwitchLink(
                          question: 'New Commuter?',
                          actionLabel: 'Sign Up',
                          onTap: () => context.push('/signup'),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const AuthLegalNotice(actionVerb: 'logging in'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
