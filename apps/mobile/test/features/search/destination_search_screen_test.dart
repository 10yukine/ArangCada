import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/features/search/destination_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('search and shortcuts remain reachable above a tall keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final state = DemoState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoStateProvider.overrideWithValue(state)],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: const DestinationSearchScreen(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pin on map'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Pin on map').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
