import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/ph_mobile.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/labeled_text_field.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';

/// Lets a commuter change the one thing they are actually allowed to change.
///
/// Everything else on this screen is deliberately read-only, and says why. That
/// is not a placeholder: `profiles` grants UPDATE on exactly
/// (display_name, phone) to `authenticated`, and
/// guard_profiles_privileged_columns() rejects role or status changes outright.
/// Offering an editable field the database would refuse is worse than showing
/// none -- the user fills it in, taps Save, and learns nothing about why it did
/// not take.
///
/// Email and mobile number are shown because seeing them is the common reason
/// for opening this screen at all ("which address did I sign up with?").
/// Changing either is a separate job with its own verification: a new number
/// re-enters the SMS flow, and a new email needs working SMTP, which this
/// project does not have yet.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _name;

  bool _saving = false;
  String? _error;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: ref.read(demoStateProvider).currentUser?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

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
      _saving = true;
      _error = null;
      _nameError = null;
    });

    try {
      await ref.read(authRepositoryProvider).updateDisplayName(_name.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name updated.')));
      context.pop();
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(demoStateProvider).currentUser;
    final mobile = user?.mobileNumber;

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
              LabeledTextField(
                label: 'Full Name',
                controller: _name,
                icon: Icons.person_outline,
                hintText: 'Juan dela Cruz',
                textInputAction: TextInputAction.done,
                errorText: _nameError,
                onSubmitted: (_) => _save(),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: AppTypography.bodySm.copyWith(color: AppColors.danger),
                ),
              ],

              const SizedBox(height: AppSpacing.lg),
              ArangButton(
                label: _saving ? 'Saving...' : 'Save',
                onPressed: _saving ? null : _save,
              ),

              const SizedBox(height: AppSpacing.xl),
              Text(
                'Not editable here',
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ReadOnlyRow(
                      icon: Icons.mail_outline,
                      label: 'Email address',
                      value: user?.email ?? '-',
                      reason:
                          'Changing this needs a confirmation sent to both '
                          'addresses.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ReadOnlyRow(
                      icon: Icons.phone_outlined,
                      label: 'Mobile number',
                      // Masked, not shown in full. Rule 10 -- and the user
                      // already knows their own number; what they need here is
                      // enough to recognise which one is on the account.
                      value: mobile == null
                          ? '-'
                          : normalizePhMobile(mobile).masked,
                      reason:
                          'Changing this sends a new 6-digit code to the new '
                          'number.',
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

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.reason,
  });

  final IconData icon;
  final String label;
  final String value;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              Text(value, style: AppTypography.body),
              const SizedBox(height: 2),
              Text(
                reason,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
