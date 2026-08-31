import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/ph_mobile.dart';
import '../../core/widgets/arang_ui.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';

/// Holds a newly registered account until a 6-digit SMS code proves the user
/// controls the mobile number they typed.
///
/// Decided with Calamba City Hall context on 31 Aug 2026: a Filipino holds one
/// or two SIMs but can create unlimited email addresses, so the SIM is the
/// stronger anti-fraud anchor. Gating on it raises the cost of a fake booking.
///
/// This screen is a **convenience gate**. The real enforcement is server-side:
/// `request_ride`, `can_driver_go_online` and `create_ride_share_link` each
/// refuse an unverified account, so a tampered client that skips this screen
/// still cannot book, drive, or share a link (CLAUDE.md rule 6).
class VerifyPhoneScreen extends ConsumerStatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen> {
  static const _codeLength = 6;

  /// Matches `record_otp_send()`'s 60-second server-side rule. The countdown is
  /// a courtesy so the user is not invited to press a button that will be
  /// refused; it is not the throttle itself.
  static const _resendCooldown = Duration(seconds: 60);

  final _pinController = TextEditingController();
  final _pinFocus = FocusNode();

  bool _busy = false;
  String? _error;
  String? _notice;
  int _secondsLeft = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // The code was already sent by the sign-up flow, so the cooldown starts
    // immediately rather than after the first resend. Otherwise the user sees
    // an enabled Resend button that the server will reject.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _resendCooldown.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  String? get _phone => ref.read(demoStateProvider).currentUser?.mobileNumber;

  Future<void> _submit(String code) async {
    final phone = _phone;
    if (phone == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .verifyPhoneOtp(e164Phone: phone, token: code);
      // No navigation here. The router redirect watches DemoState and moves the
      // user to their role home once needsPhoneVerification flips false.
      // Navigating manually as well would race the redirect.
    } on DemoAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        // Clear the field so the user retypes rather than editing six wrong
        // digits one at a time.
        _pinController.clear();
      });
      _pinFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final phone = _phone;
    if (phone == null || _busy || _secondsLeft > 0) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await ref.read(authRepositoryProvider).sendPhoneOtp(phone);
      if (!mounted) return;
      setState(() => _notice = 'A new code is on its way.');
      _startCooldown();
    } on DemoAuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Android shows the code in the notification shade, and copying it is often
  /// faster than memorising six digits and switching back. Reading the
  /// clipboard on an explicit tap keeps that convenient without the app
  /// silently inspecting clipboard contents.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (!mounted) return;

    if (digits.length < _codeLength) {
      setState(() => _error = 'No 6-digit code found on the clipboard.');
      return;
    }

    // Take the first six digits: an SMS body carries prose around the code.
    final code = digits.substring(0, _codeLength);
    _pinController.text = code;
    setState(() => _error = null);
    await _submit(code);
  }

  Future<void> _signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    final masked = phone == null
        ? 'your mobile number'
        : normalizePhMobile(phone).masked;

    final defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: AppTypography.h2.copyWith(color: AppColors.ink),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: AppColors.border),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.screenBackground,
      appBar: AppBar(
        title: const Text('Verify your number'),
        backgroundColor: AppColors.screenBackground,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.md),
              const Icon(
                Icons.sms_outlined,
                size: 48,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Enter the 6-digit code',
                style: AppTypography.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'We sent it by SMS to $masked.',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),

              Pinput(
                length: _codeLength,
                controller: _pinController,
                focusNode: _pinFocus,
                autofocus: true,
                enabled: !_busy,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: defaultPinTheme.copyWith(
                  decoration: defaultPinTheme.decoration!.copyWith(
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                ),
                errorPinTheme: defaultPinTheme.copyWith(
                  decoration: defaultPinTheme.decoration!.copyWith(
                    color: AppColors.dangerFill,
                    border: Border.all(color: AppColors.dangerBorder),
                  ),
                ),
                forceErrorState: _error != null,
                keyboardType: TextInputType.number,
                // No smsRetriever: pinput 6 wants a SmsRetriever implementation
                // backed by another package (smart_auth) for automatic SMS
                // pickup. Not worth a dependency here -- Pinput's default
                // autofillHints already include oneTimeCode, so the Android
                // keyboard offers the code from the notification, and the
                // Paste button below covers the rest.
                onCompleted: _submit,
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: AppTypography.bodySm.copyWith(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ],
              if (_notice != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _notice!,
                  style: AppTypography.bodySm.copyWith(color: AppColors.green),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              ArangButton(
                label: _busy ? 'Checking…' : 'Verify',
                onPressed: _busy || _pinController.text.length < _codeLength
                    ? null
                    : () => _submit(_pinController.text),
              ),

              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: _busy ? null : _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_outlined, size: 18),
                label: const Text('Paste code'),
              ),

              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: (_busy || _secondsLeft > 0) ? null : _resend,
                child: Text(
                  _secondsLeft > 0
                      ? 'Resend code in ${_secondsLeft}s'
                      : 'Resend code',
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              const Divider(color: AppColors.dividerLight),
              const SizedBox(height: AppSpacing.xs),

              // A typo in the mobile number would otherwise strand the account
              // permanently: the code goes to a number the user does not hold,
              // and there is no other way back. Signing out returns them to
              // registration.
              Text(
                'Wrong number? Sign out and register again with the correct '
                'one.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _busy ? null : _signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
