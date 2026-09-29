import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/screens.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_fixture.dart';

/// Same fixture-injection pattern driver_document_review_test.dart uses:
/// connected: true so AdminsScreen's connected-mode branch (real lists,
/// enabled Invite button) is what renders.
class _AdminAccountsFixtureController extends AdminController {
  @override
  AdminState build() => testAdminState().copyWith(
    connected: true,
    adminAccounts: const [
      AdminAccount(
        id: 'admin-lgu-1',
        email: 'lgu.evaluator@example.test',
        role: AdminRole.lgu,
        firstName: 'Lian',
        lastName: 'Garcia',
      ),
      AdminAccount(
        id: 'admin-toda-1',
        email: 'toda.officer@example.test',
        role: AdminRole.toda,
        firstName: 'Mico',
        lastName: 'Santos',
        toda: 'Calamba Poblacion TODA',
      ),
    ],
    adminInvites: [
      AdminInvite(
        id: 'invite-1',
        email: 'pending.recruit@example.test',
        scope: AdminRole.toda,
        status: 'pending',
        created: DateTime(2026, 9, 8),
        toda: 'Calamba Poblacion TODA',
      ),
    ],
    todaZoneOptions: const [('zone-1', 'Calamba Poblacion TODA')],
  );

  @override
  Future<void> removeAdmin(String adminId) async => removed.add(adminId);
}

final removed = <String>[];

void main() {
  tearDown(() {
    auth.value = null;
  });

  Future<void> openAdminsScreen(
    WidgetTester tester, {
    required AdminRole role,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    auth.value = AdminSession(
      userId: role == AdminRole.lgu ? 'admin-lgu-1' : null,
      name: role == AdminRole.lgu ? 'LGU evaluator' : 'TODA officer',
      role: role,
      toda: role == AdminRole.toda ? 'Calamba Poblacion TODA' : null,
      connected: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminProvider.overrideWith(_AdminAccountsFixtureController.new),
        ],
        child: const AdminApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Admins'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admins'));
    await tester.pumpAndSettle();
  }

  testWidgets('LGU sees both LGU and TODA admin accounts, by name and email', (
    tester,
  ) async {
    await openAdminsScreen(tester, role: AdminRole.lgu);

    expect(find.text('LGU administrators'), findsOneWidget);
    expect(find.text('TODA administrators'), findsOneWidget);
    expect(find.text('Lian Garcia'), findsOneWidget);
    expect(find.text('lgu.evaluator@example.test'), findsOneWidget);
    expect(find.text('Mico Santos'), findsOneWidget);
    expect(
      find.text('toda.officer@example.test -- Calamba Poblacion TODA'),
      findsOneWidget,
    );
  });

  testWidgets('LGU can remove another admin, never themselves', (tester) async {
    removed.clear();
    await openAdminsScreen(tester, role: AdminRole.lgu);

    // Signed in as Lian (admin-lgu-1): only Mico has a Remove action.
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Mico Santos?'), findsOneWidget);
    await tester.tap(find.text('Remove administrator'));
    await tester.pumpAndSettle();
    expect(removed, ['admin-toda-1']);
    expect(
      find.text('Mico Santos is no longer an administrator.'),
      findsOneWidget,
    );
  });

  testWidgets('LGU sees the pending invite with a revoke action', (
    tester,
  ) async {
    await openAdminsScreen(tester, role: AdminRole.lgu);

    expect(find.text('Pending invites'), findsOneWidget);
    expect(find.text('pending.recruit@example.test'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);
  });

  testWidgets(
    'a TODA-scoped admin sees a read-only notice instead of the lists',
    (tester) async {
      // AdminsScreen's own role gate, tested directly rather than through
      // the nav rail -- a TODA-scoped session never sees the /admins tab at
      // all (main.dart filters it out), so there is no rail item to tap.
      // This proves the screen itself refuses to show admin data even if
      // reached, which is the property that actually matters -- the rail
      // filter is only a convenience on top of it.
      auth.value = const AdminSession(
        name: 'TODA officer',
        role: AdminRole.toda,
        toda: 'Calamba Poblacion TODA',
        connected: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminProvider.overrideWith(_AdminAccountsFixtureController.new),
          ],
          child: const MaterialApp(home: Scaffold(body: AdminsScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('managed by an LGU administrator'),
        findsOneWidget,
      );
      expect(find.text('Invite admin'), findsNothing);
      expect(find.text('LGU administrators'), findsNothing);
    },
  );

  testWidgets(
    'the invite dialog only asks for a TODA once toda scope is selected',
    (tester) async {
      await openAdminsScreen(tester, role: AdminRole.lgu);

      await tester.tap(find.text('Invite admin'));
      await tester.pumpAndSettle();

      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('TODA'), findsNothing);

      await tester.tap(find.text('LGU administrator -- all TODAs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TODA administrator -- one TODA').last);
      await tester.pumpAndSettle();

      expect(find.text('TODA'), findsOneWidget);
    },
  );

  testWidgets('the invite dialog blocks submission with no email', (
    tester,
  ) async {
    await openAdminsScreen(tester, role: AdminRole.lgu);

    await tester.tap(find.text('Invite admin'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send invite'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    // The dialog is still open -- a real send was never attempted.
    expect(find.text('Invite an administrator'), findsOneWidget);
  });
}
