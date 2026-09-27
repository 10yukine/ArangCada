import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:arangcada_admin/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_fixture.dart';

/// Every console page must lay out without a Flutter layout error (overflow,
/// unbounded size) at common window sizes, in both themes, for both roles,
/// and at 1.3x text on a phone.
void main() {
  const routes = [
    '/dashboard',
    '/live-map',
    '/safety',
    '/drivers',
    '/admins',
    '/discount-claims',
    '/reviews',
    '/evaluation',
    '/evaluation/feedback',
    '/evaluation/responses',
    '/evaluation/iso',
    '/settings',
  ];
  const sizes = [
    Size(1920, 1080),
    Size(1440, 900),
    Size(1024, 768),
    Size(768, 1024),
    Size(390, 844),
  ];
  const sessions = [
    AdminSession(name: 'LGU Evaluator', role: AdminRole.lgu),
    AdminSession(name: 'Coordinator', role: AdminRole.toda, toda: 'Brgy. Real'),
  ];

  tearDown(() {
    auth.value = null;
    adminThemeMode.value = ThemeMode.system;
  });

  for (final session in sessions) {
    for (final route in routes) {
      testWidgets('${session.role.name} $route lays out cleanly everywhere', (
        tester,
      ) async {
        final problems = <String>[];
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          for (final size in sizes) {
            for (final scale in size.width < 600 ? [1.0, 1.3] : [1.0]) {
              await tester.binding.setSurfaceSize(size);
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              adminThemeMode.value = mode;
              auth.value = session;
              await tester.pumpWidget(
                ProviderScope(
                  key: UniqueKey(),
                  overrides: fixtureOverrides,
                  child: AdminApp(initialLocation: route),
                ),
              );
              await tester.pumpAndSettle();
              final error = tester.takeException();
              if (error != null) {
                problems.add(
                  '${mode.name} ${size.width.toInt()}x${size.height.toInt()} '
                  '@${scale}x: ${error.toString().split('\n').first}',
                );
              }
            }
          }
        }
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.binding.setSurfaceSize(null);
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  }
}
