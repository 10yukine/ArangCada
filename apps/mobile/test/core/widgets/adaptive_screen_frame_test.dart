import 'package:arangcada/app/shells/commuter_shell.dart';
import 'package:arangcada/app/theme/app_dimensions.dart';
import 'package:arangcada/core/widgets/adaptive_screen_frame.dart';
import 'package:arangcada/core/widgets/floating_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds a [ConstrainedBox] that caps width at [AppSizes.maxContentWidth] --
/// the one [AdaptiveScreenFrame] adds -- distinct from any ambient
/// `BoxConstraints.biggest` box the framework's own view/app boilerplate
/// inserts regardless of this widget.
final _frameConstraint = find.byWidgetPredicate(
  (widget) =>
      widget is ConstrainedBox &&
      widget.constraints.maxWidth == AppSizes.maxContentWidth,
);

void _setWidth(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('AdaptiveScreenFrame', () {
    testWidgets('renders the child unconstrained below the compact breakpoint', (
      tester,
    ) async {
      _setWidth(tester, 360);

      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptiveScreenFrame(child: Text('Screen content')),
        ),
      );

      expect(find.text('Screen content'), findsOneWidget);
      expect(_frameConstraint, findsNothing);
    });

    testWidgets(
      'caps content to AppSizes.maxContentWidth at AppBreakpoints.compact and above',
      (tester) async {
        _setWidth(tester, 900);

        await tester.pumpWidget(
          const MaterialApp(
            home: AdaptiveScreenFrame(child: Text('Screen content')),
          ),
        );

        expect(find.text('Screen content'), findsOneWidget);
        expect(_frameConstraint, findsOneWidget);
      },
    );
  });

  group('AdaptiveTabShell', () {
    const destinations = [
      FloatingTabDestination(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
        label: 'Home',
      ),
      FloatingTabDestination(
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
        label: 'Profile',
      ),
    ];

    testWidgets('shows the bottom FloatingTabBar below the compact breakpoint', (
      tester,
    ) async {
      _setWidth(tester, 360);

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveTabShell(
            selectedIndex: 0,
            onSelected: (_) {},
            destinations: destinations,
            body: const SizedBox.shrink(),
          ),
        ),
      );

      expect(find.byType(FloatingTabBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets(
      'shows a NavigationRail at AppBreakpoints.compact and above',
      (tester) async {
        _setWidth(tester, 900);

        await tester.pumpWidget(
          MaterialApp(
            home: AdaptiveTabShell(
              selectedIndex: 0,
              onSelected: (_) {},
              destinations: destinations,
              body: const SizedBox.shrink(),
            ),
          ),
        );

        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(FloatingTabBar), findsNothing);
      },
    );
  });
}
