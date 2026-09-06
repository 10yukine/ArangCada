import 'package:arangcada/core/widgets/report_issue_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness({
    required bool driver,
    required Future<void> Function(String category, String description)?
    onSubmit,
  }) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showReportIssueFlow(
            context: context,
            driver: driver,
            onSubmit: onSubmit,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );

  testWidgets('a disconnected account never sees the sheet at all', (
    tester,
  ) async {
    await tester.pumpWidget(harness(driver: false, onSubmit: null));
    await tester.tap(find.text('open'));
    await tester.pump();

    expect(find.text('Report an issue'), findsNothing);
    expect(
      find.text('Filing a report requires a connected account.'),
      findsOneWidget,
    );
  });

  testWidgets('submit stays disabled until a category and a description are '
      'both given', (tester) async {
    final submitted = <(String, String)>[];
    await tester.pumpWidget(
      harness(
        driver: false,
        onSubmit: (category, description) async {
          submitted.add((category, description));
        },
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Finder submitButton() => find.widgetWithText(FilledButton, 'Submit report');
    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNull);

    await tester.tap(find.text('Driver was late'));
    await tester.pump();
    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Waited 20 minutes.');
    await tester.pump();
    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNotNull);

    await tester.ensureVisible(submitButton());
    await tester.pumpAndSettle();
    await tester.tap(submitButton());
    await tester.pumpAndSettle();

    expect(submitted, [('driver_late', 'Waited 20 minutes.')]);
    expect(find.text('Report sent'), findsOneWidget);
  });

  testWidgets('the driver sees driver-facing categories, not commuter ones', (
    tester,
  ) async {
    // A no-op, non-null callback -- with onSubmit null the sheet never opens
    // at all (that is the previous test's point), so this one needs any
    // callback just to reach the category list.
    await tester.pumpWidget(
      harness(driver: true, onSubmit: (_, _) async {}),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Passenger was late'), findsOneWidget);
    expect(find.text('Driver was late'), findsNothing);
  });

  testWidgets('Cancel closes the sheet without calling onSubmit', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(
      harness(
        driver: false,
        onSubmit: (_, _) async => called = true,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final cancelButton = find.text('Cancel');
    await tester.ensureVisible(cancelButton);
    await tester.pumpAndSettle();
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    expect(called, isFalse);
  });
}
