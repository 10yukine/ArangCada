import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/auth_footer.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A tile, not a bare glyph. The OTP screen already frames
                  // its icon this way, and an unbacked 40px icon floating above
                  // a heading reads as decoration rather than as the subject of
                  // the screen.
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primaryFill,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        size: 28,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _sent ? 'Check your email' : 'Reset your password',
                    style: AppTypography.displaySm,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _sent
                        ? 'If an account matches that address, Supabase Auth sent recovery instructions.'
                        : 'Enter the email address connected to your ArangCada account.',
                  ),
                  if (!_sent) ...[
                    const SizedBox(height: AppSpacing.md),
                    // The app's own field, not a raw TextField. Login and
                    // register both use LabeledTextField; this screen was the
                    // last one rendering a Material label that floats into the
                    // border on focus.
                    LabeledTextField(
                      label: 'Email address',
                      controller: _email,
                      icon: Icons.email_outlined,
                      hintText: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.done,
                      errorText: _error,
                      onSubmitted: (_) => _send(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ArangButton(
                      label: _sending ? 'Sending...' : 'Send Reset Link',
                      icon: Icons.arrow_forward,
                      iconTrailing: true,
                      onPressed: _sending ? null : _send,
                    ),
                  ] else ...[
                    const SizedBox(height: AppSpacing.md),
                    ArangButton(
                      label: 'Back to Sign In',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ],
              ),
            ),
            if (!_sent) ...[
              const SizedBox(height: AppSpacing.lg),
              AuthSwitchLink(
                question: 'Remember your password?',
                actionLabel: 'Log In',
                onTap: () => Navigator.pop(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
