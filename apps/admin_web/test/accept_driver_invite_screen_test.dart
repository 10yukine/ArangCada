import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_fixture.dart';

/// Overrides lookupDriverInvite/acceptDriverInvite so this public screen
/// can be exercised without a live Supabase connection -- same reasoning
/// driver_enrollment_test.dart's fixture controller uses.
class _DriverInviteAcceptFixtureController extends AdminController {
  @override
  AdminState build() => testAdminState();

  @override
  Future<({String email, String todaZoneName})> lookupDriverInvite(
    String token,
  ) async => (
    email: 'invited.driver@example.test',
    todaZoneName: 'Calamba Poblacion TODA',
  );

  @override
  Future<void> acceptDriverInvite({
    required String token,
    required String displayName,
    required String mobileNumber,
    required String password,
  }) async {}
}

void main() {
  testWidgets('shows a clear error when the link has no token', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AcceptDriverInviteScreen(token: null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This invite link is missing its token.'), findsOneWidget);
  });

  testWidgets(
    'shows the invalid/expired state when the connection is unavailable',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AcceptDriverInviteScreen(token: 'sometoken'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('invalid or has expired'), findsOneWidget);
      expect(find.text('Create account'), findsNothing);
    },
  );

  testWidgets(
    'a resolved invite locks the email, shows the TODA, and never signs in '
    'or navigates after account creation',
    (tester) async {
      // The form scrolls in a default-sized test surface -- widen it so
      // every field, including the submit button, is reachable without a
      // manual scrollUntilVisible.
      await tester.binding.setSurfaceSize(const Size(500, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminProvider.overrideWith(
              _DriverInviteAcceptFixtureController.new,
            ),
          ],
          child: const MaterialApp(
            home: AcceptDriverInviteScreen(token: 'sometoken'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('invited.driver@example.test'), findsWidgets);
      expect(find.textContaining('Calamba Poblacion TODA'), findsWidgets);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'First name'),
        'Juan',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Last name'),
        'Dela Cruz',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mobile number'),
        '09171234567',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'Password123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Repeat password'),
        'Password123',
      );
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      // Confirmation copy, no navigation attempted -- a driver account
      // cannot open an admin_web session (AdminSession.fromProfile requires
      // role = 'admin'), so this screen is the entire rest of the flow.
      expect(find.text('Account created'), findsOneWidget);
      expect(
        find.textContaining('Open the ArangCada mobile app'),
        findsOneWidget,
      );
      expect(find.text('Create account'), findsNothing);
    },
  );
}
