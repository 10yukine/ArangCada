import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  const VerifyPhoneScreen({this.initialError, super.key});

  /// Why the code that sign-up tried to send never went out.
  ///
  /// Registration deliberately treats a failed send as non-fatal -- the account
  /// already exists, so bouncing back to the form would orphan it -- but it
  /// then set the message on a screen it immediately navigated away from, so
  /// the reason was destroyed on the way here. The user landed on a screen
  /// saying "We sent it by SMS" when nothing had been sent, and the only clue
  /// was a 60-second wait for a Resend button.
  final String? initialError;

  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen>
    with SingleTickerProviderStateMixin {
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
    _error = widget.initialError;
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

  /// Leaves verification and returns to the registration form.
  ///
  /// Signing out first is not optional today: this screen is only reachable
  /// once the account exists and is signed in, so without ending the session
  /// the router's verification gate redirects straight back here. `/signup` is
  /// an auth path, so a signed-out user is allowed to land on it.
  ///
  /// Once registration defers account creation until the code is accepted
  /// (specs.md Spec 10) there is no session to end and this becomes a plain
  /// pop. Written as sign-out-then-navigate so it behaves correctly either way.
  Future<void> _goBack() async {
    if (_busy) return;
    setState(() => _busy = true);

    final auth = ref.read(authRepositoryProvider);
    try {
      // Delete first, sign out second. Deleting needs the session that names
      // the account, so signing out first would leave the row behind with no
      // way for this device to reach it again -- the exact orphan this button
      // exists to prevent.
      await auth.abandonUnverifiedRegistration();
    } on Exception {
      // Deliberately swallowed. If the delete fails -- offline, or the account
      // turned out to be verified after all -- the user must still be able to
      // leave this screen. A stranded user is worse than a stray row, and the
      // hourly sweep collects the row anyway.
    }

    try {
      await auth.signOut();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        context.go('/signup');
      }
    }
  }

  /// A static circle. This briefly cross-faded to a green checkmark on success,
  /// which was pointless: the router redirect fires the moment
  /// needsPhoneVerification flips, so the app is already on the dashboard
  /// before a 300ms animation can finish. Landing on the dashboard IS the
  /// confirmation. Removed rather than slowed down, because delaying a correct
  /// login to show a tick is a worse trade than showing nothing.
  Widget _statusBadge() {
    return const Center(
      child: SizedBox.square(
        dimension: 72,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primaryFill,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.sms_outlined,
            size: 32,
            color: AppColors.primaryText,
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
                'Enter the 6-digit code',
                style: AppTypography.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'We sent it by SMS to $masked.',
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
                      // code straight from the notification. A dedicated Paste
                      // button used to sit below; it was removed because long
                      // pressing the field already gives the platform's own
                      // paste affordance, and the app reading the clipboard
                      // unprompted is worse than the user choosing to.
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
                label: _busy || _verified ? 'Checking...' : 'Verify',
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

              // A typo in the mobile number would otherwise strand the account:
              // the code goes to a number the user does not hold, and there is
              // no other way back. This is that way back, and it returns to
              // registration rather than to a login screen -- there is nothing
              // to log in to yet.
              Text(
                'Using the wrong number?',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxs),
              TextButton(
                onPressed: _busy || _verified ? null : _goBack,
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
