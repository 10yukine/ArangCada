import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/screens.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_fixture.dart';

/// Same fixture-injection pattern admin_invites_test.dart uses, plus method
/// overrides so the two-step dialog's async steps (previewDriverCandidate,
/// promoteCommuterToDriver, sendDriverInvite, revokeDriverInvite) never hit
/// the real repository, which resolves to null in this test environment
/// (no --dart-define Supabase keys).
class _DriverInviteFixtureController extends AdminController {
  String? lastPromotedEmail;
  String? lastInvitedEmail;
  String? lastRevokedInviteId;

  @override
  AdminState build() => testAdminState().copyWith(
    connected: true,
    todaZoneOptions: const [('zone-1', 'Calamba Poblacion TODA')],
    driverInvites: [
      DriverInvite(
        id: 'invite-1',
        email: 'pending.driver@example.test',
        toda: 'Calamba Poblacion TODA',
        status: 'pending',
        created: DateTime(2026, 9, 9),
      ),
    ],
  );

  @override
  Future<List<DriverCandidate>> previewDriverCandidate(String email) async {
    if (email == 'existing@example.test') {
      return const [
        DriverCandidate(
          maskedName: 'J*** D.',
          accountRole: 'commuter',
          accountStatus: 'active',
          joinedOn: '2026-01-05',
          tripCount: 12,
        ),
      ];
    }
    return const [];
  }

  @override
  Future<void> promoteCommuterToDriver({
    required String email,
    required String confirmValue,
    required String todaZoneId,
    String? bodyNumber,
    String? reason,
  }) async {
    lastPromotedEmail = email;
  }

  @override
  Future<void> sendDriverInvite({
    required String email,
    required String todaZoneId,
    String? bodyNumber,
  }) async {
    lastInvitedEmail = email;
  }

  @override
  Future<void> revokeDriverInvite(String inviteId) async {
    lastRevokedInviteId = inviteId;
    state = state.copyWith(
      driverInvites: state.driverInvites
          .where((invite) => invite.id != inviteId)
          .toList(),
    );
  }

  @override
  Future<void> refreshDriverInvites() async {}
}

void main() {
  tearDown(() {
    auth.value = null;
  });

  Future<_DriverInviteFixtureController> openDriversScreen(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    auth.value = const AdminSession(
      name: 'LGU evaluator',
      role: AdminRole.lgu,
      connected: true,
    );

    final controller = _DriverInviteFixtureController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminProvider.overrideWith(() => controller)],
        child: const AdminApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Drivers'));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('the pending invites panel lists an unaccepted invite', (
    tester,
  ) async {
    await openDriversScreen(tester);

    expect(find.text('Pending driver invites'), findsOneWidget);
    expect(find.text('pending.driver@example.test'), findsOneWidget);
  });

  testWidgets('revoking a pending invite removes it from the panel', (
    tester,
  ) async {
    final controller = await openDriversScreen(tester);

    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();

    expect(controller.lastRevokedInviteId, 'invite-1');
    expect(find.text('Pending driver invites'), findsNothing);
  });

  testWidgets(
    'a TODA-scoped admin sees a read-only notice, not the enroll button',
    (tester) async {
      // Rendered directly rather than through the nav rail (same pattern
      // admin_invites_test.dart uses for its own TODA-scoped check) --
      // proves DriversScreen's own role gate refuses the enrollment UI
      // even if reached, independent of whether the rail would offer a tab.
      await tester.binding.setSurfaceSize(const Size(2000, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      auth.value = const AdminSession(
        name: 'TODA officer',
        role: AdminRole.toda,
        toda: 'Calamba Poblacion TODA',
        connected: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminProvider.overrideWith(_DriverInviteFixtureController.new),
          ],
          child: const MaterialApp(home: Scaffold(body: DriversScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('managed by an LGU administrator'),
        findsOneWidget,
      );
      expect(find.text('Enroll driver'), findsNothing);
      expect(find.text('Pending driver invites'), findsNothing);
    },
  );

  testWidgets('the enrollment dialog blocks a malformed email', (
    tester,
  ) async {
    await openDriversScreen(tester);

    await tester.tap(find.text('Enroll driver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets(
    'an email with an existing account shows the candidate and asks to '
    'confirm before promoting',
    (tester) async {
      await openDriversScreen(tester);

      await tester.tap(find.text('Enroll driver'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, "Driver's email address"),
        'existing@example.test',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('This email already has an account'), findsOneWidget);
      expect(find.textContaining('J*** D.'), findsOneWidget);
      expect(find.text('Confirm email'), findsOneWidget);
      expect(find.text('Promote to driver'), findsOneWidget);

      // Mismatched confirm blocks submission.
      await tester.tap(find.text('Promote to driver'));
      await tester.pumpAndSettle();
      expect(find.text('Must match the email above exactly.'), findsOneWidget);
    },
  );

  testWidgets(
    'an email with no existing account offers to send an invite instead',
    (tester) async {
      final controller = await openDriversScreen(tester);

      await tester.tap(find.text('Enroll driver'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, "Driver's email address"),
        'new.driver@example.test',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Enroll a new driver'), findsOneWidget);
      expect(find.textContaining('an invite will be emailed'), findsOneWidget);
      expect(find.text('Send invite'), findsOneWidget);

      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();

      expect(controller.lastInvitedEmail, 'new.driver@example.test');
    },
  );
}
