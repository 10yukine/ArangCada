import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

/// "New Commuter? Sign Up" / "Already have an account? Log In" -- plain
/// text question plus an accent-colored action word, matching the
/// prototype exactly. Shared so login and sign-up can't drift into two
/// different link styles for the same pattern.
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    required this.question,
    required this.actionLabel,
    required this.onTap,
    super.key,
  });

  final String question;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
        ),
        child: RichText(
          text: TextSpan(
            style: AppTypography.body.copyWith(color: AppColors.textRow),
            children: [
              TextSpan(text: '$question '),
              TextSpan(
                text: actionLabel,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder legal notice for the bottom of an auth screen.
///
/// Explicitly a placeholder: no real Terms of Service or Privacy Policy
/// content exists yet -- that is deliberately out of scope for this pass.
/// Tapping either link is honest about that instead of opening a page that
/// doesn't exist, matching how the rest of this app handles not-yet-built
/// destinations.
class AuthLegalNotice extends StatelessWidget {
  const AuthLegalNotice({required this.actionVerb, super.key});

  /// "Logging in" or "Creating an account" -- keeps the sentence accurate
  /// to which screen it's on rather than a single generic phrase.
  final String actionVerb;

  void _showPlaceholder(BuildContext context, String document) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$document is a placeholder for this academic prototype -- not '
          'written yet.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: AppTypography.caption.copyWith(height: 1.5),
          children: [
            TextSpan(text: 'By $actionVerb, you agree to ArangCada\'s '),
            TextSpan(
              text: 'Terms of Service',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
              recognizer:
                  (TapGestureRecognizer()
                    ..onTap = () => _showPlaceholder(context, 'Terms of Service')),
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
              recognizer:
                  (TapGestureRecognizer()
                    ..onTap = () => _showPlaceholder(context, 'Privacy Policy')),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}
