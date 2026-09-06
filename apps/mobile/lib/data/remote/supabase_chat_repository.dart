import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/chat.dart';
import '../repositories/chat_repository.dart';
import 'supabase_ride_repository.dart';

/// Participant-only trip chat, retained read-only for 30 days after a ride.
class SupabaseChatRepository extends ChangeNotifier implements ChatRepository {
  SupabaseChatRepository(this._client, this._rides) {
    _rides.addListener(_synchronizeTrips);
    _synchronizeTrips();
  }

  static const _uuid = Uuid();
  static const _activeStatuses = {
    'accepted',
    'driver_en_route',
    'arrived',
    'in_progress',
    'emergency_reported',
  };

  final SupabaseClient _client;
  final SupabaseRideRepository _rides;
  final StreamController<List<ChatThread>> _changes =
      StreamController<List<ChatThread>>.broadcast();
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>> _listeners =
      {};
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, int> _unread = {};
  final Set<String> _initializedTrips = {};
  // Resolved counterpart avatar URLs, keyed by trip id. Populated
  // asynchronously (see _loadCounterpartAvatar) since Storage signed-URL
  // minting cannot happen inside the synchronous _threadFromTrip mapping --
  // same reasoning and shape as SupabaseRideRepository's identical cache.
  final Map<String, String?> _counterpartAvatars = {};
  List<ChatThread> _threads = const [];
  bool _disposed = false;

  String get _userId => _client.auth.currentUser!.id;

  void _synchronizeTrips() {
    if (_disposed) return;
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final visible = <Map<String, dynamic>>[];
    for (final trip in _rides.trips) {
      final status = trip['status'] as String?;
      if (trip['driver_id'] == null ||
          (!_activeStatuses.contains(status) && status != 'completed')) {
        continue;
      }
      final completed = trip['completed_at'] as String?;
      if (completed != null &&
          DateTime.parse(completed).toUtc().isBefore(cutoff)) {
        continue;
      }
      visible.add(trip);
    }

    final visibleIds = visible.map((trip) => trip['id'] as String).toSet();
    for (final id in _listeners.keys.toList()) {
      if (!visibleIds.contains(id)) {
        unawaited(_listeners.remove(id)?.cancel());
        _messages.remove(id);
        _unread.remove(id);
      }
    }
    for (final trip in visible) {
      final id = trip['id'] as String;
      _listeners.putIfAbsent(
        id,
        () => _client
            .from('trip_messages')
            .stream(primaryKey: ['id'])
            .eq('trip_id', id)
            // SupabaseStreamBuilder.order() defaults to ascending: false
            // (descending / newest-first) -- the OPPOSITE of the regular
            // query builder's documented convention and easy to miss, since
            // nothing here read like it needed the flag. Without it, every
            // realtime snapshot arrived newest-first, _messages[tripId] got
            // populated in that order, and ListView.builder (no reverse:
            // true) rendered the newest message at the top of the thread.
            // Confirmed against the installed postgrest/supabase package
            // source, not assumed.
            .order('created_at', ascending: true)
            .listen((rows) => _receiveMessages(trip, rows), onError: (_) {}),
      );
      if (!_counterpartAvatars.containsKey(id)) {
        unawaited(_loadCounterpartAvatar(id));
      }
    }
    _threads = visible.map(_threadFromTrip).toList(growable: false);
    _emit();
  }

  ChatThread _threadFromTrip(Map<String, dynamic> trip) {
    final id = trip['id'] as String;
    return ChatThread(
      id: id,
      tripId: id,
      commuterName: trip['rider_display_name'] as String? ?? 'Commuter',
      driverName: trip['driver_display_name'] as String? ?? 'Driver',
      bodyNumber: trip['driver_body_number'] as String? ?? 'Verified driver',
      todaName: trip['toda_name'] as String? ?? 'Assigned TODA',
      messages: List.unmodifiable(_messages[id] ?? const <ChatMessage>[]),
      unreadCount: _unread[id] ?? 0,
      isActiveTrip: _activeStatuses.contains(trip['status']),
      counterpartAvatarUrl: _counterpartAvatars[id],
    );
  }

