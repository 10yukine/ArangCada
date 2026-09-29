import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/password_requirements.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';

/// Changes the signed-in account's password.
///
/// Supabase's `updateUser(password:)` does not verify the existing password at
/// all -- it changes it on the strength of the session alone. Without
/// re-authentication first, anyone holding an unlocked phone could take the
/// account, which would make the app weaker than the platform default. So
/// this screen always replays `signInWithPassword` against the current
/// password before calling `updateUser`, and a wrong current password fails
/// at that first step with a message the user can act on. See
/// .pipeline/specs.md Spec 11 §1.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _obscureRepeat = true;
  bool _saving = false;
  final _errors = <String, String>{};

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    setState(() {
      _errors.clear();
      if (_current.text.isEmpty) {
        _errors['current'] = 'Enter your current password';
      }
      final problem = passwordProblem(_next.text);
      if (problem != null) {
        _errors['next'] = problem;
      } else if (_next.text == _current.text) {
        _errors['next'] = 'That is already your password';
      }
      if (_repeat.text.isEmpty) {
        _errors['repeat'] = 'Enter the new password again';
      } else if (_repeat.text != _next.text) {
        _errors['repeat'] = 'Passwords do not match';
      }
    });
    if (_errors.isNotEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final auth = ref.read(authRepositoryProvider);
    try {
      // Step 1 proves the person is the account owner, not just the phone's
      // holder. A wrong current password fails HERE, never at step 2.
      try {
        await auth.reauthenticate(_current.text);
      } on DemoAuthException catch (error) {
        if (mounted) setState(() => _errors['current'] = error.message);
        return;
      }
      await auth.updatePassword(_next.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
      context.pop();
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _errors['next'] = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBackground,
      appBar: AppBar(
        title: const Text('Change password'),
        backgroundColor: AppColors.screenBackground,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledTextField(
                    label: 'Current password',
                    hintText: 'Enter your current password',
                    controller: _current,
                    icon: Icons.lock_outline,
                    obscureText: _obscureCurrent,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.password],
                    errorText: _errors['current'],
                    onChanged: (_) => setState(() => _errors.remove('current')),
                    suffixIcon: _visibilityToggle(
                      obscured: _obscureCurrent,
                      onPressed: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LabeledTextField(
                    label: 'New password',
                    hintText: 'Create a new password',
                    controller: _next,
                    icon: Icons.lock_outline,
                    obscureText: _obscureNext,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    errorText: _errors['next'],
                    onChanged: (_) => setState(() => _errors.remove('next')),
                    suffixIcon: _visibilityToggle(
                      obscured: _obscureNext,
                      onPressed: () =>
                          setState(() => _obscureNext = !_obscureNext),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LabeledTextField(
                    label: 'Repeat new password',
                    hintText: 'Re-enter your new password',
                    controller: _repeat,
                    icon: Icons.lock_outline,
                    obscureText: _obscureRepeat,
                    onSubmitted: (_) => _save(),
                    autofillHints: const [AutofillHints.newPassword],
                    errorText: _errors['repeat'],
                    onChanged: (_) => setState(() => _errors.remove('repeat')),
                    suffixIcon: _visibilityToggle(
                      obscured: _obscureRepeat,
                      onPressed: () =>
                          setState(() => _obscureRepeat = !_obscureRepeat),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  PasswordRequirements(password: _next, repeat: _repeat),
                  const SizedBox(height: AppSpacing.lg),
                  ArangButton(
                    label: _saving ? 'Saving...' : 'Save',
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
