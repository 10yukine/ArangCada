import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/core/widgets/arang_ui.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/location_repository.dart';
import 'package:arangcada/data/repositories/notifications_repository.dart';
import 'package:arangcada/domain/models/app_notification.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/home/commuter_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNotificationsRepository implements NotificationsRepository {
  _FakeNotificationsRepository(this.items);

  final List<AppNotificationRecord> items;

  @override
  List<AppNotificationRecord> history() => items;

  @override
  Future<void> markRead(String id) async {}
}

class _LocationSpy implements LocationRepository {
  int requests = 0;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<LocationFix> currentLocation() async {
    requests++;
    return LocationFix(
      coordinate: const GeoCoordinate(latitude: 14.2825, longitude: 121.115),
      accuracyMeters: 18,
      timestamp: DateTime.utc(2026, 8, 25),
    );
  }
}

void main() {
  Future<void> render(
    WidgetTester tester, {
    required DemoUser user,
    required _LocationSpy location,
    List<AppNotificationRecord> notifications = const [],
  }) async {
    final state = DemoState(initialUser: user);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          locationRepositoryProvider.overrideWithValue(location),
          notificationsRepositoryProvider.overrideWithValue(
            _FakeNotificationsRepository(notifications),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CommuterHomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('real commuters request GPS and start from their live pickup', (
    tester,
  ) async {
    final location = _LocationSpy();
    await render(
      tester,
      user: const DemoUser(
        email: 'commuter@example.com',
        displayName: 'Connected Commuter',
        role: DemoRole.commuter,
        isInternalTester: true,
      ),
      location: location,
    );

    expect(location.requests, 1);
    expect(find.text('Current location'), findsWidgets);
  });

  testWidgets('local demo commuters never request permission unprompted', (
    tester,
  ) async {
    final location = _LocationSpy();
    await render(
      tester,
      user: const DemoUser(
        email: 'commuter@arangcada.demo',
        displayName: 'Demo Commuter',
        role: DemoRole.commuter,
      ),
      location: location,
    );

    expect(location.requests, 0);
  });

  group('notification bell dot', () {
    testWidgets('hidden when there is no unread history', (tester) async {
      await render(
        tester,
        user: const DemoUser(
          email: 'commuter@example.com',
          displayName: 'Connected Commuter',
          role: DemoRole.commuter,
          isInternalTester: true,
        ),
        location: _LocationSpy(),
        notifications: [
          AppNotificationRecord(
            id: '1',
            title: 'Receipt ready',
            body: 'Your completed ride receipt is available in Trips.',
            receivedAt: DateTime.now(),
            data: const {},
            read: true,
          ),
        ],
      );

      final bell = tester.widget<ArangIconButton>(
        find.widgetWithIcon(ArangIconButton, Icons.notifications_outlined),
      );
      expect(bell.showDot, isFalse);
    });

    testWidgets('shown when at least one entry is unread', (tester) async {
      await render(
        tester,
        user: const DemoUser(
          email: 'commuter@example.com',
          displayName: 'Connected Commuter',
          role: DemoRole.commuter,
          isInternalTester: true,
        ),
        location: _LocationSpy(),
        notifications: [
          AppNotificationRecord(
            id: '1',
            title: 'Driver assigned',
            body: 'Marco Dela Cruz is heading to your pickup point.',
            receivedAt: DateTime.now(),
            data: const {},
            read: false,
          ),
        ],
      );

      final bell = tester.widget<ArangIconButton>(
        find.widgetWithIcon(ArangIconButton, Icons.notifications_outlined),
      );
      expect(bell.showDot, isTrue);
    });
  });
}