  /// Best-effort only -- same reasoning as
  /// SupabaseRideRepository._loadCounterpartAvatar, which this mirrors: a
  /// photo is cosmetic, never load-bearing, so any failure just leaves the
  /// initials fallback in place. Re-runs _synchronizeTrips() on success
  /// rather than emitting directly, so _threads is rebuilt from the same
  /// single source of truth (_rides.trips) instead of patched in two places.
  Future<void> _loadCounterpartAvatar(String tripId) async {
    try {
      final path = await _client.rpc(
        'trip_counterpart_avatar_path',
        params: {'p_trip_id': tripId},
      ) as String?;
      if (_disposed) return;
      final url = path == null
          ? null
          : await _client.storage
                .from('profile-photos')
                .createSignedUrl(path, 300);
      if (_disposed) return;
      _counterpartAvatars[tripId] = url;
      _synchronizeTrips();
    } catch (_) {
      // Swallow -- see the best-effort note above. Deliberately does not
      // cache a failure into _counterpartAvatars, so a transient error
      // (e.g. offline) gets retried the next time _synchronizeTrips() runs
      // rather than permanently giving up on this trip's photo.
    }
  }

  void _receiveMessages(
    Map<String, dynamic> trip,
    List<Map<String, dynamic>> rows,
  ) {
    if (_disposed) return;
    final tripId = trip['id'] as String;
    final previous = _messages[tripId] ?? const <ChatMessage>[];
    final priorIds = previous
        .where((message) => message.remoteId != null)
        .map((message) => message.remoteId)
        .toSet();
    final remote = rows
        .map((row) {
          final sender = row['sender_id'] as String;
          final id = row['id'] as String;
          return ChatMessage(
            id: id,
            remoteId: id,
            threadId: tripId,
            author: sender == trip['driver_id']
                ? ChatMessageAuthor.driver
                : ChatMessageAuthor.commuter,
            body: row['body'] as String,
            sentAt: DateTime.parse(row['created_at'] as String).toLocal(),
          );
        })
        .toList(growable: false);

    if (_initializedTrips.contains(tripId)) {
      final newIncoming = rows.where((row) {
        return row['sender_id'] != _userId && !priorIds.contains(row['id']);
      }).length;
      _unread[tripId] = (_unread[tripId] ?? 0) + newIncoming;
    }
    _initializedTrips.add(tripId);
    final optimistic = previous.where((message) {
      return message.remoteId == null &&
          message.status != ChatMessageStatus.sent;
    });
    _messages[tripId] = [...remote, ...optimistic];
    _rebuildThreads();
  }

  void _rebuildThreads() {
    _threads = _threads
        .map((thread) {
          return thread.copyWith(
            messages: _messages[thread.id] ?? const [],
            unreadCount: _unread[thread.id] ?? 0,
          );
        })
        .toList(growable: false);
    _emit();
  }

  void _emit() {
    if (_disposed) return;
    _changes.add(List.unmodifiable(_threads));
    notifyListeners();
  }

  @override
  Stream<List<ChatThread>> watchThreads() async* {
    yield List.unmodifiable(_threads);
    yield* _changes.stream;
  }

  @override
  List<ChatThread> get threads => List.unmodifiable(_threads);

  String? get activeThreadId {
    for (final thread in _threads) {
      if (thread.isActiveTrip) return thread.id;
    }
    return null;
  }

  String _resolveId(String id) => id == 'thread-active'
      ? (activeThreadId ?? (_rides.activeTrip?['id'] as String?) ?? id)
      : id;

  @override
  ChatThread? threadById(String id) {
    final resolved = _resolveId(id);
    for (final thread in _threads) {
      if (thread.id == resolved) return thread;
    }
    return null;
  }

