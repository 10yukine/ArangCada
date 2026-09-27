import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/core/widgets/arang_ui.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/location_repository.dart';
import 'package:arangcada/data/repositories/notifications_repository.dart';
import 'package:arangcada/domain/models/app_notification.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/core/widgets/philippine_peso_icon.dart';
import 'package:arangcada/features/home/commuter_home_screen.dart';
import 'package:arangcada/demo/demo_data.dart';
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
  _LocationSpy({
    this.fail = false,
    this.coordinate = const GeoCoordinate(
      latitude: 14.2085,
      longitude: 121.1555,
    ),
  });

  final bool fail;
  final GeoCoordinate coordinate;
  int requests = 0;

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<LocationFix> currentLocation() async {
    requests++;
    if (fail) {
      throw const LocationFailure(
        LocationFailureReason.unavailable,
        'Location is unavailable right now.',
      );
    }
    return LocationFix(
      coordinate: coordinate,
      accuracyMeters: 18,
      timestamp: DateTime.utc(2026, 8, 25),
    );
  }
}

void main() {
  Future<DemoState> render(
    WidgetTester tester, {
    required DemoUser user,
    required _LocationSpy location,
    List<AppNotificationRecord> notifications = const [],
    DemoPlace? pickup,
  }) async {
    final state = DemoState(initialUser: user);
    if (pickup != null) state.setPickup(pickup);
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
    return state;
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

  testWidgets('GPS does not replace a manually chosen pickup', (
    tester,
  ) async {
    final state = await render(
      tester,
      user: const DemoUser(
        email: 'commuter@example.com',
        displayName: 'Connected Commuter',
        role: DemoRole.commuter,
        isInternalTester: true,
      ),
      location: _LocationSpy(),
      pickup: DemoData.places.last,
    );

    expect(state.pickup, same(DemoData.places.last));
  });

  testWidgets('when GPS is outside Calamba City, pickup shows Out of Service Area', (
    tester,
  ) async {
    final location = _LocationSpy(
      coordinate: const GeoCoordinate(latitude: 14.2825, longitude: 121.115),
    );
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
    expect(find.text('Out of Service Area'), findsOneWidget);
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

  testWidgets('know your fare row renders PhilippinePesoIcon', (tester) async {
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

    expect(find.text('Know your fare'), findsOneWidget);
    expect(find.byType(PhilippinePesoIcon), findsOneWidget);
  });

  testWidgets('GPS failure never displays Crossing as the pickup or map', (
    tester,
  ) async {
    final state = await render(
      tester,
      user: const DemoUser(
        email: 'commuter@example.com',
        displayName: 'Connected Commuter',
        role: DemoRole.commuter,
      ),
      location: _LocationSpy(fail: true),
    );

    expect(state.hasPickup, isFalse);
    expect(find.text('Calamba Crossing Terminal'), findsNothing);
    expect(find.text('Location unavailable'), findsWidgets);
    expect(find.text('GPS unavailable'), findsOneWidget);
  });

  testWidgets('GPS in Cabuyao is shown instead of a Calamba fallback', (
    tester,
  ) async {
    final state = await render(
      tester,
      user: const DemoUser(
        email: 'commuter@example.com',
        displayName: 'Connected Commuter',
        role: DemoRole.commuter,
      ),
      location: _LocationSpy(
        coordinate: const GeoCoordinate(latitude: 14.31, longitude: 121.13),
      ),
    );

    expect(state.pickup.id, 'gps');
    expect(state.pickup.coordinate.latitude, 14.31);
    expect(find.text('Calamba Crossing Terminal'), findsNothing);
  });

  testWidgets('GPS refreshes while the home screen remains open', (
    tester,
  ) async {
    final location = _LocationSpy();
    await render(
      tester,
      user: const DemoUser(
        email: 'commuter@example.com',
        displayName: 'Connected Commuter',
        role: DemoRole.commuter,
      ),
      location: location,
    );

    await tester.pump(const Duration(seconds: 15));
    expect(location.requests, 2);
  });
}
