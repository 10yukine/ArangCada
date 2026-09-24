import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/auth/sign_up_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAuthRepo implements AuthRepository {
  String? signedUpName;
  String? signedUpPhone;
  String? signedUpEmail;
  String? signedUpPassword;
  int sendOtpCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  DemoUser? get currentUser => null;

  @override
  Future<RegistrationResult> signUp({
    required String displayName,
    required String mobileNumber,
    required String email,
    required String password,
  }) async {
    signedUpName = displayName;
    signedUpPhone = mobileNumber;
    signedUpEmail = email;
    signedUpPassword = password;
    return RegistrationResult(
      user: DemoUser(
        email: email,
        displayName: displayName,
        role: DemoRole.commuter,
        mobileNumber: mobileNumber,
        phoneVerified: false,
      ),
      requiresEmailConfirmation: false,
    );
  }

  @override
  Future<void> sendPhoneOtp(String e164Phone) async {
    sendOtpCalls++;
  }
}

void main() {
  testWidgets('3-step signup wizard navigates forward, backward, and preserves data', (
    tester,
  ) async {
    final fakeRepo = _FakeAuthRepo();

    final router = GoRouter(
      initialLocation: '/signup',
      routes: [
        GoRoute(
          path: '/signup',
          builder: (_, _) => const SignUpScreen(),
        ),
        GoRoute(
          path: '/verify-phone',
          builder: (_, state) => const Scaffold(body: Text('verify-phone')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('login')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Step 1 (Identity) checks
    expect(find.text('STEP 1 OF 3: IDENTITY'), findsOneWidget);
    expect(find.text('First Name'), findsOneWidget);
    expect(find.text('Last Name'), findsOneWidget);

    // Verify back button is present and does not overlap with content
    final backBtn = find.byTooltip('Back');
    expect(backBtn, findsOneWidget);
    final backBtnRect = tester.getRect(backBtn);
    final titleRect = tester.getRect(find.text('Create Account'));
    // Content title must be strictly below back button
    expect(titleRect.top, greaterThanOrEqualTo(backBtnRect.bottom));

    // Try tapping Continue with empty fields
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter both your first and last name.'), findsOneWidget);

    // Enter name
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'Maria');
    await tester.enterText(textFields.at(1), 'Santos');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // 2. Step 2 (Contact) checks
    expect(find.text('STEP 2 OF 3: CONTACT'), findsOneWidget);
    expect(find.text('Mobile Number'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);

    // Test back button returning to Step 1 and preserving name
    await tester.tap(backBtn);
    await tester.pumpAndSettle();
    expect(find.text('STEP 1 OF 3: IDENTITY'), findsOneWidget);
    expect(find.text('Maria'), findsOneWidget);
    expect(find.text('Santos'), findsOneWidget);

    // Advance to Step 2 again
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 2 OF 3: CONTACT'), findsOneWidget);

    // Fill invalid mobile
    final step2Fields = find.byType(TextField);
    await tester.enterText(step2Fields.at(0), '12345');
    await tester.enterText(step2Fields.at(1), 'maria@example.com');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a Philippine mobile number, like 0917 123 4567.'),
      findsOneWidget,
    );

    // Fill valid Philippine mobile and valid email
    await tester.enterText(step2Fields.at(0), '09171234567');
    await tester.enterText(step2Fields.at(1), 'maria@example.com');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // 3. Step 3 (Security) checks
    expect(find.text('STEP 3 OF 3: SECURITY'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Repeat Password'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);

    // Test back button returning to Step 2 and preserving phone & email
    await tester.tap(backBtn);
    await tester.pumpAndSettle();
    expect(find.text('STEP 2 OF 3: CONTACT'), findsOneWidget);
    expect(find.text('09171234567'), findsOneWidget);
    expect(find.text('maria@example.com'), findsOneWidget);

    // Advance back to Step 3
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 3 OF 3: SECURITY'), findsOneWidget);

    // Try submit without legal agreement
    final step3Fields = find.byType(TextField);
    await tester.enterText(step3Fields.at(0), 'supersecret123');
    await tester.enterText(step3Fields.at(1), 'supersecret123');
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(
      find.text('You must agree to the Terms of Service and Privacy Policy.'),
      findsOneWidget,
    );

    // Agree to legal and submit
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Account'));
    await tester.pump();

    // Verify repository received full combined name and formatted details
    expect(fakeRepo.signedUpName, 'Maria Santos');
    expect(fakeRepo.signedUpPhone, '+639171234567');
    expect(fakeRepo.signedUpEmail, 'maria@example.com');
    expect(fakeRepo.signedUpPassword, 'supersecret123');
    expect(fakeRepo.sendOtpCalls, 1);
  });
}
