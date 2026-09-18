import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/profile/support_screen.dart';
import 'package:arangcada/features/profile/support_topics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  late DemoState state;

  void setRole(DemoRole role) => state.setCurrentUser(
    DemoUser(
      email: '${role.name}@arangcada.demo',
      displayName: 'Test user',
      role: role,
    ),
  );

  setUp(() {
    state = DemoState();
    setRole(DemoRole.commuter);
  });
  tearDown(() => state.dispose());

  Widget harness({double textScale = 1}) {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SupportScreen()),
        for (final route
            in supportTopics
                .map((topic) => topic.route)
                .whereType<String>()
                .toSet())
          GoRoute(
            path: route,
            builder: (_, _) => Scaffold(
              appBar: AppBar(title: const Text('Destination screen')),
              body: Text('Opened $route'),
            ),
          ),
      ],
    );
    addTearDown(router.dispose);
    return ProviderScope(
      overrides: [demoStateProvider.overrideWithValue(state)],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
  }

  test('help search ignores case and common question words', () {
    expect(
      findSupportTopics('  MY PASSWORD? ', DemoRole.commuter).single.id,
      'password',
    );
    expect(
      findSupportTopics('MTOP', DemoRole.driver).single.id,
      'driver-documents',
    );
    expect(findSupportTopics('xyz-not-a-feature', DemoRole.commuter), isEmpty);
    expect(findSupportTopics('   ', DemoRole.commuter), isNotEmpty);
  });

  test('role-specific help does not send users into another role’s flow', () {
    final commuter = findSupportTopics('', DemoRole.commuter);
    final driver = findSupportTopics('', DemoRole.driver);
    expect(
      commuter.any((topic) => topic.route?.startsWith('/driver') ?? false),
      isFalse,
    );
    expect(commuter.any((topic) => topic.id == 'driver-documents'), isFalse);
    expect(
      driver.any(
        (topic) => topic.id == 'booking' || topic.id == 'saved-places',
      ),
      isFalse,
    );
    expect(
      findSupportTopics('', null).every((topic) => topic.role == null),
      isTrue,
    );
  });

  testWidgets(
    'placeholder contacts and disabled assistant become useful help',
    (tester) async {
      await tester.pumpWidget(harness());
      expect(find.text('Help guide'), findsOneWidget);
      expect(find.textContaining('No message is sent'), findsOneWidget);
      expect(find.text('support@arangcada.example'), findsNothing);
      expect(find.text('+63 900 000 0000'), findsNothing);
      expect(find.text('Not available yet'), findsNothing);
      await tester.enterText(find.byType(TextField), 'password');
      await tester.pumpAndSettle();
      await tester.tap(find.text('How do I change my password?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least 8 characters'), findsOneWidget);
      await tester.ensureVisible(find.text('Open Settings'));
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Opened /profile/app-settings'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'password',
      );
    },
  );

  testWidgets('unmatched searches recover through Show all topics and Clear', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No matching help topics'), findsOneWidget);
    await tester.ensureVisible(find.text('Show all topics'));
    await tester.tap(find.text('Show all topics'));
    await tester.pumpAndSettle();
    expect(find.text('How do I book a ride?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'notifications');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('How do I book a ride?'), findsOneWidget);
  });

  testWidgets('driver document help links to the viewer', (tester) async {
    setRole(DemoRole.driver);
    await tester.pumpWidget(harness());
    await tester.enterText(find.byType(TextField), 'mtop');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Where are my franchise and driver documents?'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open Franchise & documents'));
    await tester.tap(find.text('Open Franchise & documents'));
    await tester.pumpAndSettle();
    expect(find.text('Opened /profile/driver-documents'), findsOneWidget);
  });

  testWidgets('safety help explains limits without claiming to send an alert', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.enterText(find.byType(TextField), 'sos');
    await tester.pumpAndSettle();
    await tester.tap(find.text('What does SOS do?'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('does not contact police or emergency services'),
      findsOneWidget,
    );
    expect(
      find.textContaining('This help guide does not send reports'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('guides remain scrollable with narrow screens and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness(textScale: 2));
    await tester.scrollUntilVisible(find.byType(TextField), 100);
    await tester.enterText(find.byType(TextField), 'notifications');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.text('How do I change notification settings?'),
    );
    await tester.tap(find.text('How do I change notification settings?'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Opened /profile/app-settings'), findsOneWidget);
  });
}
