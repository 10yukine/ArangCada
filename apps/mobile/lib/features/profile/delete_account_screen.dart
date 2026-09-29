import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';

/// Deletes the signed-in account for good (Google Play account-deletion
/// requirement). The password is checked by the account-deletion edge
/// function, which signs in with it before deleting anything; the same
/// function backs arangcada.app/delete-account for people without the app.
typedef AccountDeleter = Future<void> Function(String password);

final accountDeleterProvider = Provider<AccountDeleter>(
  (ref) => (password) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    final identifier = (user?.email?.isNotEmpty ?? false)
        ? user!.email
        : user?.phone;
    if (identifier == null || identifier.isEmpty) {
      throw const DemoAuthException('Sign in again to continue.');
    }
    try {
      await client.functions.invoke(
        'account-deletion',
        body: {'identifier': identifier, 'password': password},
      );
    } on FunctionException catch (error) {
      final details = error.details;
      throw DemoAuthException(
        error.status == 401
            ? 'That password is incorrect.'
            : (details is Map ? details['error'] as String? : null) ??
                  'Your account could not be deleted. Try again.',
      );
    } catch (_) {
      throw const DemoAuthException(
        'Could not reach ArangCada. Check your connection and try again.',
      );
    }
  },
);

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _deleting = false;
  String? _passwordError;
  // Reasons not about the password, e.g. a ride in progress.
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_deleting) return;
    if (_password.text.isEmpty) {
      setState(() => _passwordError = 'Enter your password');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _deleting = true;
      _error = null;
      _passwordError = null;
    });
    try {
      await ref.read(accountDeleterProvider)(_password.text);
    } on DemoAuthException catch (error) {
      if (mounted) {
        setState(() {
          _deleting = false;
          if (error.message.contains('password')) {
            _passwordError = error.message;
          } else {
            _error = error.message;
          }
        });
      }
      return;
    }
    // The account no longer exists, so the server-side sign-out may fail;
    // the local session is cleared regardless.
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {}
    ref.read(chatRepositoryProvider).clearSession();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Your account was deleted.')));
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    Widget point(String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: AppTypography.body),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.screenBackground,
      appBar: AppBar(
        title: const Text('Delete account'),
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
                  Text('Deleted right away', style: AppTypography.h2),
                  point('Your account and sign-in'),
                  point('Your name, photo, email and mobile number'),
                  point('Discount claims and ID photos'),
                  point('Your chat messages and voice notes'),
                  point('Driver record and documents, if you drive'),
                  const SizedBox(height: AppSpacing.md),
                  Text('Kept without your name', style: AppTypography.h2),
                  point(
                    'Past trips, ratings, complaints and SOS reports, for the '
                    'periods in our Privacy Policy. They can no longer be '
                    'linked to you.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'This cannot be undone.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.dangerDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledTextField(
                    label: 'Password',
                    hintText: 'Enter your password to confirm',
                    controller: _password,
                    icon: Icons.lock_outline,
                    obscureText: _obscure,
                    onSubmitted: (_) => _delete(),
                    errorText: _passwordError,
                    onChanged: (_) => setState(() => _passwordError = null),
                    autofillHints: const [AutofillHints.password],
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
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  ArangButton(
                    label: _deleting ? 'Deleting...' : 'Delete my account',
                    variant: ArangButtonVariant.dangerGhost,
                    icon: Icons.delete_outline,
                    onPressed: _deleting ? null : _delete,
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
