import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:arangcada/features/rating/driver_rating_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('passenger rating shows the completed trip actual route', (
    tester,
  ) async {
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@example.com',
        displayName: 'Connected Driver',
        role: DemoRole.driver,
      ),
    );
    addTearDown(state.dispose);
    state.pickup = DemoPlace(
      id: 'gps',
      name: 'Current location',
      address: 'Cabuyao, Laguna',
      coordinate: DemoData.calambaCrossing.coordinate,
    );
    state.destination = DemoData.places.firstWhere(
      (place) => place.name == 'SM City Calamba',
    );
    state.driverTrip.status = DriverTripStatus.completed;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoStateProvider.overrideWithValue(state)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const DriverRatingScreen(),
        ),
      ),
    );

    expect(find.text('Current location → SM City Calamba'), findsOneWidget);
    expect(
      find.text('Calamba Crossing Terminal → Calamba City Hall'),
      findsNothing,
    );
  });
}