  @override
  int get totalUnread => _threads.fold(0, (count, thread) {
    return count + thread.unreadCount;
  });

  @override
  ChatThread ensureActiveTripThread({
    required String commuterName,
    required String driverName,
    required String bodyNumber,
    required String todaName,
  }) {
    _synchronizeTrips();
    final thread = threadById('thread-active');
    if (thread == null) {
      throw StateError('Chat opens after the driver accepts the ride.');
    }
    return thread;
  }

  @override
  void closeActiveTripThread() => _synchronizeTrips();

  @override
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String body,
    required ChatMessageAuthor author,
  }) async {
    final resolved = _resolveId(threadId);
    final thread = threadById(resolved);
    if (thread == null) throw StateError('Conversation not found.');
    if (thread.isReadOnly) throw StateError('This conversation is closed.');
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.length > 1000) {
      throw StateError('Messages must contain 1 to 1,000 characters.');
    }

    final pending = ChatMessage(
      id: 'pending-${_uuid.v4()}',
      threadId: resolved,
      author: author,
      body: trimmed,
      sentAt: DateTime.now(),
      status: ChatMessageStatus.sending,
    );
    _messages[resolved] = [...?_messages[resolved], pending];
    _rebuildThreads();

    try {
      final result = await _client.rpc(
        'send_trip_message',
        params: {'p_trip_id': resolved, 'p_body': trimmed},
      );
      final row = result is List
          ? Map<String, dynamic>.from(result.first as Map)
          : Map<String, dynamic>.from(result as Map);
      final remoteId = row['id'] as String;
      final acknowledged = ChatMessage(
        id: remoteId,
        remoteId: remoteId,
        threadId: resolved,
        author: author,
        body: trimmed,
        sentAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
      _messages[resolved] = (_messages[resolved] ?? [])
          .where((message) {
            return message.id != pending.id && message.remoteId != remoteId;
          })
          .followedBy([acknowledged])
          .toList();
      _rebuildThreads();
      return acknowledged;
    } on Exception {
      _setMessageStatus(resolved, pending.id, ChatMessageStatus.failed);
      throw StateError('Message could not be sent. Tap Retry.');
    }
  }

  void _setMessageStatus(
    String threadId,
    String messageId,
    ChatMessageStatus status,
  ) {
    _messages[threadId] = (_messages[threadId] ?? []).map((message) {
      return message.id == messageId
          ? message.copyWith(status: status)
          : message;
    }).toList();
    _rebuildThreads();
  }

  @override
  Future<void> retryMessage({
    required String threadId,
    required String messageId,
  }) async {
    final resolved = _resolveId(threadId);
    final failed = (_messages[resolved] ?? []).firstWhere(
      (message) => message.id == messageId,
    );
    _messages[resolved] = (_messages[resolved] ?? [])
        .where((message) => message.id != messageId)
        .toList();
    await sendMessage(
      threadId: resolved,
      body: failed.body,
      author: failed.author,
    );
  }

  @override
  Future<void> markRead(String threadId) async {
    final resolved = _resolveId(threadId);
    if ((_unread[resolved] ?? 0) == 0) return;
    _unread[resolved] = 0;
    _rebuildThreads();
  }

  @override
  Future<void> markUnread(String threadId) async {
    final resolved = _resolveId(threadId);
    if ((_unread[resolved] ?? 0) != 0) return;
    _unread[resolved] = 1;
    _rebuildThreads();
  }

  @override
  void clearSession() {
    for (final subscription in _listeners.values) {
      unawaited(subscription.cancel());
    }
    _listeners.clear();
    _messages.clear();
    _unread.clear();
    _threads = const [];
    _emit();
  }

  @override
  void dispose() {
    _rides.removeListener(_synchronizeTrips);
    clearSession();
    _disposed = true;
    unawaited(_changes.close());
    super.dispose();
  }
}
