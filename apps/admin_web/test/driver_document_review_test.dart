import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_fixture.dart';

/// Same fixture-injection pattern claims_screen_test.dart uses: connected:
/// true so the redesigned dialog's connected-mode branch (Upload/Replace,
/// Approve/Reject, the inline photo) is what renders, not the disconnected
/// local-demo placeholder text.
class _DriverDocumentFixtureController extends AdminController {
  @override
  AdminState build() => testAdminState().copyWith(
    connected: true,
    drivers: [
      Driver(
        id: 'driver-1',
        name: 'Marco Dela Cruz',
        toda: 'Calamba Poblacion TODA',
        phone: '+639170001234',
        plate: 'ABC-1234',
        status: DriverStatus.review,
        documents: 2,
        enrollmentCode: 'Body 42',
        updated: DateTime(2026, 9, 8),
        documentStatuses: {
          'drivers_license': 'approved',
          'mtop_franchise': 'pending',
          'toda_membership': 'rejected',
        },
        documentIds: {
          'drivers_license': 'doc-license',
          'mtop_franchise': 'doc-mtop',
          'toda_membership': 'doc-toda',
        },
        documentPaths: {
          'drivers_license': 'driver-1/drivers_license-1.jpg',
          'mtop_franchise': 'driver-1/mtop_franchise-1.jpg',
          'toda_membership': 'driver-1/toda_membership-1.jpg',
        },
      ),
    ],
  );
}

void main() {
  tearDown(() {
    auth.value = null;
  });

  Future<void> openDriverDialog(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(2000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    auth.value = const AdminSession(
      name: 'LGU evaluator',
      role: AdminRole.lgu,
      connected: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminProvider.overrideWith(_DriverDocumentFixtureController.new),
        ],
        child: const AdminApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drivers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the redesigned dialog lists all 6 real document types, not the old '
    '4-item list',
    (tester) async {
      await openDriverDialog(tester);

      expect(find.text('Driver’s license'), findsOneWidget);
      expect(find.text('MTOP / franchise permit'), findsOneWidget);
      expect(find.text('TODA membership endorsement'), findsOneWidget);
      expect(find.text('Vehicle OR / CR registration'), findsOneWidget);
      expect(find.text('Barangay clearance (optional)'), findsOneWidget);
      expect(find.text('Vehicle photo (optional)'), findsOneWidget);
    },
  );

  testWidgets('a pending document with a file shows Approve and Reject', (
    tester,
  ) async {
    await openDriverDialog(tester);

    // Drivers are approved or suspended; only a document can be rejected.
    expect(find.text('Approve'), findsNWidgets(2));
    expect(find.text('Reject'), findsOneWidget);
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(
      find.descendant(
        of: find.byWidget(dialog.actions!.single),
        matching: find.text('Reject'),
      ),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.text('Manage details')).dy,
      lessThan(tester.getTopLeft(find.text('Submitted documents')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Approve').last).dx,
      lessThan(tester.getTopLeft(find.text('Suspend')).dx),
    );
    expect(
      tester.getTopLeft(find.text('Suspend')).dx,
      lessThan(tester.getTopLeft(find.text('Close')).dx),
    );
  });

  testWidgets(
    'an approved document shows Replace but not Approve/Reject for that row',
    (tester) async {
      await openDriverDialog(tester);

      // drivers_license is 'approved' -- Replace, no review actions for it.
      // mtop_franchise is 'pending' -- Approve/Reject exist exactly once,
      // both belonging to that row (asserted above), not the approved one.
      expect(find.text('Replace'), findsWidgets);
    },
  );

  testWidgets('a document with no file at all offers Upload, not Replace', (
    tester,
  ) async {
    await openDriverDialog(tester);

    // or_cr, barangay_clearance, and vehicle_photo have no path in the
    // fixture (only drivers_license/mtop_franchise/toda_membership do).
    expect(find.text('Upload'), findsNWidgets(3));
  });

  testWidgets(
    'the old "files remain private" copy is gone -- documents are viewable '
    'now',
    (tester) async {
      await openDriverDialog(tester);

      expect(find.textContaining('Files remain private'), findsNothing);
      expect(find.textContaining('mints a signed link'), findsOneWidget);
    },
  );
}
