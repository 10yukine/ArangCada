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

/// Legal notice for the bottom of an auth screen.
///
/// Links to the real Terms/Privacy pages served by apps/web
/// (arangcada.app/terms, arangcada.app/policy) -- these used to point at a
/// placeholder arangcada.ph/tos + /privacy that predated apps/web existing
/// and was never updated once it did (found during a gap audit, 6 Sep
/// 2026). See .pipeline/changes.md.
class AuthLegalNotice extends StatelessWidget {
  const AuthLegalNotice({
    this.actionVerb,
    this.prefixText,
    this.textAlign = TextAlign.center,
    this.padding,
    super.key,
  }) : assert(actionVerb != null || prefixText != null);

  /// "Logging in" or "Creating an account"
  final String? actionVerb;
  
  /// "I agree to the "
  final String? prefixText;

  /// Alignment of the text within its container. Defaults to [TextAlign.center].
  final TextAlign textAlign;

  /// Optional outer padding. Defaults to horizontal [AppSpacing.lg].
  final EdgeInsetsGeometry? padding;

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
      padding: padding ?? const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: RichText(
        textAlign: textAlign,
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
                    ..onTap = () => _launchURL(context, 'https://arangcada.app/terms')),
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
                    ..onTap = () => _launchURL(context, 'https://arangcada.app/policy')),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}
