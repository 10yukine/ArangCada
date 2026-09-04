import 'package:arangcada/app/app.dart';
import 'package:arangcada/app/router.dart';
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

class _FeedbackRideRepository extends ChangeNotifier
    implements SupabaseRideRepository {
  _FeedbackRideRepository(this.state);

  final DemoState state;

  @override
  Map<String, dynamic>? get activeTrip => null;

  @override
  List<Map<String, dynamic>> get trips => const [];

  @override
  Future<void> completeTrip() async {
    state.driverTrip.completeTrip();
    state.driverChanged();
  }

  @override
  Future<void> refreshFeedbackState() async {
    state.driverFeedbackPending = true;
    state.pendingFeedbackTripId = 'completed-trip';
    state.driverChanged();
  }

  @override
  Future<void> submitDriverFeedback({
    required Map<String, int> answers,
    required bool anonymous,
    String? comment,
  }) async {
    state.finishDriverTrip();
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('driver dashboard survives mandatory feedback completion', (
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
    final rides = _FeedbackRideRepository(state);
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

    final router = container.read(appRouterProvider);
    state.destination = DemoData.places.firstWhere(
      (place) => place.name == 'SM City Calamba',
    );
    state.driverTrip.status = DriverTripStatus.accepted;
    state.driverChanged();
    await tester.pumpAndSettle();
    expect(find.text('Arrived at Pickup'), findsOneWidget);

    state.driverTrip.status = DriverTripStatus.inProgress;
    state.driverChanged();
    await tester.pumpAndSettle();
    expect(find.text('Complete Trip'), findsOneWidget);

    state.liveTripId = 'completed-trip';
    await tester.tap(find.text('Complete Trip'));
    await tester.pumpAndSettle();
    expect(find.text('Rate your passenger'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Required app feedback'), findsOneWidget);

    await rides.submitDriverFeedback(answers: const {}, anonymous: true);
    router.go('/driver');
    state.driverChanged();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Hello, Connected'), findsOneWidget);
  });
}
