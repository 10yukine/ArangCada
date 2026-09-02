import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
/// Temporarily launches placeholder URLs (e.g. arangcada.ph/tos) until the 
/// legal pages are fully integrated into the app.
class AuthLegalNotice extends StatelessWidget {
  const AuthLegalNotice({
    this.actionVerb,
    this.prefixText,
    super.key,
  }) : assert(actionVerb != null || prefixText != null);

  /// "Logging in" or "Creating an account"
  final String? actionVerb;
  
  /// "I agree to the "
  final String? prefixText;

  void _launchURL(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch browser')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch browser')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefix = prefixText ?? 'By $actionVerb, you agree to ArangCada\'s ';
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: AppTypography.caption.copyWith(height: 1.5),
          children: [
            TextSpan(text: prefix),
            TextSpan(
              text: 'Terms of Service',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
              recognizer:
                  (TapGestureRecognizer()
                    ..onTap = () => _launchURL(context, 'https://arangcada.ph/tos')),
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
                    ..onTap = () => _launchURL(context, 'https://arangcada.ph/privacy')),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}
