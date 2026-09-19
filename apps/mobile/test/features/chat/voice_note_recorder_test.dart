import 'dart:async';
import 'dart:typed_data';

import 'package:arangcada/features/chat/voice_note_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRecorder extends VoiceRecorder {
  bool denied = false;
  bool disposed = false;
  int stops = 0;
  @override
  Future<void> start() async {
    if (denied) throw StateError('Microphone permission is required.');
  }

  @override
  Future<Uint8List> stop() async {
    stops++;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  testWidgets('permission failure never sends and discard releases recorder', (
    tester,
  ) async {
    final recorder = FakeRecorder()..denied = true;
    var sent = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceNoteRecorder(
            recorder: recorder,
            onSend: (_, _, _) async {
              sent = true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone permission is required.'), findsOneWidget);
    expect(sent, false);
    await tester.pumpWidget(const SizedBox());
    expect(recorder.disposed, true);
  });
  testWidgets(
    'failed send retains audio and retries same ID; background stops capture',
    (tester) async {
      final recorder = FakeRecorder();
      final ids = <String>[];
      final pending = Completer<void>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceNoteRecorder(
              recorder: recorder,
              onSend: (id, bytes, duration) async {
                ids.add(id);
                expect(bytes, [1, 2, 3]);
                expect(duration, greaterThanOrEqualTo(500));
                if (ids.length == 1) throw StateError('offline');
                await pending.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Record'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(recorder.stops, 1);
      expect(ids, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.text('Send voice message'));
      await tester.pumpAndSettle();
      expect(find.text('Retry send'), findsOneWidget);
      await tester.tap(find.text('Retry send'));
      await tester.pump();
      expect(ids.length, 2);
      expect(ids.first, ids.last);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Discard and close'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(recorder.disposed, true);
      expect(tester.takeException(), isNull);
    },
  );
}
