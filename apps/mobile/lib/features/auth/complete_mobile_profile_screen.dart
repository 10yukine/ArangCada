import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/ph_mobile.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';

/// Completes contact setup on an authenticated existing account.
class CompleteMobileProfileScreen extends ConsumerStatefulWidget {
  const CompleteMobileProfileScreen({super.key});

  @override
  ConsumerState<CompleteMobileProfileScreen> createState() =>
      _CompleteMobileProfileScreenState();
}

class _CompleteMobileProfileScreenState
    extends ConsumerState<CompleteMobileProfileScreen> {
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phone.text = ref.read(demoStateProvider).currentUser?.mobileNumber ?? '';
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    final phone = normalizePhMobile(_phone.text);
    if (!phone.isValid) {
      setState(() => _error = phone.error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPhoneOtp(phone.e164!);
      if (mounted) context.go('/verify-phone');
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the code. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
      if (mounted) context.go('/login');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not sign out. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(demoStateProvider).currentUser;
    if (user == null) return const Scaffold();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _signOut();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Set up mobile access'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.phone_android_outlined,
                      size: 48,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      user.isAdminAccount
                          ? 'Your admin account already exists'
                          : 'Add your mobile number',
                      style: AppTypography.h2,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      user.isAdminAccount
                          ? 'Add and verify your mobile number to book rides with this account. Your website admin access stays the same.'
                          : 'Verify a mobile number to start using your existing account.',
                      style: AppTypography.bodySm,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Name', style: AppTypography.label),
                    const SizedBox(height: AppSpacing.xs),
                    SelectableText(user.displayName),
                    const SizedBox(height: AppSpacing.md),
                    Text('Email', style: AppTypography.label),
                    const SizedBox(height: AppSpacing.xs),
                    SelectableText(user.email),
                    const SizedBox(height: AppSpacing.lg),
                    AutofillGroup(
                      child: LabeledTextField(
                        label: 'Mobile number',
                        controller: _phone,
                        icon: Icons.phone_outlined,
                        hintText: '09XX XXX XXXX',
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _sendCode(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'We’ll send a 6-digit SMS code to verify this number.',
                      style: AppTypography.bodySm,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    ArangButton(
                      label: _busy ? 'Please wait…' : 'Send verification code',
                      onPressed: _busy ? null : _sendCode,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: _busy ? null : _signOut,
                      child: const Text('Sign out'),
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
