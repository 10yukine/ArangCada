import 'package:arangcada_admin/theme.dart';
import 'package:arangcada_admin/screens/shared_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation moves vertically without resizing the page', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    const pageKey = ValueKey('destination');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: adminTheme(),
        home: const Scaffold(),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const SizedBox.expand(
          key: pageKey,
          child: ColoredBox(color: Colors.blue),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final movingSize = tester.getSize(find.byKey(pageKey));
    final movingY = tester.getTopLeft(find.byKey(pageKey)).dy;
    expect(movingY, greaterThan(0));
    expect(
      find.ancestor(
        of: find.byKey(pageKey),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(pageKey)), movingSize);
    expect(tester.getTopLeft(find.byKey(pageKey)).dy, 0);
  });

  testWidgets('reduced motion shows the destination without movement', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    const pageKey = ValueKey('destination');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: adminTheme(),
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const SizedBox.expand(
          key: pageKey,
          child: ColoredBox(color: Colors.blue),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getTopLeft(find.byKey(pageKey)).dy, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('review columns stretch together as details expand', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final height = ValueNotifier<double>(160);
    addTearDown(height.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<double>(
              valueListenable: height,
              builder: (_, value, _) => ReviewWorkspace(
                showDetail: true,
                onBack: () {},
                queue: const ColoredBox(
                  key: ValueKey('queue'),
                  color: Colors.white,
                  child: SizedBox(height: 80),
                ),
                detail: ColoredBox(
                  key: const ValueKey('detail'),
                  color: Colors.blue,
                  child: SizedBox(height: value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('queue'))).height, 160);
    height.value = 420;
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('queue'))).height, 420);
    expect(tester.getSize(find.byKey(const ValueKey('detail'))).height, 420);
  });
}
