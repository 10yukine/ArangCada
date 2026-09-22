import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:arangcada_admin/screens/claims_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same fixture-injection pattern app_smoke_test.dart uses for
/// reportedChats: fareClassClaims carries no demo seed data (commuters have
/// no TODA to seed a per-TODA fixture against), so a claim to review has to
/// be injected the same way.
class _ClaimFixtureController extends AdminController {
  @override
  AdminState build() => seedAdminState().copyWith(
    fareClassClaims: [
      FareClassClaim.fromRow({
        'id': 'claim-1',
        'claimant_display_name': 'Ana Reyes',
        'requested_class': 'student',
        'id_photo_path': '00000000-0000-0000-0000-000000000001/id.jpg',
        'status': 'pending_review',
        'created_at': '2026-09-05T10:00:00Z',
      }),
      FareClassClaim.fromRow({
        'id': 'claim-2',
        'claimant_display_name': 'Paolo Cruz',
        'requested_class': 'pwd',
        'id_photo_path': '00000000-0000-0000-0000-000000000002/id.jpg',
        'status': 'rejected',
        'rejection_reason': 'Photo was too blurry to read.',
        'created_at': '2026-09-04T09:00:00Z',
      }),
    ],
  );
}

void main() {
  testWidgets('compact claims focus on one record and return to the queue', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    auth.value = const AdminSession(name: 'LGU evaluator', role: AdminRole.lgu);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminProvider.overrideWith(_ClaimFixtureController.new)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: ClaimsScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Submitted ID'), findsNothing);
    await tester.ensureVisible(find.text('Ana Reyes'));
    await tester.tap(find.text('Ana Reyes'));
    await tester.pumpAndSettle();
    expect(find.text('Submitted ID'), findsOneWidget);
    expect(find.text('Paolo Cruz'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Back to queue'));
    await tester.tap(find.text('Back to queue'));
    await tester.pumpAndSettle();
    expect(find.text('Paolo Cruz'), findsOneWidget);
    expect(find.text('Submitted ID'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  tearDown(() {
    auth.value = null;
  });

  testWidgets(
    'LGU sees a pending claim with Approve/Reject and the submitted photo '
    'link',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      auth.value = const AdminSession(
        name: 'LGU evaluator',
        role: AdminRole.lgu,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminProvider.overrideWith(_ClaimFixtureController.new)],
          child: const AdminApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discount claims'));
      await tester.pumpAndSettle();

      expect(find.text('Ana Reyes'), findsWidgets);
      expect(find.text('Student'), findsWidgets);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    },
  );

  testWidgets(
    'a rejected claim shows its reason and no longer offers Approve/Reject',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      auth.value = const AdminSession(
        name: 'LGU evaluator',
        role: AdminRole.lgu,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminProvider.overrideWith(_ClaimFixtureController.new)],
          child: const AdminApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discount claims'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paolo Cruz'));
      await tester.pumpAndSettle();

      expect(find.text('Photo was too blurry to read.'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    },
  );

  testWidgets(
    'a TODA administrator sees an LGU-only explanation instead of the list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      auth.value = const AdminSession(
        name: 'Brgy. Real desk',
        role: AdminRole.toda,
        toda: 'Brgy. Real',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminProvider.overrideWith(_ClaimFixtureController.new)],
          child: const AdminApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discount claims'));
      await tester.pumpAndSettle();

      expect(find.text('Ana Reyes'), findsNothing);
      expect(
        find.textContaining('reviewed by an LGU administrator'),
        findsOneWidget,
      );
    },
  );
}
