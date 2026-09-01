import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/arangcada_mark.dart';
import '../../core/widgets/auth_footer.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/demo_user.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _submitting = false;
  bool _obscurePassword = true;

  static const _padTop = AppSpacing.lg;
  static const _padBottom = AppSpacing.xl;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }


  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
      if (!mounted) return;
      context.go(user.role == DemoRole.commuter ? '/home' : '/driver');
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              _padTop,
              AppSpacing.xl,
              _padBottom,
            ),
            // The padding is subtracted because SingleChildScrollView adds it
            // *around* this box. Using the raw viewport height here makes the
            // content taller than the screen by exactly the padding, which
            // reads as a page biased toward the bottom.
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
                        const Center(
                          child: ArangCadaMark(badge: true),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Center(
                          child: SizedBox(
                            width: 280,
                            child: Text(
                              'Tricycle rides across Calamba City, anchored to '
                              'your local TODA.',
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
                                label: 'Email Address',
                                // Format-illustrative, not a generic
                                // instruction -- matches the reference
                                // prototype and shows the expected shape of
                                // the answer at a glance.
                                hintText: 'you@example.com',
                                controller: _emailController,
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              LabeledTextField(
                                label: 'Password',
                                hintText: 'Enter your password',
                                controller: _passwordController,
                                icon: Icons.lock_outline,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _submit(),
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
                              if (_errorMessage != null) ...[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  _errorMessage!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.danger),
                                ),
                              ],
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () =>
                                      context.push('/forgot-password'),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
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
                        const SizedBox(height: AppSpacing.sm),
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
