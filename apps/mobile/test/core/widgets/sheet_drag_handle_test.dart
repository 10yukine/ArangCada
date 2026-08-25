import 'package:arangcada/core/widgets/sheet_drag_handle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('direct drag streams movement without toggling first', (
    tester,
  ) async {
    var dragged = 0.0;
    var ended = false;
    var toggles = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SheetDragHandle(
            expanded: true,
            onToggle: () => toggles++,
            onDragUpdate: (dy) => dragged += dy,
            onDragEnd: (_) => ended = true,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SheetDragHandle)),
    );
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -24));
    await gesture.up();
    await tester.pump();

    expect(dragged, lessThan(0));
    expect(ended, isTrue);
    expect(toggles, 0);
  });
}
