import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/ph_mobile.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';

/// Account details: name, mobile number, and email, all editable directly on
/// this one screen -- the owner's explicit call (Spec 11 revision, 5 Sep
/// 2026) is that neither contact field gets its own page. Password lives on
/// the Settings screen instead (`profile_detail_screens.dart`), reachable
/// from the profile tab, not from here.
///
/// Name needs no password: it is low-risk and self-correcting, and gating it
/// behind a credential trains users to type their password into any box that
/// asks. Mobile number and email both DO require the current password first
/// -- `updateUser` neither checks it nor is guarded by RLS, so re-authenticating
/// is the only thing standing between an unlocked, still-signed-in phone and a
/// changed identity.
///
/// A mobile number change still needs its SMS code accepted before it takes
/// effect (Supabase's phone-change flow has no other way), so that step
/// happens right here too, as an inline card, rather than a second screen.
/// Email has no such step: `mailer_autoconfirm` applies it immediately, and
/// the owner decided that trade is worth it so a mistyped sign-up address is
/// recoverable rather than a dead end.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  // PROFILE
  late final TextEditingController _name;
  bool _savingName = false;
  String? _nameError;
  String? _nameSaveError;

  // CONTACT
  late final TextEditingController _mobile;
  late final TextEditingController _email;
  final _contactPassword = TextEditingController();
  bool _savingContact = false;
  String? _contactError;

  /// Set once `sendPhoneOtp` succeeds for a changed number. Non-null shows
  /// the inline "enter the code" card in place of the Save button.
  String? _pendingPhoneE164;
  final _otpCode = TextEditingController();
  bool _verifyingOtp = false;
  String? _otpError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(demoStateProvider).currentUser;
    _name = TextEditingController(text: user?.displayName ?? '');
    _mobile = TextEditingController(
      text: user?.mobileNumber == null
          ? ''
          : normalizePhMobile(user!.mobileNumber).display,
    );
    _email = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _contactPassword.dispose();
    _otpCode.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    if (_savingName) return;

    // Validated here rather than through a FormField: LabeledTextField is a
    // presentation widget with an errorText slot, not a FormField, and wrapping
    // the app's own field in a Form to gain a validator would mean maintaining
    // two ways of showing the same error.
    final trimmed = _name.text.trim();
    final invalid = trimmed.isEmpty
        ? 'Enter your name'
        : trimmed.length < 2
        ? 'That name looks too short'
        : null;
    if (invalid != null) {
      setState(() => _nameError = invalid);
      return;
    }

    setState(() {
      _savingName = true;
      _nameSaveError = null;
      _nameError = null;
    });

    try {
      await ref.read(authRepositoryProvider).updateDisplayName(_name.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name updated.')));
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _nameSaveError = error.message);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _saveContact() async {
    if (_savingContact) return;
    final user = ref.read(demoStateProvider).currentUser;

    final trimmedEmail = _email.text.trim();
    final emailChanged = trimmedEmail != (user?.email ?? '');
    if (emailChanged && !trimmedEmail.contains('@')) {
      setState(() => _contactError = 'Enter a valid email address.');
      return;
    }

    PhMobileNumber? mobile;
    var mobileChanged = false;
    if (_mobile.text.trim().isNotEmpty) {
      mobile = normalizePhMobile(_mobile.text);
      if (!mobile.isValid) {
        setState(() => _contactError = mobile!.error);
        return;
      }
      mobileChanged = mobile.e164 != user?.mobileNumber;
    }

    if (!emailChanged && !mobileChanged) return;

    if (_contactPassword.text.isEmpty) {
      setState(() => _contactError = 'Enter your current password.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _savingContact = true;
      _contactError = null;
    });

    final auth = ref.read(authRepositoryProvider);
    try {
      // Proves the person is the account owner, not just the phone's holder.
      // A wrong current password fails HERE, with a message the user can act
      // on -- never a generic error.
      await auth.reauthenticate(_contactPassword.text);

      if (emailChanged) {
        await auth.updateEmail(trimmedEmail);
      }
      if (mobileChanged) {
        await auth.sendPhoneOtp(mobile!.e164!);
      }

      if (!mounted) return;
      _contactPassword.clear();
      if (mobileChanged) {
        setState(() => _pendingPhoneE164 = mobile!.e164);
      }
      if (emailChanged) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Email updated.')));
      }
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _contactError = error.message);
    } finally {
      if (mounted) setState(() => _savingContact = false);
    }
  }

  Future<void> _verifyPendingPhone() async {
    final phone = _pendingPhoneE164;
    if (phone == null || _verifyingOtp) return;

    setState(() {
      _verifyingOtp = true;
      _otpError = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .verifyPhoneOtp(e164Phone: phone, token: _otpCode.text.trim());
      if (!mounted) return;
      setState(() {
        _pendingPhoneE164 = null;
        _otpCode.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mobile number updated.')));
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _otpError = error.message);
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  /// Cancelling needs no server call: GoTrue keeps the old confirmed number in
  /// `auth.users.phone` and parks the claimed one in `new_phone` until the
  /// code is accepted, so nothing was ever committed.
  void _cancelPendingPhone() {
    setState(() {
      _pendingPhoneE164 = null;
      _otpCode.clear();
      _otpError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBackground,
      appBar: AppBar(
        title: const Text('Account details'),
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
                    label: 'Full Name',
                    controller: _name,
                    icon: Icons.person_outline,
                    hintText: 'Juan dela Cruz',
                    textInputAction: TextInputAction.done,
                    errorText: _nameError,
                    onSubmitted: (_) => _saveName(),
                  ),
                  if (_nameSaveError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _nameSaveError!,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  ArangButton(
                    label: _savingName ? 'Saving...' : 'Save name',
                    onPressed: _savingName ? null : _saveName,
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledTextField(
                    label: 'Mobile Number',
                    controller: _mobile,
                    icon: Icons.phone_outlined,
                    hintText: '0917 123 4567',
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LabeledTextField(
                    label: 'Email Address',
                    controller: _email,
                    icon: Icons.mail_outline,
                    hintText: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LabeledTextField(
                    label: 'Current Password',
                    controller: _contactPassword,
                    icon: Icons.lock_outline,
                    hintText: 'Enter your password',
                    obscureText: true,
                    onSubmitted: (_) => _saveContact(),
                  ),
                  if (_contactError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _contactError!,
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  ArangButton(
                    label: _savingContact ? 'Saving...' : 'Save contact info',
                    onPressed: _savingContact ? null : _saveContact,
                  ),

                  if (_pendingPhoneE164 != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const Divider(color: AppColors.dividerLight),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Enter the 6-digit code sent to your new number',
                      style: AppTypography.label,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LabeledTextField(
                      label: 'Code',
                      controller: _otpCode,
                      icon: Icons.sms_outlined,
                      hintText: '123456',
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _verifyPendingPhone(),
                    ),
                    if (_otpError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _otpError!,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: ArangButton(
                            label: _verifyingOtp ? 'Checking...' : 'Verify',
                            onPressed: _verifyingOtp
                                ? null
                                : _verifyPendingPhone,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ArangButton(
                            label: 'Cancel',
                            variant: ArangButtonVariant.ghost,
                            onPressed: _verifyingOtp
                                ? null
                                : _cancelPendingPhone,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
