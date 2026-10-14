import 'dart:async';

import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/notifications_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/models/app_notification.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:arangcada/features/driver/driver_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoNotifications implements NotificationsRepository {
  @override
  List<AppNotificationRecord> history() => const [];
  @override
  Future<void> markRead(String id) async {}
}

void main() {
  late DemoState state;
  late List<bool> calls;
  setUp(() {
    calls = [];
    state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@arangcada.demo',
        displayName: 'Driver',
        role: DemoRole.driver,
      ),
    );
    state.setDestination(DemoData.places.first);
  });
  tearDown(() => state.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Future<void> Function(bool)? toggle,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          notificationsRepositoryProvider.overrideWithValue(_NoNotifications()),
          driverScreenAwakeProvider.overrideWithValue(
            toggle ??
                (enabled) async {
                  calls.add(enabled);
                },
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const DriverHomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'awake only for accepted, pickup arrival and in-progress states',
    (tester) async {
      await mount(tester);
      expect(calls, isEmpty);
      for (final status in [
        DriverTripStatus.accepted,
        DriverTripStatus.arrivedAtPickup,
        DriverTripStatus.inProgress,
      ]) {
        state.driverTrip.status = status;
        state.driverChanged();
        await tester.pump();
        expect(calls, [true]);
      }
      state.driverTrip.status = DriverTripStatus.completed;
      state.driverChanged();
      await tester.pump();
      expect(calls, [true, false]);

      for (final status in [
        DriverTripStatus.offline,
        DriverTripStatus.available,
        DriverTripStatus.incoming,
        DriverTripStatus.declined,
      ]) {
        state.driverTrip.status = DriverTripStatus.accepted;
        state.driverChanged();
        await tester.pump();
        expect(calls.last, isTrue);
        state.driverTrip.status = status;
        state.driverChanged();
        await tester.pump();
        expect(calls.last, isFalse);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sign-out releases the wake lock even with a leftover active status',
    (tester) async {
      state.driverTrip.status = DriverTripStatus.inProgress;
      await mount(tester);
      expect(calls, [true]);
      state.setCurrentUser(null);
      await tester.pump();
      expect(calls, [true, false]);
      await tester.pumpWidget(const SizedBox());
      expect(calls, [true, false]);
    },
  );

  testWidgets('disposing an active driver screen releases the wake lock', (
    tester,
  ) async {
    state.driverTrip.status = DriverTripStatus.accepted;
    await mount(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls, [true, false]);
  });

  testWidgets(
    'commuters never request a wake lock even with driver trip state',
    (tester) async {
      state.setCurrentUser(
        const DemoUser(
          email: 'commuter@arangcada.demo',
          displayName: 'Commuter',
          role: DemoRole.commuter,
        ),
      );
      state.driverTrip.status = DriverTripStatus.inProgress;
      await mount(tester);
      await tester.pumpWidget(const SizedBox());
      expect(calls, isEmpty);
    },
  );

  testWidgets('a delayed enable completes before disposal disables it', (
    tester,
  ) async {
    state.driverTrip.status = DriverTripStatus.accepted;
    final enable = Completer<void>();
    await mount(
      tester,
      toggle: (enabled) async {
        calls.add(enabled);
        if (enabled) await enable.future;
      },
    );
    await tester.pumpWidget(const SizedBox());
    expect(calls, [true]);
    enable.complete();
    await tester.pump();
    expect(calls, [true, false]);
  });

  testWidgets('resuming an active trip reapplies the screen wake lock', (
    tester,
  ) async {
    state.driverTrip.status = DriverTripStatus.accepted;
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, [true, true]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls, [true, true, false]);
  });
}
