import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_fixture.dart';

class _CancellationsController extends AdminController {
  @override
  AdminState build() => testAdminState().copyWith(
    driverCancellations: [
      for (final reason in ['Passenger did not show up', 'Vehicle problem'])
        DriverCancellation(
          driver: 'Marco Dela Cruz',
          toda: 'Brgy. Real',
          reason: reason,
          at: DateTime.now(),
        ),
      DriverCancellation(
        driver: 'Other TODA Driver',
        toda: 'Parian',
        reason: 'Safety concern',
        at: DateTime.now(),
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, AdminSession session) async {
  // Tall enough that the Needs attention list shows every row unscrolled.
  await tester.binding.setSurfaceSize(const Size(1440, 1800));
  auth.value = session;
  addTearDown(() async {
    auth.value = null;
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminProvider.overrideWith(_CancellationsController.new)],
      child: const AdminApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Owner rule: a driver cancelling after accepting alerts the administrators
  // and may be penalised, so the reasons are shown for review.
  testWidgets('LGU sees every driver cancellation with its reasons', (
    tester,
  ) async {
    await _pump(
      tester,
      const AdminSession(name: 'LGU evaluator', role: AdminRole.lgu),
    );
    expect(find.text('3 driver cancellations this week'), findsOneWidget);
    expect(
      find.textContaining(
        'Marco Dela Cruz ×2: Passenger did not show up, Vehicle problem',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a TODA admin sees only their own drivers', (tester) async {
    await _pump(
      tester,
      const AdminSession(
        name: 'TODA admin',
        role: AdminRole.toda,
        toda: 'Parian',
      ),
    );
    expect(find.text('1 driver cancellation this week'), findsOneWidget);
    expect(find.textContaining('Marco Dela Cruz ×2'), findsNothing);
  });
}
