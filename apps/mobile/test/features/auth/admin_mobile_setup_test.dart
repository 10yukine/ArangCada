import 'package:arangcada/app/router.dart';
import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Auth extends Fake implements AuthRepository {
  _Auth(this.state);
  final DemoState state;
  String? failSend;
  int sends = 0;
  int deletions = 0;
  @override
  DemoUser? get currentUser => state.currentUser;
  @override
  Future<void> sendPhoneOtp(String phone) async {
    sends++;
    if (failSend != null) throw DemoAuthException(failSend!);
    state.setCurrentUser(state.currentUser!.withPendingPhone(phone));
  }

  @override
  Future<void> signOut() async => state.setCurrentUser(null);
  @override
  Future<void> abandonUnverifiedRegistration() async => deletions++;
}

class _App extends ConsumerWidget {
  const _App();
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    theme: AppTheme.light,
    routerConfig: ref.watch(appRouterProvider),
  );
}

void main() {
  const admin = DemoUser(
    email: 'admin@example.test',
    displayName: 'Website Admin',
    role: DemoRole.commuter,
    isAdminAccount: true,
  );
  late DemoState state;
  late _Auth auth;
  late ProviderContainer container;
  GoRouter router() => container.read(appRouterProvider);
  setUp(() {
    state = DemoState(initialUser: admin);
    auth = _Auth(state);
    container = ProviderContainer(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        authRepositoryProvider.overrideWithValue(auth),
        sessionRestorationProvider.overrideWith((ref) async {}),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    state.dispose();
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _App()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'missing phone gates deep links; identity is read-only; SMS failure stays on setup',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(tester);
      expect(
        router().routeInformationProvider.value.uri.path,
        '/complete-mobile-profile',
      );
      expect(find.text('Website Admin'), findsOneWidget);
      expect(find.text('admin@example.test'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      router().go('/home');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        router().routeInformationProvider.value.uri.path,
        '/complete-mobile-profile',
      );
      await tester.tap(find.text('Send verification code'));
      await tester.pump();
      expect(auth.sends, 0);
      auth.failSend = 'SMS unavailable. Try again.';
      await tester.enterText(find.byType(TextField), '09171234567');
      await tester.tap(find.text('Send verification code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('SMS unavailable. Try again.'), findsOneWidget);
      expect(state.currentUser!.phoneVerified, isFalse);
      expect(
        router().routeInformationProvider.value.uri.path,
        '/complete-mobile-profile',
      );
      auth.failSend = null;
      await tester.tap(find.text('Send verification code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(router().routeInformationProvider.value.uri.path, '/verify-phone');
      expect(state.currentUser!.mobileNumber, '+639171234567');
      expect(state.currentUser!.needsPhoneVerification, isTrue);
      await tester.ensureVisible(find.text('Wrong number? Change number'));
      await tester.tap(find.text('Wrong number? Change number'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        router().routeInformationProvider.value.uri.path,
        '/complete-mobile-profile',
      );
      expect(auth.deletions, 0);
      expect(state.currentUser!.isAdminAccount, isTrue);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(router().routeInformationProvider.value.uri.path, '/login');
      expect(state.currentUser, isNull);
      expect(auth.deletions, 0);
    },
  );

  testWidgets('pending admin verification resumes after restart', (
    tester,
  ) async {
    state.setCurrentUser(admin.withPendingPhone('+639171234567'));
    await mount(tester);
    expect(router().routeInformationProvider.value.uri.path, '/verify-phone');
    expect(find.text('Wrong number? Change number'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('admin onboarding requires SMS even for an internal tester', () {
    const testerAdmin = DemoUser(
      email: 'admin@example.test',
      displayName: 'Admin',
      role: DemoRole.commuter,
      isAdminAccount: true,
      isInternalTester: true,
    );
    expect(testerAdmin.needsPhoneVerification, isTrue);
  });
}
