import 'package:flutter/foundation.dart';

import '../../domain/models/chat.dart';

/// Chat transport boundary.
///
/// The only implementation today is [LocalChatRepository], which keeps threads
/// on the device. A future `SupabaseChatRepository` backed by Realtime can
/// replace it without any screen change, which is why `sendMessage` returns
/// the stored message (so a backend can hand back a server id and timestamp)
/// and why `watchThreads` is a stream rather than a getter.
abstract class ChatRepository implements Listenable {
  Stream<List<ChatThread>> watchThreads();

  List<ChatThread> get threads;

  ChatThread? threadById(String id);

  int get totalUnread;

  /// Appends a commuter message. Implementations must surface a `sending`
  /// state before `sent` so the UI never shows an unacknowledged message as
  /// delivered.
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String body,
  });

  Future<void> retryMessage({
    required String threadId,
    required String messageId,
  });

  Future<void> markRead(String threadId);
}
