import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/section_card.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 40,
                    color: AppColors.coral,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Password recovery is offline in this demo',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'The production app will send a secure reset link through '
                    'Supabase Auth. No email is sent and no account is changed '
                    'by this aeroplane-mode build.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: context.pop,
                    child: const Text('Back to sign in'),
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
