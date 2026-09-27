import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/core/widgets/trip_share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> _open(WidgetTester tester, Future<Uri> Function() link) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showTripShareSheet(context, createLink: link),
              child: const Text('Share'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Share'));
  await tester.pumpAndSettle();
}

void main() {
  test('tracking links use the /t/<token> route', () {
    expect(
      tripTrackingUri('abc_123-x').toString(),
      'https://track.arangcada.app/t/abc_123-x',
    );
  });

  testWidgets('copies the live link for any chat app', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _open(tester, () async => tripTrackingUri('tok123'));
    expect(find.text('https://track.arangcada.app/t/tok123'), findsOneWidget);

    await tester.tap(find.text('Copy link'));
    await tester.pump();
    expect(copied, 'https://track.arangcada.app/t/tok123');
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('shows the server refusal as a sentence', (tester) async {
    await _open(
      tester,
      () async =>
          throw const PostgrestException(message: 'this trip has already ended'),
    );
    expect(find.text('This trip has already ended.'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });
}
