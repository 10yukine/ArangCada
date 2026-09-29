import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

import '../../app/theme/app_typography.dart';

/// Rules for every new password (sign-up, reset, change). Existing passwords
/// are never re-checked, so accounts made before these rules still log in.
/// The same rules are enforced by Supabase Auth (password requirements).
final _upper = RegExp('[A-Z]');
final _lower = RegExp('[a-z]');
final _digit = RegExp('[0-9]');

bool _longEnough(String p) => p.length >= 8;
bool _mixedCase(String p) => _upper.hasMatch(p) && _lower.hasMatch(p);
bool _hasNumber(String p) => _digit.hasMatch(p);

/// The first unmet rule as an error line, or null when the password is fine.
String? passwordProblem(String password) {
  if (password.isEmpty) return 'Create a password';
  if (!_longEnough(password)) return 'Use at least 8 characters';
  if (!_mixedCase(password)) return 'Use both uppercase and lowercase letters';
  if (!_hasNumber(password)) return 'Add at least one number';
  return null;
}

/// Live checklist under a new-password field: each rule turns into a green
/// tick the moment the typed password meets it. Pass [repeat] to add a
/// "Both passwords match" row.
class PasswordRequirements extends StatelessWidget {
  const PasswordRequirements({required this.password, this.repeat, super.key});

  final TextEditingController password;
  final TextEditingController? repeat;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([password, ?repeat]),
      builder: (context, _) {
        final value = password.text;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Requirement(
              met: _longEnough(value),
              label: 'At least 8 characters',
            ),
            _Requirement(
              met: _mixedCase(value),
              label: 'Uppercase and lowercase letters',
            ),
            _Requirement(met: _hasNumber(value), label: 'At least one number'),
            if (repeat case final repeat?)
              _Requirement(
                met: repeat.text.isNotEmpty && repeat.text == value,
                label: 'Both passwords match',
              ),
          ],
        );
      },
    );
  }
}

class _Requirement extends StatelessWidget {
  const _Requirement({required this.met, required this.label});

  final bool met;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.green : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Semantics(
        label: '$label, ${met ? 'done' : 'not yet'}',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: AppMotion.button,
              child: Icon(
                met ? Icons.check_circle : Icons.radio_button_unchecked,
                key: ValueKey(met),
                size: 16,
                color: color,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: AppTypography.caption.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
