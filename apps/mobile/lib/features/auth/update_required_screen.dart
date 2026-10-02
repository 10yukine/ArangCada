import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../config/app_build.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/section_card.dart';

/// Shown instead of everything else when the server no longer accepts this
/// build (see checkMinimumBuild).
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  Future<void> _download(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(appDownloadUrl),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open arangcada.app/download in your browser.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primaryFill,
                        borderRadius: BorderRadius.circular(AppRadii.card),
                      ),
                      child: const Icon(
                        Icons.system_update_outlined,
                        size: 28,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Update ArangCada',
                    style: AppTypography.displaySm,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'This version can no longer be used. Install the latest '
                    'version to continue; your account and trips are kept.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ArangButton(
                    label: 'Get the update',
                    icon: Icons.arrow_forward,
                    iconTrailing: true,
                    onPressed: () => _download(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
