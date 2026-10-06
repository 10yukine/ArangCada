import 'package:arangcada/app/auth_captcha.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cloudflare's box asks "Verify you are human" in English. A driver who has
/// never met one gets a line above it saying what to do, and only then.
void main() {
  Future<void> show(WidgetTester tester, double? open) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            CaptchaSlotLayout(
              open: open,
              child: const Text('the check page', key: Key('page')),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('shut, it shows nothing and says nothing', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, null);

    expect(find.textContaining('I-tap ang kahon'), findsNothing);
    expect(tester.getSize(find.byType(CaptchaSlotLayout)).height, 1);
    expect(find.bySemanticsLabel('the check page'), findsNothing);
    handle.dispose();
  });

  testWidgets('when a tap is wanted, a line above the box says so', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, 81);

    final hint = find.text('I-tap ang kahon para magpatuloy.');
    expect(hint, findsOneWidget);
    expect(find.text('Tap the box to continue.'), findsOneWidget);
    // Starting where Cloudflare's box starts, not centred over it.
    expect(tester.getTopLeft(hint).dx, 8);
    expect(tester.getTopLeft(find.text('Tap the box to continue.')).dx, 8);
    // Above the box, and the box at the height Cloudflare asked for.
    expect(
      tester.getBottomLeft(hint).dy,
      lessThan(tester.getTopLeft(find.byType(ClipRect).first).dy),
    );
    expect(tester.getSize(find.byType(ClipRect).first).height, 81);
    expect(find.bySemanticsLabel('the check page'), findsOneWidget);
    handle.dispose();
  });
}
