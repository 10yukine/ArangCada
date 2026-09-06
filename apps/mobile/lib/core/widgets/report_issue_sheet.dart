import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import 'arang_dialog.dart';

/// A non-emergency complaint category, paired with the server-side value
/// `create_complaint()` expects (`supabase/migrations/20260905020000_complaints.sql`).
class ComplaintCategory {
  const ComplaintCategory(this.value, this.label);

  final String value;
  final String label;
}

const commuterComplaintCategories = [
  ComplaintCategory('driver_late', 'Driver was late'),
  ComplaintCategory('unsafe_driving_non_emergency', 'Unsafe driving'),
  ComplaintCategory('rude_unprofessional', 'Rude or unprofessional'),
  ComplaintCategory('wrong_route', 'Wrong route taken'),
  ComplaintCategory('vehicle_condition', 'Vehicle condition'),
  ComplaintCategory('overcharged', 'Overcharged'),
  ComplaintCategory('other', 'Other'),
];

const driverComplaintCategories = [
  ComplaintCategory('passenger_late', 'Passenger was late'),
  ComplaintCategory('rude_unprofessional', 'Rude or unprofessional'),
  ComplaintCategory('damaged_vehicle_non_emergency', 'Damaged vehicle'),
  ComplaintCategory('disputed_fare', 'Disputed fare'),
  ComplaintCategory('other', 'Other'),
];

/// Files a non-emergency complaint about the other trip participant.
///
/// Deliberately a separate sheet from `sos_hold_button.dart`'s
/// `showSafetyReportFlow` -- that one's red, alarming styling exists on
/// purpose to be reserved for actual danger. Reusing it here for "driver was
/// late" would train users to associate red with routine gripes, which is
/// exactly the outcome SOS's design was trying to avoid.
Future<void> showReportIssueFlow({
  required BuildContext context,
  required bool driver,
  required Future<void> Function(String category, String description)?
  onSubmit,
}) async {
  if (onSubmit == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Filing a report requires a connected account.'),
      ),
    );
    return;
  }

  final categories = driver
      ? driverComplaintCategories
      : commuterComplaintCategories;
  String? selectedCategory;
  final descriptionController = TextEditingController();

  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.report_problem_outlined,
              color: AppColors.primary,
              size: 34,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Report an issue',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Not an emergency -- LGU/TODA administrators review this. For '
              'immediate danger, use SOS during the ride instead.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final category in categories)
                  ChoiceChip(
                    label: Text(category.label),
                    selected: selectedCategory == category.value,
                    onSelected: (_) => setSheetState(
                      () => selectedCategory = category.value,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: descriptionController,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setSheetState(() {}),
            ),
            const SizedBox(height: AppSpacing.xs),
            FilledButton(
              onPressed:
                  selectedCategory == null ||
                      descriptionController.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(sheetContext, true),
              child: const Text('Submit report'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );

  final category = selectedCategory;
  if (submitted != true || category == null || !context.mounted) return;
  try {
    await onSubmit(category, descriptionController.text.trim());
  } on Exception {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The report could not be sent. Please try again.'),
        ),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => ArangDialog(
      icon: const Icon(Icons.shield_outlined, color: AppColors.green),
      title: 'Report sent',
      content: const Text(
        'ArangCada administrators received your report and will follow up '
        'if needed.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
