import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/notifications_repository.dart';
import 'package:arangcada/domain/models/app_notification.dart';
import 'package:arangcada/features/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Records calls and never touches Hive -- PushNotificationService's real
/// history()/markRead() (and the Hive box behind them) are exercised by
/// physical-device QA instead, same boundary as every other
/// Firebase-platform-channel-dependent piece of this service already has
/// (no unit test touches those either).
class _FakeNotificationsRepository implements NotificationsRepository {
  List<AppNotificationRecord> items = const [];
  final List<String> markReadCalls = <String>[];

  @override
  List<AppNotificationRecord> history() => items;

  @override
  Future<void> markRead(String id) async {
    markReadCalls.add(id);
    items = [
      for (final item in items)
        if (item.id == id) item.copyWithRead(true) else item,
    ];
  }
}

void main() {
  late _FakeNotificationsRepository repository;

  setUp(() {
    repository = _FakeNotificationsRepository();
  });

  Widget harness() => ProviderScope(
    overrides: [
      notificationsRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(home: NotificationsScreen()),
  );

  testWidgets('shows the honest empty state when there is no history', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('No notifications'), findsOneWidget);
    expect(
      find.text('Ride updates and safety reminders will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'renders real history -- title, body, relative time, and an unread dot '
    'only on the unread entry',
    (tester) async {
      repository.items = [
        AppNotificationRecord(
          id: 'unread-1',
          title: 'Driver assigned',
          body: 'Marco Dela Cruz is heading to your pickup point.',
          receivedAt: DateTime.now().subtract(const Duration(minutes: 2)),
          data: const {'type': 'ride_offer'},
          read: false,
        ),
        AppNotificationRecord(
          id: 'read-1',
          title: 'Receipt ready',
          body: 'Your completed ride receipt is available in Trips.',
          receivedAt: DateTime.now().subtract(const Duration(days: 1)),
          data: const {'type': 'ride_updated'},
          read: true,
        ),
      ];

      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.text('Driver assigned'), findsOneWidget);
      expect(
        find.text('Marco Dela Cruz is heading to your pickup point.'),
        findsOneWidget,
      );
      expect(find.text('2 min ago'), findsOneWidget);
      expect(find.text('Receipt ready'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      // Type-based icon mapping.
      expect(find.byIcon(Icons.electric_rickshaw_outlined), findsOneWidget);
      expect(
        find.byIcon(Icons.directions_car_filled_outlined),
        findsOneWidget,
      );

      final dots = tester.widgetList<DecoratedBox>(
        find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(dots, hasLength(1));
    },
  );

  testWidgets('tapping an unread notification marks it read', (tester) async {
    repository.items = [
      AppNotificationRecord(
        id: 'unread-1',
        title: 'Driver assigned',
        body: 'Marco Dela Cruz is heading to your pickup point.',
        receivedAt: DateTime.now(),
        data: const {'type': 'ride_offer'},
        read: false,
      ),
    ];

    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Driver assigned'));
    await tester.pump();

    expect(repository.markReadCalls, ['unread-1']);
    // The screen re-reads history() after marking read, so the dot is gone.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
      findsNothing,
    );
  });

  testWidgets('tapping an already-read notification does not call markRead '
      'again', (tester) async {
    repository.items = [
      AppNotificationRecord(
        id: 'read-1',
        title: 'Receipt ready',
        body: 'Your completed ride receipt is available in Trips.',
        receivedAt: DateTime.now(),
        data: const {},
        read: true,
      ),
    ];

    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Receipt ready'));
    await tester.pump();

    expect(repository.markReadCalls, isEmpty);
  });

  Widget routedHarness() => ProviderScope(
    overrides: [
      notificationsRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/notifications',
        routes: [
          GoRoute(
            path: '/notifications',
            builder: (_, _) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/driver',
            builder: (_, _) => const Scaffold(body: Text('driver destination')),
          ),
          GoRoute(
            path: '/trips',
            builder: (_, _) => const Scaffold(body: Text('trips destination')),
          ),
        ],
      ),
    ),
  );

  testWidgets(
    'tapping a ride_offer notification navigates to /driver',
    (tester) async {
      repository.items = [
        AppNotificationRecord(
          id: 'driver-notif-1',
          title: 'New ride offer',
          body: 'Special ride requested nearby.',
          receivedAt: DateTime.now(),
          data: const {'type': 'ride_offer'},
          read: false,
        ),
      ];

      await tester.pumpWidget(routedHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('New ride offer'));
      await tester.pumpAndSettle();

      expect(find.text('driver destination'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a ride_updated notification navigates to /trips',
    (tester) async {
      repository.items = [
        AppNotificationRecord(
          id: 'rider-notif-1',
          title: 'Ride completed',
          body: 'Your ride has completed.',
          receivedAt: DateTime.now(),
          data: const {'type': 'ride_updated'},
          read: false,
        ),
      ];

      await tester.pumpWidget(routedHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ride completed'));
      await tester.pumpAndSettle();

      expect(find.text('trips destination'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a ride_cancelled notification with target_role commuter navigates to /trips',
    (tester) async {
      repository.items = [
        AppNotificationRecord(
          id: 'rider-cancelled-1',
          title: 'Ride cancelled',
          body: 'Your driver cancelled the ride.',
          receivedAt: DateTime.now(),
          data: const {'type': 'ride_cancelled', 'target_role': 'commuter'},
          read: false,
        ),
      ];

      await tester.pumpWidget(routedHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ride cancelled'));
      await tester.pumpAndSettle();

      expect(find.text('trips destination'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a ride_cancelled notification with target_role driver navigates to /driver',
    (tester) async {
      repository.items = [
        AppNotificationRecord(
          id: 'driver-cancelled-1',
          title: 'Ride cancelled',
          body: 'The passenger cancelled this ride request.',
          receivedAt: DateTime.now(),
          data: const {'type': 'ride_cancelled', 'target_role': 'driver'},
          read: false,
        ),
      ];

      await tester.pumpWidget(routedHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ride cancelled'));
      await tester.pumpAndSettle();

      expect(find.text('driver destination'), findsOneWidget);
    },
  );
}
