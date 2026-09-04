import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReportedChatFixtureController extends AdminController {
  @override
  AdminState build() => seedAdminState().copyWith(
    reportedChats: [
      ReportedTripChat.fromRow({
        'id': 'chat-report-1',
        'trip_id': 'trip-1',
        'reporter_id': 'commuter-1',
        'reason': 'Threatening language during pickup',
        'consented_at': '2026-08-25T10:07:00Z',
        'created_at': '2026-08-25T10:07:00Z',
        'messages': [
          {
            'id': 'message-1',
            'sender_id': 'commuter-1',
            'body': 'Only an LGU reviewer may read this message.',
            'created_at': '2026-08-25T10:01:00Z',
          },
        ],
        'trips': {
          'rider_id': 'commuter-1',
          'driver_id': 'driver-1',
          'rider_display_name': 'Ana Reyes',
          'driver_display_name': 'Marco Dela Cruz',
          'toda_name': 'Brgy. Real',
        },
      }),
    ],
  );
}

void main() {
  testWidgets('demo login opens the merged six-section console', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    auth.value = null;
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    await tester.ensureVisible(find.text('Open console'));
    await tester.tap(find.text('Open console'));
    await tester.pumpAndSettle();

    expect(find.text('Good morning, evaluator'), findsOneWidget);
    expect(find.text('Live map'), findsAtLeastNWidgets(1));
    expect(find.text('Evaluation'), findsAtLeastNWidgets(1));
    expect(find.text('Driver survey'), findsNothing);
    expect(find.text('Settings'), findsAtLeastNWidgets(1));
  });

  testWidgets('compact rail remains usable at a narrow desktop size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    auth.value = const AdminSession(
      name: 'Coordinator',
      role: AdminRole.toda,
      toda: 'Brgy. Real',
    );
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();

    expect(find.text('Good morning, evaluator'), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard restores operations panels and actionable review cards',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      auth.value = const AdminSession(
        name: 'LGU evaluator',
        role: AdminRole.lgu,
      );
      addTearDown(() async {
        auth.value = null;
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(const ProviderScope(child: AdminApp()));
      await tester.pumpAndSettle();

      expect(find.text('Live dispatch map'), findsOneWidget);
      expect(find.text('Rides per hour · today'), findsOneWidget);
      expect(find.text('Terminal activity'), findsOneWidget);

      final semantics = tester.ensureSemantics();
      await tester.tap(find.text('PENDING REVIEWS'));
      await tester.pumpAndSettle();

      expect(find.text('Driver verification'), findsOneWidget);
      expect(find.text('Joel Mendoza'), findsOneWidget);
      expect(find.text('Mario Santos'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Settings')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Sign out')), findsWidgets);
      semantics.dispose();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compact table density'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drivers'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<DataTable>(find.byType(DataTable)).dataRowMinHeight,
        48,
      );
    },
  );

  testWidgets(
    'TODA feedback evaluation stays scoped and removes manual surveys',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      auth.value = const AdminSession(
        name: 'Coordinator',
        role: AdminRole.toda,
        toda: 'Brgy. Real',
      );
      addTearDown(() async {
        auth.value = null;
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(const ProviderScope(child: AdminApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evaluation'));
      await tester.pumpAndSettle();

      expect(find.text('Driver App Feedback · Objective 4'), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text('ISO/IEC 25010:2023 · Objective 3'), findsOneWidget);
      expect(find.text('Parian'), findsNothing);
      expect(find.text('Canlubang'), findsNothing);
      expect(find.text('Record response'), findsNothing);
      expect(
        find.text('8 of 10 unique drivers · 8 total responses'),
        findsOneWidget,
      );

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('8 of 10 target drivers'), findsOneWidget);
    },
  );

  testWidgets(
    'TODA safety reports are visible but status actions are read-only',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      auth.value = const AdminSession(
        name: 'Coordinator',
        role: AdminRole.toda,
        toda: 'Brgy. Real',
      );
      addTearDown(() async {
        auth.value = null;
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(const ProviderScope(child: AdminApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Safety reports'));
      await tester.pumpAndSettle();

      expect(
        find.text('Read-only · LGU manages safety report status'),
        findsOneWidget,
      );
      expect(find.text('Mark resolved'), findsNothing);
      expect(find.text('Investigate'), findsNothing);
      expect(find.text('Reported conversations · LGU only'), findsNothing);
    },
  );

  testWidgets(
    'LGU can review explicitly consented reported conversation snapshots',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      auth.value = const AdminSession(
        name: 'LGU evaluator',
        role: AdminRole.lgu,
      );
      addTearDown(() async {
        auth.value = null;
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminProvider.overrideWith(_ReportedChatFixtureController.new),
          ],
          child: const AdminApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Safety reports'));
      await tester.pumpAndSettle();

      expect(find.text('Reported conversations · LGU only'), findsOneWidget);
      expect(find.text('Threatening language during pickup'), findsOneWidget);
      expect(
        find.text('Only an LGU reviewer may read this message.'),
        findsOneWidget,
      );
      expect(find.textContaining('Reported by Ana Reyes'), findsOneWidget);
    },
  );

  testWidgets('TODA never renders consented chat snapshots even if injected', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    auth.value = const AdminSession(
      name: 'Coordinator',
      role: AdminRole.toda,
      toda: 'Brgy. Real',
    );
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminProvider.overrideWith(_ReportedChatFixtureController.new),
        ],
        child: const AdminApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Safety reports'));
    await tester.pumpAndSettle();

    expect(find.text('Reported conversations · LGU only'), findsNothing);
    expect(find.text('Threatening language during pickup'), findsNothing);
    expect(
      find.text('Only an LGU reviewer may read this message.'),
      findsNothing,
    );
  });

  testWidgets('TODA administrators see read-only global feedback settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    auth.value = const AdminSession(
      name: 'Coordinator',
      role: AdminRole.toda,
      toda: 'Brgy. Real',
    );
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Driver app-feedback rules'), findsOneWidget);
    expect(find.text('Save interval'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets(
    'TODA driver review permits approval but hides LGU-only actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      auth.value = const AdminSession(
        name: 'Coordinator',
        role: AdminRole.toda,
        toda: 'Brgy. Real',
      );
      addTearDown(() async {
        auth.value = null;
        await tester.binding.setSurfaceSize(null);
      });
      await tester.pumpWidget(const ProviderScope(child: AdminApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drivers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review').first);
      await tester.pumpAndSettle();

      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Suspend'), findsNothing);
      expect(find.text('Reinstate'), findsNothing);
    },
  );

  testWidgets('account settings match the approved hierarchy and stay honest', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1001, 941));
    auth.value = const AdminSession(
      name: 'Maria Robles',
      email: 'm.robles@calamba.gov.ph',
      role: AdminRole.lgu,
      userId: 'admin-1',
      connected: true,
    );
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Maria Robles'), findsNWidgets(2));
    expect(find.text('MR'), findsNWidgets(2));
    expect(find.text('m.robles@calamba.gov.ph'), findsOneWidget);
    expect(find.text('LGU administrator'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Console access'), findsOneWidget);
    expect(find.text('Console preferences'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Update password'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Reset staff password'),
      findsOneWidget,
    );

    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your current password.'), findsOneWidget);
    expect(find.text('Enter at least 8 characters.'), findsOneWidget);
    expect(find.text('Confirm the new password.'), findsOneWidget);

    await tester.tap(find.text('Reset staff password'));
    await tester.pumpAndSettle();
    expect(find.text('Staff password reset'), findsOneWidget);
    expect(
      find.textContaining('requires a reviewed server-side LGU workflow'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Current password'),
      'current-secret',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password'),
      'new-secret-1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new password'),
      'new-secret-1',
    );
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Password could not be updated. Check your current password and try again.',
      ),
      findsOneWidget,
    );
  });
}
