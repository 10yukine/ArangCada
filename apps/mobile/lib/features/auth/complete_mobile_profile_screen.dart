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
  String? _phoneError;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Local format (0917 123 4567), the way people type and read it.
    final current = normalizePhMobile(
      ref.read(demoStateProvider).currentUser?.mobileNumber,
    );
    _phone.text = current.isValid ? current.display : '';
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
      setState(() => _phoneError = phone.error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _phoneError = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPhoneOtp(phone.e164!);
      if (mounted) context.go('/verify-phone');
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _phoneError = error.message);
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
    // A number already on file means the user came from the code screen to
    // correct it; back returns there instead of signing them out.
    final changing =
        user.mobileNumber != null && user.mobileNumber!.trim().isNotEmpty;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        changing ? context.go('/verify-phone') : _signOut();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(changing ? 'Change number' : 'Set up mobile access'),
          automaticallyImplyLeading: false,
          leading: changing
              ? IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _busy ? null : () => context.go('/verify-phone'),
                )
              : null,
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
                          : changing
                          ? 'Fix your mobile number'
                          : 'Add your mobile number',
                      style: AppTypography.h2,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      user.isAdminAccount
                          ? 'Add and verify your mobile number to book rides with this account. Your website admin access stays the same.'
                          : changing
                          ? 'Correct the number below and we will text a new code. Everything else you entered is kept.'
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
                        errorText: _phoneError,
                        onChanged: (_) => setState(() => _phoneError = null),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'We’ll send a 6-digit code to verify this number.',
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
