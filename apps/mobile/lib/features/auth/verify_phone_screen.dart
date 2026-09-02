import 'dart:async';
import 'dart:math' as math;

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

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen>
    with SingleTickerProviderStateMixin {
  static const _codeLength = 6;

  /// The app's emphasized easing. Motion decelerates into place rather than
  /// easing symmetrically, so a correction reads as settling, not bouncing.
  static const _emphasized = Cubic(0.2, 0, 0, 1);

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

  /// A wrong code already turns the cells red and prints a message. The shake
  /// is the third channel, not the only one -- motion must never be the sole
  /// carrier of a state change, because it is over before a distracted user
  /// looks back at the screen.
  late final AnimationController _shake;

  /// Set the instant a code is accepted, so the checkmark can play while the
  /// router redirect resolves. Without it the screen sits on 'Checking...'
  /// and the one moment worth confirming passes invisibly.
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // Pinput drives the controller, but nothing else rebuilds this screen when
    // the text changes, so the Verify button stayed disabled even on six
    // typed digits until some unrelated setState happened to fire.
    _pinController.addListener(_onPinChanged);
    // The code was already sent by the sign-up flow, so the cooldown starts
    // immediately rather than after the first resend. Otherwise the user sees
    // an enabled Resend button that the server will reject.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _shake.dispose();
    _pinController.removeListener(_onPinChanged);
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  void _onPinChanged() {
    if (mounted) setState(() {});
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
      if (mounted) setState(() => _verified = true);
    } on DemoAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        // Clear the field so the user retypes rather than editing six wrong
        // digits one at a time.
        _pinController.clear();
      });
      unawaited(HapticFeedback.mediumImpact());
      _shake.forward(from: 0);
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

  /// Two states, one shape. The circle is the only thing on the screen that
  /// changes when the code is accepted, so it carries the confirmation while
  /// the router redirect resolves.
  Widget _statusBadge() {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: _emphasized,
        switchOutCurve: _emphasized,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          // 0.25 to 1. Starting nearer zero reads as a pop rather than an
          // arrival, and a scale is cheaper to composite than a size change.
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.25, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: Container(
          key: ValueKey<bool>(_verified),
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _verified ? AppColors.greenFill : AppColors.primaryFill,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _verified ? Icons.check_rounded : Icons.sms_outlined,
            size: 32,
            color: _verified ? AppColors.green : AppColors.primaryText,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    final masked = phone == null
        ? 'your mobile number'
        : normalizePhMobile(phone).masked;

    // The pin row is the one thing on this screen that cannot wrap. Six fixed
    // 48 px cells plus their separators overflow a 320 dp handset once the
    // screen margins are taken out, and a fixed 56 px height clips the digit
    // at the app's 1.3x text-scale ceiling. Both now follow what is actually
    // available (CLAUDE.md rule 11).
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final cellHeight = (56.0 * textScale).clamp(56.0, 76.0);

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
              _statusBadge(),
              const SizedBox(height: AppSpacing.lg),
              Text(
                _verified ? 'Number verified' : 'Enter the 6-digit code',
                style: AppTypography.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _verified
                    ? 'Taking you to ArangCada.'
                    : 'We sent it by SMS to $masked.',
                style: AppTypography.bodySm.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),

              LayoutBuilder(
                builder: (context, constraints) {
                  const gap = AppSpacing.xs;
                  final cellWidth =
                      ((constraints.maxWidth - gap * (_codeLength - 1)) /
                              _codeLength)
                          .clamp(38.0, 52.0);
                  final defaultPinTheme = PinTheme(
                    width: cellWidth,
                    height: cellHeight,
                    textStyle: AppTypography.h2.copyWith(color: AppColors.ink),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(AppRadii.input),
                      border: Border.all(color: AppColors.border),
                    ),
                  );

                  return AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) {
                      // Damped sine: three passes that decay to nothing, so
                      // the row settles rather than stopping mid-swing.
                      final t = _shake.value;
                      final dx =
                          math.sin(t * math.pi * 3) * 8 * (1 - t);
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: child,
                      );
                    },
                    child: Pinput(
                      length: _codeLength,
                      controller: _pinController,
                      focusNode: _pinFocus,
                      autofocus: true,
                      enabled: !_busy && !_verified,
                      defaultPinTheme: defaultPinTheme,
                      separatorBuilder: (index) =>
                          const SizedBox(width: gap),
                      focusedPinTheme: defaultPinTheme.copyWith(
                        decoration: defaultPinTheme.decoration!.copyWith(
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                      ),
                      submittedPinTheme: _verified
                          ? defaultPinTheme.copyWith(
                              decoration: defaultPinTheme.decoration!
                                  .copyWith(
                                    color: AppColors.greenFill,
                                    border: Border.all(color: AppColors.green),
                                  ),
                            )
                          : defaultPinTheme,
                      errorPinTheme: defaultPinTheme.copyWith(
                        decoration: defaultPinTheme.decoration!.copyWith(
                          color: AppColors.dangerFill,
                          border: Border.all(color: AppColors.dangerBorder),
                        ),
                      ),
                      forceErrorState: _error != null,
                      keyboardType: TextInputType.number,
                      // No smsRetriever: pinput 6 wants a SmsRetriever
                      // implementation backed by another package (smart_auth)
                      // for automatic SMS pickup. Not worth a dependency here
                      // -- Pinput's default autofillHints already include
                      // oneTimeCode, which is Android's
                      // AUTOFILL_HINT_SMS_OTP_CODE, so the keyboard offers the
                      // code from the notification, and the Paste button below
                      // covers the rest.
                      onCompleted: _submit,
                    ),
                  );
                },
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
                label: _verified
                    ? 'Verified'
                    : (_busy ? 'Checking...' : 'Verify'),
                onPressed:
                    _busy ||
                        _verified ||
                        _pinController.text.length < _codeLength
                    ? null
                    : () => _submit(_pinController.text),
              ),

              // Paste and Resend belong to the Verify action, so they sit one
              // small gap from it. The account-level escape hatch below is a
              // different group, so it gets a gap twice as large. Space does
              // the grouping now; the Divider that used to attempt it is gone
              // (a line where space would do reads as structure that is not
              // there).
              const SizedBox(height: AppSpacing.xs),
              TextButton.icon(
                onPressed: _busy || _verified ? null : _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_outlined, size: 18),
                label: const Text('Paste code'),
              ),

              // A countdown is not a control. Rendering it as a disabled
              // button invited a tap that could never work; while it runs it
              // is plain text, and the button only exists once it is pressable.
              if (_secondsLeft > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    'Resend code in ${_secondsLeft}s',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                TextButton(
                  onPressed: _busy || _verified ? null : _resend,
                  child: const Text('Resend code'),
                ),

              const SizedBox(height: AppSpacing.xxl),

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
              const SizedBox(height: AppSpacing.xxs),
              TextButton(
                onPressed: _busy || _verified ? null : _signOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
