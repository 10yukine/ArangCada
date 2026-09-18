import 'dart:async';

import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/features/profile/profile_detail_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DemoState state;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;
  bool? allowed;
  var opens = true;
  var fail = false;
  Completer<bool>? pendingOpen;

  setUp(() {
    state = DemoState();
    calls = [];
    allowed = true;
    opens = true;
    fail = false;
    pendingOpen = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      if (fail) throw PlatformException(code: 'unavailable');
      return switch (call.method) {
        'areNotificationsEnabled' => allowed,
        'openAppNotificationSettings' =>
          pendingOpen == null ? opens : pendingOpen!.future,
        _ => throw StateError('Unexpected notification method ${call.method}'),
      };
    });
  });

  tearDown(() {
    state.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Widget harness() => ProviderScope(
    overrides: [demoStateProvider.overrideWithValue(state)],
    child: const MaterialApp(home: AppSettingsScreen()),
  );

  testWidgets(
    'opens Android settings instead of storing ineffective switches',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.textContaining('Allowed by Android'), findsOneWidget);
      await tester.tap(find.text('Notification settings'));
      await tester.pumpAndSettle();
      expect(calls, ['areNotificationsEnabled', 'openAppNotificationSettings']);
    },
  );

  testWidgets(
    'permission status refreshes when returning from Android settings',
    (tester) async {
      allowed = false;
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.textContaining('Blocked by Android'), findsOneWidget);
      await tester.tap(find.text('Notification settings'));
      await tester.pumpAndSettle();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      allowed = true;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('Allowed by Android'), findsOneWidget);
      expect(
        calls.where((method) => method == 'areNotificationsEnabled'),
        hasLength(2),
      );
    },
  );

  testWidgets('a failed settings launch can be retried', (tester) async {
    opens = false;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notification settings'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not open notification settings'),
      findsOneWidget,
    );
    opens = true;
    await tester.tap(find.text('Notification settings'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not open notification settings'),
      findsNothing,
    );
    expect(
      calls.where((method) => method == 'openAppNotificationSettings'),
      hasLength(2),
    );
  });

  testWidgets('platform failures show an unknown status and a usable error', (
    tester,
  ) async {
    fail = true;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Permission status unavailable'),
      findsOneWidget,
    );
    await tester.tap(find.text('Notification settings'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not open notification settings'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown permission is not presented as allowed', (tester) async {
    allowed = null;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Permission status unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Allowed by Android'), findsNothing);
  });

  testWidgets(
    'unsupported platforms do not call Android',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(
        find.text('Push notifications are available in the Android app.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Notification settings'));
      expect(calls, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('repeated taps do not launch twice and disposal is safe', (
    tester,
  ) async {
    pendingOpen = Completer<bool>();
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notification settings'));
    await tester.pump();
    await tester.tap(find.text('Notification settings'));
    await tester.pump();
    expect(
      calls.where((method) => method == 'openAppNotificationSettings'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
    pendingOpen!.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
