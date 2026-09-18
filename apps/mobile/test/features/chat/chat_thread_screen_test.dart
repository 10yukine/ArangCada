import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/local_chat_repository.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/chat/chat_thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
