import 'package:arangcada/core/widgets/drag_sheet_scaffold.dart';
import 'package:arangcada/core/widgets/sheet_drag_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sheet is sized against the box it occupies, never against the display.
///
/// This is not a theoretical distinction. The ride screens render inside the
/// commuter shell, whose bottom tab bar makes the body shorter than the screen.
/// Expanding to `MediaQuery.size.height` overshot by exactly that difference,
/// which pushed the drag handle off the top edge -- and the handle is the only
/// way to close the sheet, so the screen became a trap. It reached a device
/// before anyone noticed, because on a screen with no tab bar the two heights
/// are identical and nothing looks wrong.
void main() {
  /// Deliberately shorter than the 800x600 test surface, standing in for the
  /// space a bottom tab bar leaves behind.
  Widget harness({double boxHeight = 480}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: boxHeight,
            child: DragSheetScaffold(
              collapsedHeight: 200,
              background: const ColoredBox(color: Colors.green),
              footer: const Text('footer action'),
              sheetBuilder: (context, expanded) =>
                  Text(expanded ? 'expanded body' : 'collapsed body'),
            ),
          ),
          const Spacer(),
        ],
      ),
    ),
  );

  testWidgets('the drag handle stays inside the box when fully expanded', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final handle = find.byType(SheetDragHandle);
    expect(handle, findsOneWidget);

    // Tap to expand, then let the animation finish.
    await tester.tap(handle);
    await tester.pumpAndSettle();

    expect(
      find.text('expanded body'),
      findsOneWidget,
      reason: 'the sheet should report itself expanded after the toggle',
    );

    // THE ASSERTION THAT MATTERS. Off the top of its box means unreachable,
    // and unreachable means the sheet can never be closed again.
    final handleTop = tester.getTopLeft(handle).dy;
    expect(
      handleTop,
      greaterThanOrEqualTo(0.0),
      reason: 'the handle must not be pushed above the top of its own box',
    );
    expect(
      handleTop,
      lessThan(480.0),
      reason: 'the handle must remain within the box the sheet was given',
    );
  });

  testWidgets('expanding never grows the sheet beyond its own constraints', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SheetDragHandle));
    await tester.pumpAndSettle();

    // Measured on the sheet's own surface rather than the whole widget, so this
    // fails if the height is ever taken from MediaQuery again.
    final sheetHeight = tester.getSize(find.byType(SheetDragHandle)).height;
    expect(sheetHeight, greaterThan(0));

    final handleBottom = tester.getBottomLeft(find.byType(SheetDragHandle)).dy;
    expect(
      handleBottom,
      lessThanOrEqualTo(480.0),
      reason: 'nothing in the sheet may render past the bottom of its box',
    );
  });

  testWidgets('a collapsed peek taller than the box is clamped, not overflowed', (
    tester,
  ) async {
    // A caller asking for a 900px peek inside a 480px box is a mistake, but it
    // must degrade to "as tall as there is room for" rather than overflowing --
    // an overflow here would again put the handle out of reach, before the user
    // has even touched anything.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 480,
            child: DragSheetScaffold(
              collapsedHeight: 900,
              background: const ColoredBox(color: Colors.green),
              sheetBuilder: (context, expanded) => const Text('body'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byType(SheetDragHandle)).dy,
      greaterThanOrEqualTo(0.0),
    );
  });

  testWidgets('the footer is rendered and stays below the scrolling body', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('footer action'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('footer action')).dy,
      greaterThan(tester.getTopLeft(find.text('collapsed body')).dy),
      reason: 'the primary action belongs below the content, pinned',
    );
  });
}
