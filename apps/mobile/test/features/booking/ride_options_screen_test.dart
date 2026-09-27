import 'package:arangcada/core/widgets/map/route_preview_map.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/features/booking/ride_options_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression cover for the Calamba City Hall decisions of 31 August 2026.
///
/// Pooling was withdrawn as a bookable option and the Espesyal passenger cap
/// was raised to 4. Both are commitments to the client, and both are the kind
/// of thing a later UI refactor could quietly undo -- restoring a ride-type
/// toggle "for completeness", or copy-pasting the old `max: 3`. Nothing else
/// in the suite would notice.
void main() {
  Widget harness(DemoState state) => ProviderScope(
    overrides: [demoStateProvider.overrideWithValue(state)],
    child: MaterialApp(home: const RideOptionsScreen()),
  );

  DemoState bookingState() {
    final state = DemoState();
    // The screen renders an empty placeholder without a destination.
    state.setPickup(DemoData.calambaCrossing);
    state.setDestination(DemoData.places[1]);
    return state;
  }

  testWidgets('Pooling is not offered as a bookable ride type', (tester) async {
    final state = bookingState();
    addTearDown(state.dispose);

    await tester.pumpWidget(harness(state));
    await tester.pumpAndSettle();

    // The wording moved on 4 Sep: the "Select a Ride" heading and its single
    // permanently-selected card were removed, because a picker with one option
    // is not a choice and it was taking the room the fare breakdown needed. The
    // ride type is still named -- a commuter must be able to see what they are
    // booking -- just as a caption rather than a control.
    expect(
      find.textContaining('Espesyal'),
      findsWidgets,
      reason: 'the ride type must still be named, even with nothing to choose',
    );
    expect(
      find.text('Pooling'),
      findsNothing,
      reason:
          'Calamba City Hall withdrew pooling on 31 Aug 2026. The enum and the '
          'fare rows survive as the ordinance record of Regular na Byahe, but '
          'no commuter may book it.',
    );
    expect(
      find.textContaining('Shared trip'),
      findsNothing,
      reason: 'no shared-ride pricing may be advertised to commuters',
    );
  });

  Finder segment(String label) => find.descendant(
    of: find.byType(SegmentedButton<int>),
    matching: find.text(label),
  );

  testWidgets('passenger count reaches the LGU-approved four', (tester) async {
    final state = bookingState();
    addTearDown(state.dispose);

    await tester.pumpWidget(harness(state));
    await tester.pumpAndSettle();

    // The selector renders one segment per permitted passenger count.
    for (final value in ['1', '2', '3', '4']) {
      expect(
        segment(value),
        findsOneWidget,
        reason: '$value passengers must be selectable under the LGU-approved '
            'Espesyal cap of 4 (31 Aug 2026)',
      );
    }

    expect(
      segment('5'),
      findsNothing,
      reason: 'the cap moved from 3 to 4, it was not removed -- a fifth '
          'passenger must not be offered',
    );

    await tester.ensureVisible(segment('4'));
    await tester.pumpAndSettle();
    await tester.tap(segment('4'));
    await tester.pumpAndSettle();
    // Passenger count never changes the Espesyal price; the screen says so.
    expect(find.text('Same fare for 1–4'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(state.passengerCount, 4);
  });
  testWidgets('route preview map is interactive with center route button', (
    tester,
  ) async {
    final state = bookingState();
    addTearDown(state.dispose);

    await tester.pumpWidget(harness(state));
    await tester.pumpAndSettle();

    final previewMap = tester.widget<RoutePreviewMap>(
      find.byType(RoutePreviewMap),
    );
    expect(previewMap.interactive, isTrue);

    expect(find.byTooltip('Center route'), findsOneWidget);
    expect(find.byIcon(Icons.center_focus_strong), findsOneWidget);
  });
}
