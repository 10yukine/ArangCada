import 'package:arangcada/app/app.dart';
import 'package:arangcada/core/widgets/arangcada_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('anonymous bootstrap shows login without visible test tools', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: ArangCadaApp()));
    await tester.pumpAndSettle();
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Test accounts'), findsNothing);
  });

  testWidgets('the brand easter egg no longer reveals test accounts', (
    WidgetTester tester,
  ) async {
    // This test used to assert the OPPOSITE: that tapping the brand five times
    // revealed a panel of @arangcada.demo logins with the password printed on
    // screen. That panel was removed while preparing for the pilot beta, so the
    // old test failed -- correctly, but for a reason that looked like a bug.
    //
    // Inverted rather than deleted. A removal like this is exactly the kind of
    // thing that gets quietly reinstated by a later UI change, and an assertion
    // is the only thing that would notice.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: ArangCadaApp()));
    await tester.pumpAndSettle();

    for (var tap = 0; tap < 5; tap++) {
      await tester.tap(find.byType(ArangCadaMark));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Test accounts'), findsNothing);
    expect(
      find.textContaining('demo1234'),
      findsNothing,
      reason: 'a demo password must never be printed on the login screen',
    );
    expect(
      find.textContaining('@arangcada.demo'),
      findsNothing,
      reason: 'demo account addresses must not be advertised to users',
    );
  });
}
