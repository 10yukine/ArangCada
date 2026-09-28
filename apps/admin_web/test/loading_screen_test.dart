import 'package:arangcada_admin/theme.dart';
import 'package:arangcada_admin/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'loading screen follows theme and keeps the mobile splash layout',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      for (final brightness in Brightness.values) {
        final theme = adminTheme(brightness: brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const AdminLoadingScreen(label: 'Restoring your account'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(
          scaffold.backgroundColor,
          brightness == Brightness.light
              ? Colors.white
              : theme.scaffoldBackgroundColor,
        );
        final mark = tester.getRect(find.byType(BrandTile));
        expect(mark.size, const Size(84, 84));
        expect(mark.center, const Offset(195, 422));
        final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(progress.color, theme.colorScheme.primary);
        expect(progress.semanticsLabel, 'Restoring your account');
        final bar = tester.getRect(find.byType(LinearProgressIndicator));
        expect(bar.width, 160);
        expect(bar.height, 3);
        expect(bar.bottom, 820);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
