import 'dart:async';

import 'package:arangcada/domain/models/chat.dart';
import 'package:arangcada/features/chat/voice_note_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final completions = StreamController<void>.broadcast();
  final played = <String>[];
  @override
  PlayerState state = PlayerState.stopped;
  @override
  Stream<PlayerState> get onPlayerStateChanged => states.stream;
  @override
  Stream<Duration> get onPositionChanged => positions.stream;
  @override
  Stream<void> get onPlayerComplete => completions.stream;
  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    played.add((source as UrlSource).url);
    state = PlayerState.playing;
    states.add(state);
  }

  @override
  Future<void> pause() async {
    state = PlayerState.paused;
    states.add(state);
  }

  @override
  Future<void> stop() async {
    state = PlayerState.stopped;
    states.add(state);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  Future<void> close() async {
    await states.close();
    await positions.close();
    await completions.close();
  }
}

void main() {
  final message = ChatMessage(
    id: 'voice',
    threadId: 'trip',
    author: ChatMessageAuthor.driver,
    body: 'Voice message',
    sentAt: DateTime(2026),
    voicePath: 'trip/driver/voice.m4a',
    voiceDurationMs: 2300,
  );
  test('voice metadata survives model serialization and status changes', () {
    final restored = ChatMessage.fromJson(
      message.toJson(),
    ).copyWith(status: ChatMessageStatus.sent);
    expect(restored.voicePath, message.voicePath);
    expect(restored.voiceDurationMs, 2300);
    expect(restored.isVoice, true);
  });
  testWidgets(
    'play/pause, duration, refreshed URL on resume and retry after failure',
    (tester) async {
      final player = FakePlayer();
      final selected = ValueNotifier<String?>(null);
      var loads = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceNotePlayer(
              message: message,
              player: player,
              selected: selected,
              color: Colors.black,
              loadUrl: () async {
                loads++;
                if (loads == 1) throw StateError('offline');
                return 'https://example.test/$loads';
              },
            ),
          ),
        ),
      );
      expect(find.text('0s / 3s'), findsOneWidget);
      await tester.tap(find.byTooltip('Play voice message'));
      await tester.pumpAndSettle();
      expect(find.text('Cannot play. Tap to retry.'), findsOneWidget);
      await tester.tap(find.byTooltip('Play voice message'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause voice message'), findsOneWidget);
      player.positions.add(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('1s / 3s'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause voice message'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play voice message'));
      await tester.pumpAndSettle();
      expect(loads, 3);
      expect(player.played, [
        'https://example.test/2',
        'https://example.test/3',
      ]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(player.state, PlayerState.paused);
      await tester.pumpWidget(const SizedBox());
      await player.close();
      selected.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
  testWidgets('late URL cannot start playback after leaving bubble', (
    tester,
  ) async {
    final player = FakePlayer();
    final selected = ValueNotifier<String?>(null);
    final pending = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceNotePlayer(
            message: message,
            player: player,
            selected: selected,
            color: Colors.black,
            loadUrl: () => pending.future,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Play voice message'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete('https://example.test/late');
    await tester.pump();
    expect(player.played, isEmpty);
    await player.close();
    selected.dispose();
  });
}
