import 'package:arangcada/core/widgets/voice_record_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness(ValueChanged<Duration> onRecorded) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: VoiceRecordButton(onRecorded: onRecorded),
      ),
    ),
  );

  // The gesture is onLongPress*, so a hold has to actually clear Flutter's
  // long-press timeout with the pointer still down before it counts as
  // "recording" -- a bare tap must never trigger it.
  Future<TestGesture> holdMic(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(VoiceRecordButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    return gesture;
  }

  testWidgets('a quick tap does not start a recording', (tester) async {
    var called = false;
    await tester.pumpWidget(harness((_) => called = true));

    await tester.tap(find.byType(VoiceRecordButton));
    await tester.pump();

    expect(find.text('Slide up to cancel'), findsNothing);
    expect(called, isFalse);
  });

  testWidgets('hold shows the recording bubble, release with no drag sends', (
    tester,
  ) async {
    Duration? recorded;
    await tester.pumpWidget(harness((duration) => recorded = duration));

    final gesture = await holdMic(tester);
    expect(find.text('Slide up to cancel'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump();

    expect(recorded, isNotNull);
    expect(recorded!.inMilliseconds, greaterThan(0));
  });

  testWidgets(
    'dragging past 25% of the threshold flips to Release to cancel, and '
    'releasing there does not send',
    (tester) async {
      var called = false;
      await tester.pumpWidget(harness((_) => called = true));

      final gesture = await holdMic(tester);
      // Default cancelThreshold is 80px; 25% of that is 20px. 30px is
      // comfortably past the decision point without hitting the 80px cap.
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();

      expect(find.text('Release to cancel'), findsOneWidget);
      expect(find.text('Slide up to cancel'), findsNothing);

      await gesture.up();
      await tester.pump();

      expect(called, isFalse);
    },
  );

  testWidgets('dragging less than 25% of the threshold still sends on release', (
    tester,
  ) async {
    var called = false;
    await tester.pumpWidget(harness((_) => called = true));

    final gesture = await holdMic(tester);
    // 10px is under the 20px (25% of 80px) decision point.
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();

    expect(find.text('Slide up to cancel'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump();

    expect(called, isTrue);
  });

  testWidgets('the bubble shrinks continuously as the drag approaches cancel', (
    tester,
  ) async {
    await tester.pumpWidget(harness((_) {}));

    final gesture = await holdMic(tester);

    double currentScale() {
      // Several unrelated Transform widgets exist in the tree at once (the
      // mic's own grow-in cue, its breathing pulse, AnimatedSwitcher's icon
      // transition) -- filtering by "smallest value found" is ambiguous and
      // was picking up the wrong one. The bubble's Transform.scale is the
      // only Transform built with `alignment: Alignment.bottomRight`
      // (voice_record_button.dart), which uniquely identifies it.
      final bubbleTransform = tester
          .widgetList<Transform>(find.byType(Transform))
          .firstWhere((t) => t.alignment == Alignment.bottomRight);
      // Reading the raw (0,0) matrix entry -- the X-axis scale factor for a
      // pure diagonal scale matrix -- rather than getMaxScaleOnAxis(), which
      // is always polluted by the untouched Z axis staying at 1.0.
      return bubbleTransform.transform.entry(0, 0);
    }

    // At rest (no drag yet), nothing has shrunk below full size.
    expect(currentScale(), 1.0);

    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    final midScale = currentScale();
    expect(midScale, lessThan(1.0));

    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    final farScale = currentScale();
    expect(farScale, lessThan(midScale));

    await gesture.up();
    await tester.pump();
  });
}
