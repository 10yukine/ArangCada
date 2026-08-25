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

  testWidgets('hidden test accounts remain reachable on short screens', (
    WidgetTester tester,
  ) async {
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

    expect(find.text('Driver').hitTestable(), findsNothing);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Driver').hitTestable(), findsOneWidget);
  });
}
