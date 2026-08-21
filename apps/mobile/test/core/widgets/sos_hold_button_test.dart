import 'package:arangcada/core/widgets/sos_hold_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
