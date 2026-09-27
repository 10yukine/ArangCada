import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/features/wallet/wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'wallet disables beta actions and keeps sandbox disclosure',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = DemoState();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [demoStateProvider.overrideWithValue(state)],
          child: MaterialApp(theme: AppTheme.light, home: const WalletScreen()),
        ),
      );

      expect(find.text('Digital balance'), findsOneWidget);
      expect(find.text('₱0.00'), findsOneWidget);
      expect(find.text('SANDBOX'), findsOneWidget);
      expect(find.text('Top Up'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(
        find.text('Wallet unavailable during beta testing'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('wallet-coming-soon-barrier')),
        findsOneWidget,
      );
      expect(find.text('Top Up').hitTestable(), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Top Up'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Transactions'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('No wallet transactions'), findsOneWidget);
      expect(find.textContaining('provider-held'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wallet keeps top-up, ride debit, and refund history visible', (
    tester,
  ) async {
    final state = DemoState()..setSampleContent(true);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoStateProvider.overrideWithValue(state)],
        child: MaterialApp(theme: AppTheme.light, home: const WalletScreen()),
      ),
    );

    expect(find.text('₱350.00'), findsOneWidget);
    expect(find.text('Ride Payment'), findsOneWidget);
    expect(find.text('Refund'), findsOneWidget);
    expect(find.text('No wallet transactions'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
