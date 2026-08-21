import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/arang_ui.dart';
import '../../domain/fare/fare_matrix.dart';

/// Read-only view of the published LGU fare table.
///
/// Every amount is read from [FareMatrix]. Nothing here restates a number.
/// That is deliberate: the ordinance transcription exists precisely so there
/// is one copy, and a display screen carrying its own copy is how the app and
/// the tarpaulin quietly drift apart.
///
/// Two printed Regular rows are NOT a clean 20% of the full fare -- 4 km is
/// P15.50 and 16 km is P34.00. They are printed that way, encoded that way on
/// purpose, and must never be "corrected" here.
///
/// TODO(lgu-panel): rates are bundled from City Ordinance No. 743, s. 2022
/// because the LGU has not published a live fare panel yet. When it does, this
/// screen should source from that panel (behind a repository, cached, with the
/// bundled table as the offline fallback) instead of reading FareMatrix
/// directly. Until then, bundled data and the future panel are guaranteed to
/// agree only because both derive from the same ordinance.
class FareMatrixScreen extends StatelessWidget {
  const FareMatrixScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fare matrix')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const _SourceNote(),
            const SizedBox(height: AppSpacing.md),
            _FareTable(
              title: 'Regular na Byahe',
              subtitle: 'Pooling · shared ride',
              billing: 'Charged PER PASSENGER',
              capacity: 'Up to 4 passengers',
              tone: ArangBadgeTone.green,
              full: FareMatrix.poolingFullCentavos,
              discounted: FareMatrix.poolingDiscountedCentavos,
              pastTwentyFull: FareMatrix.incrementPast20Centavos(RideType.pooling, DiscountClass.full),
              pastTwentyDiscounted: FareMatrix.incrementPast20Centavos(RideType.pooling, DiscountClass.discounted),
            ),
            const SizedBox(height: AppSpacing.lg),
            _FareTable(
              title: 'Espesyal na Byahe',
              subtitle: 'Special · private ride',
              billing: 'Charged PER TRIP',
              capacity: '1 to 3 passengers',
              tone: ArangBadgeTone.clay,
              full: FareMatrix.specialFullCentavos,
              discounted: FareMatrix.specialDiscountedCentavos,
              pastTwentyFull: FareMatrix.incrementPast20Centavos(RideType.special, DiscountClass.full),
              pastTwentyDiscounted: FareMatrix.incrementPast20Centavos(RideType.special, DiscountClass.discounted),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _RulesCard(),
            const SizedBox(height: AppSpacing.md),
            const _Provenance(),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SourceNote extends StatelessWidget {
  const _SourceNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.amberFill,
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 18,
            color: AppColors.amberText,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Rates are from City Ordinance No. 743, s. 2022, bundled with '
              'this app. The city has not published a live fare panel yet; '
              'when it does, this screen will read from it directly.',
              style: AppTypography.caption.copyWith(
                color: AppColors.amberText,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FareTable extends StatelessWidget {
  const _FareTable({
    required this.title,
    required this.subtitle,
    required this.billing,
    required this.capacity,
    required this.tone,
    required this.full,
    required this.discounted,
    required this.pastTwentyFull,
    required this.pastTwentyDiscounted,
  });

  final String title;
  final String subtitle;
  final String billing;
  final String capacity;
  final ArangBadgeTone tone;
  final Map<int, int> full;
  final Map<int, int> discounted;
  final int pastTwentyFull;
  final int pastTwentyDiscounted;

  /// Display-only cutoff. The underlying [FareMatrix] is untouched and still
  /// carries every printed row up to [FareMatrix.printedMaxKm]; this just
  /// keeps the on-screen table short. Do not use this to change fare values.
  static const int _displayMaxKm = 10;

  @override
  Widget build(BuildContext context) {
    final kilometres = full.keys.where((km) => km <= _displayMaxKm).toList()
      ..sort();

    return ArangCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: AppTypography.displaySm),
                    ),
                    ArangBadge(capacity, tone: tone),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.caption),
                const SizedBox(height: AppSpacing.xs),
                // The one thing on this matrix that is easiest to misread.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.neutralFill,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Text(
                    billing,
                    style: AppTypography.label.copyWith(
                      color: AppColors.ink,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const _HeaderRow(),
          for (final km in kilometres)
            _FareRow(
              kilometre: km,
              fullCentavos: full[km]!,
              discountedCentavos: discounted[km]!,
              highlight: km == 2,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: Text(
              'Showing the first $_displayMaxKm km. The published matrix '
              'continues, unchanged, through ${FareMatrix.printedMaxKm} km.',
              style: AppTypography.caption,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              'Beyond ${FareMatrix.printedMaxKm} km, each started kilometre '
              'adds ${formatCentavos(pastTwentyFull)} '
              '(${formatCentavos(pastTwentyDiscounted)} discounted).',
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      height: 1.25,
    );
    return Container(
      color: AppColors.neutralFill,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Kilometro', style: style)),
          Expanded(
            flex: 4,
            child: Text(
              'Minimum na Pamasahe',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              'Senior / PWD / Estudyante',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({
    required this.kilometre,
    required this.fullCentavos,
    required this.discountedCentavos,
    required this.highlight,
  });

  final int kilometre;
  final int fullCentavos;
  final int discountedCentavos;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
      color: AppColors.ink,
    );
    final amountStyle = TextStyle(
      fontSize: 13,
      fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
      color: AppColors.ink,
    );

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.dividerLight)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 9,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              // Row 2 covers everything at or under 2 km, so it is not a
              // "2 km" row in the way 3 km is.
              highlight ? 'First 2 km' : '$kilometre km',
              style: labelStyle,
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              formatCentavos(fullCentavos),
              textAlign: TextAlign.right,
              style: amountStyle,
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              formatCentavos(discountedCentavos),
              textAlign: TextAlign.right,
              style: amountStyle.copyWith(color: AppColors.green),
            ),
          ),
        ],
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    return ArangCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How the fare is counted', style: AppTypography.h2),
          const SizedBox(height: AppSpacing.xs),
          const _Rule(
            'The base fare covers the first 2 kilometres. A trip of exactly '
            '2 km still pays the base fare.',
          ),
          const _Rule(
            'Past 2 km, every started kilometre bills in full. A 2.1 km trip '
            'pays the 3 km row.',
          ),
          const _Rule(
            'Distance is measured point to point between pickup and drop-off, '
            'not by the route the tricycle drives.',
          ),
          const _Rule(
            'Discounted fares are the amounts printed by the city, not a '
            'percentage the app calculates.',
          ),
          const _Rule('There is no surge pricing.'),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5, right: 8),
            child: SizedBox(
              width: 5,
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Provenance extends StatelessWidget {
  const _Provenance();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Source: Calamba City Ordinance No. 743, s. 2022 — Tricycle Minimum '
          'Fare, issued by the Business Permits & Tricycle Franchising Office.',
          style: AppTypography.caption.copyWith(height: 1.45),
        ),
        const SizedBox(height: 4),
        Text(
          'Fare data version: ${FareMatrix.version}',
          style: AppTypography.caption.copyWith(
            fontFeatures: const [],
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'If a posted matrix in a tricycle disagrees with this table, the '
          'posted matrix is correct — please report it.',
          style: AppTypography.caption.copyWith(height: 1.45),
        ),
      ],
    );
  }
}
