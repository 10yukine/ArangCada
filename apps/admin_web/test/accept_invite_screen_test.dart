import 'package:arangcada_admin/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a clear error when the link has no token', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AcceptInviteScreen(token: null)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This invite link is missing its token.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows the invalid/expired state rather than a blank or crashed screen '
    'when the connection is unavailable',
    (tester) async {
      // No --dart-define SUPABASE_URL/SUPABASE_ANON_KEY in the test
      // environment, so adminRepositoryProvider resolves to null and the
      // lookup fails -- exercising the same "no live connection" path
      // driverDocumentPhotoUrl/fareClassClaimPhotoUrl already establish for
      // every other screen, without needing a live Supabase project.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AcceptInviteScreen(token: 'sometoken')),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('invalid or has expired'),
        findsOneWidget,
      );
      // The password/first-name form never renders for an unresolved invite.
      expect(find.text('Create account'), findsNothing);
    },
  );
}
