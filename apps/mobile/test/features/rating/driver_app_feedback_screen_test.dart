import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/domain/models/driver_app_feedback.dart';
import 'package:arangcada/features/rating/driver_app_feedback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('counts answers and names what is still missing', (
    tester,
  ) async {
    // Tall enough that the lazy list builds every question at once.
    tester.view.physicalSize = const Size(800, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = DemoState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoStateProvider.overrideWithValue(state)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const DriverAppFeedbackScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final total = DriverAppFeedback.questions.length;
    expect(find.text('0 of $total answered'), findsOneWidget);
    expect(find.text('$total left to answer'), findsOneWidget);

    final controls = find.byType(SegmentedButton<int>);
    expect(controls, findsNWidgets(total));
    for (var i = 0; i < total; i++) {
      await tester.tap(
        find.descendant(of: controls.at(i), matching: find.text('4')),
      );
      await tester.pump();
    }
    expect(find.text('$total of $total answered'), findsOneWidget);
    expect(find.text('Check the consent box to continue'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.text('Check the consent box to continue'), findsNothing);
  });
}
