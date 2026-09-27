import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/receipt/digital_receipt_screen.dart';
import 'package:arangcada/features/trips/trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Rides extends ChangeNotifier implements SupabaseRideRepository {
  String? reportedId;
  bool loaded = false;
  @override
  List<Map<String, dynamic>> get trips => !loaded
      ? []
      : [
          {
            'id': 'old-trip',
            'status': 'completed',
            'pickup_label': 'Old pickup',
            'destination_label': 'Old destination',
            'final_fare': 82.50,
            'fare_estimate': 90,
            'ride_type': 'special',
            'payment_method': 'cash',
          },
        ];
  @override
  Future<void> createComplaint(
    String tripId,
    String category,
    String description,
  ) async {
    reportedId = tripId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final role in DemoRole.values) {
    testWidgets('$role historical summary and report retain selected trip', (
      tester,
    ) async {
      final rides = _Rides();
      final state = DemoState(
        initialUser: DemoUser(
          email: 'test@example.invalid',
          displayName: 'Test',
          role: role,
        ),
      );
      state.liveTripId = 'new-trip';
      addTearDown(state.dispose);
      addTearDown(rides.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const TripsScreen()),
          GoRoute(
            path: '/receipt',
            builder: (_, route) =>
                DigitalReceiptScreen(tripId: route.uri.queryParameters['trip']),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            liveRideRepositoryProvider.overrideWithValue(rides),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          role == DemoRole.driver ? 'No driver trips yet' : 'No trips yet',
        ),
        findsOneWidget,
      );
      rides.loaded = true;
      rides.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Summary'));
      await tester.pumpAndSettle();
      // The summary names the selected trip's stops, not the newest trip's:
      // the commuter receipt as pickup/drop-off rows, the driver sheet as a
      // one-line route.
      if (role == DemoRole.driver) {
        expect(find.text('Old pickup → Old destination'), findsWidgets);
      } else {
        expect(find.text('Old pickup'), findsWidgets);
        expect(find.text('Old destination'), findsWidgets);
      }
      expect(find.text('₱82.50'), findsOneWidget);
      expect(state.liveTripId, 'new-trip');
      expect(state.activeBooking, isNull);
      await tester.ensureVisible(find.text('Report an issue with this trip'));
      await tester.tap(find.text('Report an issue with this trip'));
      await tester.pumpAndSettle();
      state.liveTripId = 'another-trip';
      await tester.tap(find.text('Other'));
      await tester.enterText(find.byType(TextField), 'Issue with the old trip');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Submit report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(rides.reportedId, 'old-trip');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(state.liveTripId, 'another-trip');
      expect(tester.takeException(), isNull);
      if (role == DemoRole.commuter) {
        router.go('/receipt?trip=missing');
        await tester.pumpAndSettle();
        expect(find.text('No completed trip receipt.'), findsOneWidget);
        expect(find.text('₱82.50'), findsNothing);
      }
    });
  }
}
