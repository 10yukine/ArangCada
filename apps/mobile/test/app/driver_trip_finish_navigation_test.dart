import 'package:arangcada/app/app.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/local_chat_repository.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RideRepository extends ChangeNotifier
    implements SupabaseRideRepository {
  _RideRepository(this.state);

  final DemoState state;

  @override
  Map<String, dynamic>? get activeTrip => null;

  @override
  List<Map<String, dynamic>> get trips => const [];

  @override
  bool get heartbeatStale => false;

  @override
  Future<void> completeTrip() async {
    state.driverTrip.completeTrip();
    state.driverChanged();
  }

  @override
  Future<void> finishDriverTrip() async {
    state.finishDriverTrip();
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('driver returns to the dashboard after rating a passenger', (
    tester,
  ) async {
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@arangcada.demo',
        displayName: 'Connected Driver',
        role: DemoRole.driver,
        // Matches the real demo accounts: without this the phone-verification
        // redirect (31 Aug 2026) sends this fixture to /verify-phone and the
        // driver dashboard never renders.
        isInternalTester: true,
      ),
    );
    final rides = _RideRepository(state);
    final chat = LocalChatRepository();
    final container = ProviderContainer(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        liveRideRepositoryProvider.overrideWithValue(rides),
        chatRepositoryProvider.overrideWithValue(chat),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(state.dispose);
    addTearDown(rides.dispose);
    addTearDown(chat.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ArangCadaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hello, Connected'), findsOneWidget);

    state.destination = DemoData.places.firstWhere(
      (place) => place.name == 'SM City Calamba',
    );
    state.driverTrip.status = DriverTripStatus.accepted;
    state.driverChanged();
    await tester.pumpAndSettle();
    expect(find.text('Arrived at Pickup'), findsOneWidget);

    state.driverTrip.status = DriverTripStatus.inProgress;
    // At the drop-off, so the live 100 m completion rule is met.
    state.liveDriverLocation = state.destination!.coordinate;
    state.driverChanged();
    await tester.pumpAndSettle();
    expect(find.text('Complete Trip'), findsOneWidget);

    state.liveTripId = 'completed-trip';
    await tester.tap(find.text('Complete Trip'));
    await tester.pumpAndSettle();
    expect(find.text('Rate your passenger'), findsOneWidget);

    // No survey stands between the rating and the dashboard.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Hello, Connected'), findsOneWidget);
  });
}
