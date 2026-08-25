import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';

/// Support contacts, with a chatbot placeholder beneath them.
///
/// The contact details sit **above** the assistant on purpose: the working
/// route to a human is the one that must be reachable first, and the
/// assistant below it does not work yet. Nothing here claims a reply.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const supportEmail = 'support@arangcada.example';
  static const supportPhone = '+63 900 000 0000';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const Text('Contact ArangCada support', style: AppTypography.h2),
            const SizedBox(height: AppSpacing.xs),
            SectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: const [
                  _ContactRow(
                    icon: Icons.mail_outline,
                    label: 'Support email',
                    value: supportEmail,
                  ),
                  Divider(height: 1, color: AppColors.dividerLight),
                  _ContactRow(
                    icon: Icons.call_outlined,
                    label: 'Support contact number',
                    value: supportPhone,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Placeholder contact details for the academic prototype. They do '
              'not reach a staffed support desk.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text('Ask the assistant', style: AppTypography.h2),
            const SizedBox(height: AppSpacing.xs),
            const _ChatbotPlaceholder(),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.caption),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inert on purpose. A support assistant that invents answers about fares,
/// TODA jurisdiction, or an emergency would be worse than no assistant, so
/// the composer is visibly disabled rather than faked.
class _ChatbotPlaceholder extends StatelessWidget {
  const _ChatbotPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.primaryFill,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.smart_toy_outlined,
                  size: 20,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ArangCada Assistant',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Not available yet',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.neutralFill,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Text(
              'The in-app assistant is planned but not built. Use the email or '
              'contact number above to reach a person.',
              style: AppTypography.bodySm.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // A disabled composer, not a working one. It shows where the
          // assistant will live without pretending it listens.
          Opacity(
            opacity: 0.55,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: AppColors.borderStrong),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ask a question…',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.send_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
