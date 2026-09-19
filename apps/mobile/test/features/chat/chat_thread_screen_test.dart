import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/core/widgets/arang_ui.dart';
import 'package:arangcada/data/mock/local_chat_repository.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/chat/chat_thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quick replies preserve the draft even when its text matches', (
    tester,
  ) async {
    final state = DemoState();
    final chat = LocalChatRepository()..setSampleContent(true);
    addTearDown(state.dispose);
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoStateProvider.overrideWithValue(state),
          chatRepositoryProvider.overrideWithValue(chat),
          liveRideRepositoryProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: ChatThreadScreen(threadId: 'thread-active'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final draft in ['Please wait near the gate', 'Where po kayo?']) {
      await tester.enterText(find.byType(TextField), draft);
      final count = chat.threadById('thread-active')!.messages.length;
      await tester.tap(find.widgetWithText(ArangChip, 'Where po kayo?'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        draft,
      );
      expect(
        chat.threadById('thread-active')!.messages.last.body,
        'Where po kayo?',
      );
      expect(chat.threadById('thread-active')!.messages.length, count + 1);
    }
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(
      chat.threadById('thread-active')!.messages.last.body,
      'Where po kayo?',
    );
    expect(tester.takeException(), isNull);
  });

  for (final role in DemoRole.values) {
    testWidgets('${role.name} views the other participant’s profile', (
      tester,
    ) async {
      final state = DemoState()
        ..setCurrentUser(
          DemoUser(
            email: '${role.name}@arangcada.demo',
            displayName: 'Viewer',
            role: role,
          ),
        );
      final chat = LocalChatRepository()..setSampleContent(true);
      addTearDown(state.dispose);
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            chatRepositoryProvider.overrideWithValue(chat),
            liveRideRepositoryProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: ChatThreadScreen(threadId: 'thread-active'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Report conversation'), findsOneWidget);
      await tester.tap(find.text('View profile'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(
            role == DemoRole.driver ? 'Joshua Ramos' : 'Marco Dela Cruz',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('Body no. 024 · Calamba TODA'),
        ),
        role == DemoRole.driver ? findsNothing : findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report conversation'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No report will be sent or recorded'),
        findsOneWidget,
      );
      expect(find.text('Submit report'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        find.text('Report recorded for ArangCada administrators.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
