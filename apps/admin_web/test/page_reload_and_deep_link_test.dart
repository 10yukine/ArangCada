import 'dart:async';
import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:arangcada_admin/supabase_admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRepository extends Fake implements SupabaseAdminRepository {
  _FakeRepository({
    this.session,
    this.hasSession = false,
    this.restoreCompleter,
    this.restoreError,
    this.loadFailures = 0,
  });

  /// How many load() calls fail before one succeeds.
  int loadFailures;

  final AdminSession? session;
  @override
  final bool hasSession;
  final Completer<AdminSession>? restoreCompleter;
  final Object? restoreError;

  @override
  Future<AdminSession> signIn({
    required String email,
    required String password,
  }) async {
    if (session != null) return session!;
    throw StateError('Invalid credentials');
  }

  @override
  Future<AdminSession> restoreSession() async {
    if (restoreError != null) throw restoreError!;
    if (restoreCompleter != null) return restoreCompleter!.future;
    if (session != null) return session!;
    throw StateError('No administrator session');
  }

  @override
  Future<AdminSnapshot> load(AdminSession session) async {
    if (loadFailures-- > 0) throw StateError('one query failed');
    return const AdminSnapshot(
      drivers: [],
      reports: [],
      complaints: [],
      ratings: [],
      fareClassClaims: [],
      reportedChats: [],
      rides: [],
      boundaries: [],
      feedbackSummaries: [],
      feedbackResponses: [],
      feedbackInterval: 1,
      respondentTarget: 10,
      repeatFeedback: false,
    );
  }

  @override
  SupabaseClient get client => _FakeClient();

  @override
  Future<AdminAccountsSnapshot> loadAdminAccounts() async =>
      const AdminAccountsSnapshot(
        accounts: [],
        invites: [],
        todaZoneOptions: [],
      );

  @override
  Future<({List<DriverInvite> invites, List<(String id, String name)> zones})>
  loadDriverInvites() async =>
      (invites: <DriverInvite>[], zones: <(String, String)>[]);

  @override
  void subscribe({
    required AdminSession session,
    required VoidCallback onDataChanged,
    required VoidCallback onSafetyInserted,
  }) {}
}

class _FakeClient extends Fake implements SupabaseClient {
  @override
  GoTrueClient get auth => _FakeGoTrueClient();
}

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  @override
  Future<void> signOut({SignOutScope scope = SignOutScope.global}) async {}
}

void main() {
  tearDown(() {
    auth.value = null;
    authRestoring.value = false;
    authError.value = null;
  });

  // A failing query is not a wrong password. This used to stop at the login
  // page with "Check your credentials", with the session left signed in.
  testWidgets(
    'a failed first load still opens the console, with the error and a Retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeRepository(
        session: const AdminSession(
          name: 'LGU Director',
          email: 'director@calamba.gov.ph',
          role: AdminRole.lgu,
          connected: true,
        ),
        loadFailures: 1,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repo)],
          child: const AdminApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'a@example.test',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'synthetic');
      await tester.tap(find.text('Open console'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Check your credentials'), findsNothing);
      expect(find.text('Operations overview'), findsOneWidget);
      expect(find.textContaining('could not be refreshed'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be refreshed'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      // No audit feed is loaded, so the console must not claim there was none.
      expect(find.text('Live activity'), findsNothing);
      expect(
        find.textContaining('No activity in your jurisdiction'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'page reload on /admins preserves /admins during session restore and renders AdminsScreen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final completer = Completer<AdminSession>();
      const restoredSession = AdminSession(
        name: 'LGU Director',
        email: 'director@calamba.gov.ph',
        role: AdminRole.lgu,
        connected: true,
      );

      final repo = _FakeRepository(
        hasSession: true,
        restoreCompleter: completer,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repo)],
          child: const AdminApp(initialLocation: '/admins'),
        ),
      );

      // On first frame: session is restoring, authRestoring is true.
      // Must NOT redirect to /login and must NOT show the login screen.
      expect(find.text('Welcome back'), findsNothing);
      expect(find.text('Operations overview'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Complete the async restoration from Supabase
      completer.complete(restoredSession);
      await tester.pumpAndSettle();

      // Now session is restored: user lands directly on AdminsScreen!
      expect(find.text('Welcome back'), findsNothing);
      expect(find.text('Operations overview'), findsNothing);
      expect(find.text('Admins'), findsAtLeastNWidgets(1));
      expect(
        find.text(
          'Invite and review LGU and TODA administrator accounts by email.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'page reload on /drivers preserves /drivers during session restore and renders DriversScreen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const restoredSession = AdminSession(
        name: 'TODA Coordinator',
        email: 'toda@calamba.gov.ph',
        role: AdminRole.toda,
        toda: 'Brgy. Real',
        connected: true,
      );

      final repo = _FakeRepository(hasSession: true, session: restoredSession);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repo)],
          child: const AdminApp(initialLocation: '/drivers'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsNothing);
      expect(find.text('Operations overview'), findsNothing);
      expect(find.text('Drivers'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'unauthenticated visit to /admins redirects to /login?from=%2Fadmins and returns to /admins after sign in',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _FakeRepository(
        hasSession: false,
        session: const AdminSession(
          name: 'LGU evaluator',
          email: 'lgu@example.test',
          role: AdminRole.lgu,
          connected: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repo)],
          child: const AdminApp(initialLocation: '/admins'),
        ),
      );
      await tester.pumpAndSettle();

      // Redirected to login with ?from=/admins
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Use local demo'), findsNothing);

      // Sign in with an administrator account.
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'lgu@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'synthetic-password',
      );
      await tester.tap(find.text('Open console'));
      await tester.pumpAndSettle();

      // Redirected back to the requested /admins page, NOT /dashboard!
      expect(find.text('Welcome back'), findsNothing);
      expect(find.text('Operations overview'), findsNothing);
      expect(find.text('Admins'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'session expiration during restore redirects to /login with error message',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _FakeRepository(
        hasSession: true,
        restoreError: StateError('Session expired'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repo)],
          child: const AdminApp(initialLocation: '/admins'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.text('Your administrator session expired. Sign in again.'),
        findsOneWidget,
      );
    },
  );
}
