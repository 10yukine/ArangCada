import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/arangcada_mark.dart';
import '../../core/widgets/auth_footer.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/section_card.dart';
import '../../data/mock/mock_auth_repository.dart';
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
  String? _selectedDemoEmail;
  int _brandTapCount = 0;
  bool _showTestAccounts = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _prefill(DemoAccount account) {
    _emailController.text = account.user.email;
    _passwordController.text = account.password;
    setState(() {
      _errorMessage = null;
      _selectedDemoEmail = account.user.email;
    });
  }

  void _onBrandTap() {
    _brandTapCount++;
    if (_brandTapCount < 5) return;
    _brandTapCount = 0;
    setState(() => _showTestAccounts = true);
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
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _onBrandTap,
                            // `badge: true` swaps in the rounded-square
                            // backdrop and the square-framed mark. See
                            // ArangCadaMark for why both differ from every
                            // other call site.
                            child: const ArangCadaMark(badge: true),
                          ),
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
                        if (_showTestAccounts) ...[
                          const SizedBox(height: AppSpacing.xl),
                          Row(
                            children: [
                              Text(
                                'Test accounts',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              const Chip(label: Text('SANDBOX')),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: [
                              for (final account in MockAuthRepository.accounts)
                                ChoiceChip(
                                  selected:
                                      _selectedDemoEmail == account.user.email,
                                  side: BorderSide(
                                    color:
                                        _selectedDemoEmail == account.user.email
                                        ? AppColors.coral
                                        : AppColors.borderStrong,
                                  ),
                                  avatar: Icon(
                                    account.user.role == DemoRole.commuter
                                        ? Icons.person_outline
                                        : Icons.electric_rickshaw_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    account.user.role == DemoRole.commuter
                                        ? 'Commuter'
                                        : 'Driver',
                                  ),
                                  onSelected: (_) => _prefill(account),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Password: demo1234',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
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
