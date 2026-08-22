import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/demo_user.dart';
import '../../core/widgets/arang_dialog.dart';

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
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _password.dispose();
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
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _mobile,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newUsername],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: 'At least 8 characters',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _error!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.danger),
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
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Driver accounts are activated with an enrollment code issued by a TODA or LGU administrator. Drivers do not sign up here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
