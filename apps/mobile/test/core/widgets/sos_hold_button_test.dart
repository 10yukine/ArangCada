import 'package:arangcada/core/widgets/sos_hold_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'SOS uses a full-button hold fill and completes after 3 seconds',
    (tester) async {
      var completions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: SosHoldButton(onCompleted: () => completions++),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(SosHoldButton)).height, 48);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      var gesture = await tester.startGesture(
        tester.getCenter(find.byType(SosHoldButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      final halfFill = tester.widget<FractionallySizedBox>(
        find.byKey(const Key('sos-button-fill')),
      );
      expect(halfFill.widthFactor, closeTo(0.5, 0.05));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(completions, 0);

      gesture = await tester.startGesture(
        tester.getCenter(find.byType(SosHoldButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 3001));
      await tester.pump();
      expect(completions, 1);
      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets('safety report requires a reason before recording', (
    tester,
  ) async {
    var submissions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showSafetyReportFlow(
                context: context,
                driver: false,
                onSubmit: () async => submissions++,
              ),
              child: const Text('Open report'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();

    FilledButton submit = tester.widget(
      find.widgetWithText(FilledButton, 'Record safety report'),
    );
    expect(submit.onPressed, isNull);

    await tester.tap(find.text('Unsafe driving'));
    await tester.pump();
    submit = tester.widget(
      find.widgetWithText(FilledButton, 'Record safety report'),
    );
    expect(submit.onPressed, isNotNull);

    await tester.tap(find.text('Record safety report'));
    await tester.pumpAndSettle();

    expect(submissions, 1);
    expect(find.text('Safety report recorded'), findsOneWidget);
  });

  testWidgets('connected SOS forwards its selected reason to administrators', (
    tester,
  ) async {
    String? submittedReason;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showSafetyReportFlow(
                context: context,
                driver: false,
                connected: true,
                onSubmit: () async {},
                onSubmitReason: (reason) async => submittedReason = reason,
              ),
              child: const Text('Open live report'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open live report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wrong route'));
    await tester.pump();
    await tester.tap(find.text('Send safety report'));
    await tester.pumpAndSettle();

    expect(submittedReason, 'Wrong route');
    expect(find.text('Administrators notified'), findsOneWidget);
    expect(
      find.textContaining('Police or emergency services were not contacted'),
      findsOneWidget,
    );
  });
}
