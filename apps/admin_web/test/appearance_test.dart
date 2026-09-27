import 'package:arangcada_admin/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('appearance icons select and save each mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    adminThemeMode.value = ThemeMode.system;
    addTearDown(() => adminThemeMode.value = ThemeMode.system);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdminAppearanceButton()),
    ));
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    for (final label in ['Dark', 'Light', 'System']) {
      await tester.tap(find.byTooltip('Appearance'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byIcon(Icons.check)).dx,
          greaterThan(tester.getTopRight(find.text(
            switch (adminThemeMode.value) {
              ThemeMode.system => 'System',
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
            },
          )).dx));
      await tester.tap(find.widgetWithText(PopupMenuItem<ThemeMode>, label));
      await tester.pumpAndSettle();
      expect(adminThemeMode.value.name, label.toLowerCase());
      expect((await SharedPreferences.getInstance()).getString('admin-appearance'), label.toLowerCase());
    }
  });
}
