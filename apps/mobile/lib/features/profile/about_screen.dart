import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arangcada_mark.dart';
import '../../core/widgets/section_card.dart';

class AboutArangCadaScreen extends StatefulWidget {
  const AboutArangCadaScreen({super.key});

  @override
  State<AboutArangCadaScreen> createState() => _AboutArangCadaScreenState();
}

class _AboutArangCadaScreenState extends State<AboutArangCadaScreen> {
  int _versionTapCount = 0;

  void _tapVersion() {
    _versionTapCount++;
    if (_versionTapCount < 5) return;
    _versionTapCount = 0;
    context.push('/profile/demo-tools');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About ArangCada')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const Center(child: ArangCadaMark(compact: true)),
            const SizedBox(height: AppSpacing.xl),
            const SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Academic capstone prototype', style: AppTypography.h2),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    'ArangCada is a non-commercial academic prototype for TODA-anchored tricycle hailing and dispatch in Calamba City. It is not a production service.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Production map and routing stack',
                    style: AppTypography.h2,
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text('Map data © OpenStreetMap contributors under ODbL.'),
                  SizedBox(height: AppSpacing.xs),
                  Text('Tiles by MapTiler.'),
                  SizedBox(height: AppSpacing.xs),
                  Text('Routing by openrouteservice / HeiGIT.'),
                  SizedBox(height: AppSpacing.xs),
                  Text('No endorsement by HeiGIT is implied.'),
                  SizedBox(height: AppSpacing.md),
                  Text(
                    'Map and routing availability depends on the configured development API keys.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const SectionCard(
              child: Text(
                'ArangCada does not hold or custody customer funds. Any production digital balance would be held and processed by a payment provider.',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            InkWell(
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadii.input),
              ),
              onTap: _tapVersion,
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  'Version 1.0.0 · Academic prototype',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
