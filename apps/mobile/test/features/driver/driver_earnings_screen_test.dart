import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/driver/driver_earnings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Rides extends ChangeNotifier implements SupabaseRideRepository {
  _Rides(this.trips);

  @override
  final List<Map<String, dynamic>> trips;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'live earnings use completed server fares without sample amounts',
    (tester) async {
      final state = DemoState(
        initialUser: const DemoUser(
          email: 'testdriver@example.com',
          displayName: 'Test Driver',
          role: DemoRole.driver,
        ),
      );
      final rides = _Rides([
        {
          'status': 'completed',
          'final_fare': 75,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
          'pickup_label': 'Cabuyao',
          'destination_label': 'Calamba',
        },
        {'status': 'in_progress', 'final_fare': 999},
      ]);
      addTearDown(state.dispose);
      addTearDown(rides.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            liveRideRepositoryProvider.overrideWithValue(rides),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const DriverEarningsScreen(),
          ),
        ),
      );

    expect(find.text('₱75.00'), findsNWidgets(3));
      expect(find.text('₱999.00'), findsNothing);
      expect(find.text('₱478.00'), findsNothing);
      expect(find.text('Cabuyao → Calamba'), findsOneWidget);
      expect(find.text('Digital payments'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
