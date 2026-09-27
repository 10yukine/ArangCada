import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/screens/drivers_screen.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_fixture.dart';

/// Records what the "Manage driver details" editor submits and applies the
/// name change the way a refresh from the server would.
class _DriverRecordFixtureController extends AdminController {
  String? lastDriverId;
  String? lastFirstName;
  String? lastLastName;

  @override
  AdminState build() => testAdminState().copyWith(
        drivers: [
          Driver(
            id: 'driver-101',
            name: 'Juan Dela Cruz',
            toda: 'Calamba Poblacion TODA',
            phone: '09171234567',
            plate: 'ABC-1234',
            status: DriverStatus.approved,
            documents: 4,
            enrollmentCode: 'Body 101',
            updated: DateTime(2026, 9, 1),
          ),
        ],
      );

  @override
  Future<void> updateDriverRecord({
    required String driverId,
    required String firstName,
    required String lastName,
    required String plateNumber,
    required String bodyNumber,
    String? todaZoneId,
    DateTime? licenseExpiresOn,
    bool clearLicenseExpiry = false,
  }) async {
    lastDriverId = driverId;
    lastFirstName = firstName.trim();
    lastLastName = lastName.trim();
    state = state.copyWith(
      drivers: [
        for (final driver in state.drivers)
          if (driver.id == driverId)
            driver.copyWith(
              name: '${firstName.trim()} ${lastName.trim()}',
              firstName: firstName.trim(),
              lastName: lastName.trim(),
            )
          else
            driver,
      ],
    );
  }
}

void main() {
  tearDown(() {
    auth.value = null;
  });

  group('Driver name model parsing', () {
    test('effectiveFirstName and effectiveLastName split full name correctly', () {
      final driver = Driver(
        id: '1',
        name: 'Maria Clara Santos',
        toda: 'Poblacion',
        phone: '09123456789',
        plate: 'XYZ-999',
        status: DriverStatus.approved,
        documents: 4,
        enrollmentCode: 'Body 1',
        updated: DateTime(2026, 9, 1),
      );

      expect(driver.effectiveFirstName, 'Maria');
      expect(driver.effectiveLastName, 'Clara Santos');
    });

    test('explicit firstName and lastName override split full name', () {
      final driver = Driver(
        id: '2',
        name: 'Jose Rizal',
        firstName: 'Dr. Jose',
        lastName: 'Protacio Rizal',
        toda: 'Poblacion',
        phone: '09123456789',
        plate: 'XYZ-999',
        status: DriverStatus.approved,
        documents: 4,
        enrollmentCode: 'Body 2',
        updated: DateTime(2026, 9, 1),
      );

      expect(driver.effectiveFirstName, 'Dr. Jose');
      expect(driver.effectiveLastName, 'Protacio Rizal');
    });
  });

  group('Manage driver details', () {
    Future<_DriverRecordFixtureController> openEditor(
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      auth.value = const AdminSession(
        name: 'LGU transport desk',
        role: AdminRole.lgu,
      );
      final controller = _DriverRecordFixtureController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminProvider.overrideWith(() => controller)],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: DriversScreen(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Manage details'));
      await tester.pumpAndSettle();
      expect(find.text('Manage driver details'), findsOneWidget);
      return controller;
    }

    testWidgets('saving a new first name updates the open driver record', (
      tester,
    ) async {
      final controller = await openEditor(tester);

      expect(find.widgetWithText(TextFormField, 'Juan'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Dela Cruz'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Juan'), 'Johnny');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(controller.lastDriverId, 'driver-101');
      expect(controller.lastFirstName, 'Johnny');
      expect(controller.lastLastName, 'Dela Cruz');
      expect(find.text('Manage driver details'), findsNothing);
      expect(find.text('Johnny Dela Cruz'), findsWidgets);
    });

    testWidgets('a blank first name is rejected before anything is saved', (
      tester,
    ) async {
      final controller = await openEditor(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Juan'), '   ');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(controller.lastDriverId, isNull);
      expect(find.text('Manage driver details'), findsOneWidget);
    });
  });
}
