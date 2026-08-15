import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/chat.dart';
import '../repositories/chat_repository.dart';

/// On-device chat transport.
///
/// Messages are stored in memory for the session and never leave the handset.
/// This is not cross-device chat and the UI must not imply that it is. The
/// `sending -> sent` transition is simulated with a short delay purely so the
/// message-status pipeline is exercised end to end; a real backend replaces
/// that delay with an actual acknowledgement.
class LocalChatRepository extends ChangeNotifier implements ChatRepository {
  LocalChatRepository() : _threads = _seedThreads();

  final List<ChatThread> _threads;
  final StreamController<List<ChatThread>> _controller =
      StreamController<List<ChatThread>>.broadcast();
  final List<Timer> _pendingAcks = [];
  int _messageSeq = 0;

  static List<ChatThread> _seedThreads() {
    final now = DateTime.now();
    return [
      ChatThread(
        id: 'thread-active',
        driverName: 'Marco Dela Cruz',
        bodyNumber: '024',
        todaName: 'Calamba TODA',
        isActiveTrip: true,
        unreadCount: 1,
        messages: [
          ChatMessage(
            id: 'm1',
            threadId: 'thread-active',
            author: ChatMessageAuthor.system,
            body: 'Driver assigned',
            sentAt: now.subtract(const Duration(minutes: 6)),
          ),
          ChatMessage(
            id: 'm2',
            threadId: 'thread-active',
            author: ChatMessageAuthor.driver,
            body: 'Otw po',
            sentAt: now.subtract(const Duration(minutes: 5)),
          ),
          ChatMessage(
            id: 'm3',
            threadId: 'thread-active',
            author: ChatMessageAuthor.commuter,
            body: "I'm at the pickup point",
            sentAt: now.subtract(const Duration(minutes: 4)),
          ),
          ChatMessage(
            id: 'm4',
            threadId: 'thread-active',
            author: ChatMessageAuthor.driver,
            body: 'Nandito na po ako',
            sentAt: now.subtract(const Duration(minutes: 3)),
          ),
        ],
      ),
      ChatThread(
        id: 'thread-past-1',
        driverName: 'Ben Aquino',
        bodyNumber: '118',
        todaName: 'Brgy. Real TODA',
        messages: [
          ChatMessage(
            id: 'p1',
            threadId: 'thread-past-1',
            author: ChatMessageAuthor.driver,
            body: 'Salamat po sa pagsakay!',
            sentAt: now.subtract(const Duration(days: 1, hours: 2)),
          ),
        ],
      ),
      ChatThread(
        id: 'thread-past-2',
        driverName: 'Rico Santos',
        bodyNumber: '204',
        todaName: 'Calamba TODA',
        messages: [
          ChatMessage(
            id: 'q1',
            threadId: 'thread-past-2',
            author: ChatMessageAuthor.commuter,
            body: 'Salamat po!',
            sentAt: now.subtract(const Duration(days: 3)),
          ),
        ],
      ),
    ];
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(List.unmodifiable(_threads));
    notifyListeners();
  }

  @override
  Stream<List<ChatThread>> watchThreads() async* {
    yield List.unmodifiable(_threads);
    yield* _controller.stream;
  }

  @override
  List<ChatThread> get threads => List.unmodifiable(_threads);

  @override
  ChatThread? threadById(String id) {
    for (final t in _threads) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  int get totalUnread =>
      _threads.fold(0, (sum, t) => sum + t.unreadCount);

  int _indexOf(String threadId) =>
      _threads.indexWhere((t) => t.id == threadId);

  @override
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String body,
  }) async {
    final index = _indexOf(threadId);
    if (index < 0) throw StateError('Unknown chat thread: $threadId');
    final thread = _threads[index];
    if (thread.isReadOnly) {
      throw StateError('This conversation is closed.');
    }

    final trimmed = body.trim();
    if (trimmed.isEmpty) throw ArgumentError('Message body is empty');

    final message = ChatMessage(
      id: 'local-${++_messageSeq}-${DateTime.now().microsecondsSinceEpoch}',
      threadId: threadId,
      author: ChatMessageAuthor.commuter,
      body: trimmed,
      sentAt: DateTime.now(),
      status: ChatMessageStatus.sending,
    );

    _threads[index] = thread.copyWith(
      messages: [...thread.messages, message],
    );
    _emit();

    // Stands in for a transport acknowledgement. Tracked so it can be
    // cancelled on dispose rather than firing against a dead notifier.
    late Timer timer;
    timer = Timer(const Duration(milliseconds: 350), () {
      _pendingAcks.remove(timer);
      _markStatus(threadId, message.id, ChatMessageStatus.sent);
    });
    _pendingAcks.add(timer);

    return message;
  }

  void _markStatus(
    String threadId,
    String messageId,
    ChatMessageStatus status,
  ) {
    final index = _indexOf(threadId);
    if (index < 0) return;
    final thread = _threads[index];
    final updated = thread.messages
        .map((m) => m.id == messageId ? m.copyWith(status: status) : m)
        .toList();
    _threads[index] = thread.copyWith(messages: updated);
    _emit();
  }

  @override
  Future<void> retryMessage({
    required String threadId,
    required String messageId,
  }) async {
    _markStatus(threadId, messageId, ChatMessageStatus.sending);
    late Timer timer;
    timer = Timer(const Duration(milliseconds: 350), () {
      _pendingAcks.remove(timer);
      _markStatus(threadId, messageId, ChatMessageStatus.sent);
    });
    _pendingAcks.add(timer);
  }

  @override
  Future<void> markRead(String threadId) async {
    final index = _indexOf(threadId);
    if (index < 0) return;
    if (_threads[index].unreadCount == 0) return;
    _threads[index] = _threads[index].copyWith(unreadCount: 0);
    _emit();
  }

  @override
  void dispose() {
    for (final t in _pendingAcks) {
      t.cancel();
    }
    _pendingAcks.clear();
    _controller.close();
    super.dispose();
  }
}
