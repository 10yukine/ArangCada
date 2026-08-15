/// Chat domain models.
///
/// Transport is local for now: no Supabase Realtime table is deployed, so
/// `LocalChatRepository` persists threads on the device only. These models
/// deliberately carry the fields a real backend needs -- `status`, `remoteId`,
/// `sentAt` -- so swapping in a Supabase-backed repository does not change any
/// screen. Nothing here may claim a message reached another physical device.
library;

enum ChatMessageAuthor { commuter, driver, system }

enum ChatMessageStatus { sending, sent, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.author,
    required this.body,
    required this.sentAt,
    this.status = ChatMessageStatus.sent,
    this.remoteId,
  });

  final String id;
  final String threadId;
  final ChatMessageAuthor author;
  final String body;
  final DateTime sentAt;
  final ChatMessageStatus status;

  /// Populated only once a backend acknowledges the message.
  final String? remoteId;

  bool get isSystem => author == ChatMessageAuthor.system;

  ChatMessage copyWith({ChatMessageStatus? status, String? remoteId}) {
    return ChatMessage(
      id: id,
      threadId: threadId,
      author: author,
      body: body,
      sentAt: sentAt,
      status: status ?? this.status,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'threadId': threadId,
    'author': author.name,
    'body': body,
    'sentAt': sentAt.toIso8601String(),
    'status': status.name,
    if (remoteId != null) 'remoteId': remoteId,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    threadId: json['threadId'] as String,
    author: ChatMessageAuthor.values.byName(json['author'] as String),
    body: json['body'] as String,
    sentAt: DateTime.parse(json['sentAt'] as String),
    status: ChatMessageStatus.values.byName(
      json['status'] as String? ?? 'sent',
    ),
    remoteId: json['remoteId'] as String?,
  );
}

class ChatThread {
  const ChatThread({
    required this.id,
    required this.driverName,
    required this.bodyNumber,
    required this.todaName,
    required this.messages,
    this.unreadCount = 0,
    this.isActiveTrip = false,
    this.driverVerified = true,
    this.tripId,
  });

  final String id;
  final String driverName;
  final String bodyNumber;
  final String todaName;
  final List<ChatMessage> messages;
  final int unreadCount;

  /// A thread attached to the ride currently in progress.
  final bool isActiveTrip;
  final bool driverVerified;
  final String? tripId;

  /// Completed rides keep their history but stop accepting new messages,
  /// matching the prototype's read-only past conversations.
  bool get isReadOnly => !isActiveTrip;

  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  String get preview {
    final last = lastMessage;
    if (last == null) return 'No messages yet';
    return last.isSystem ? last.body : last.body;
  }

  ChatThread copyWith({
    List<ChatMessage>? messages,
    int? unreadCount,
    bool? isActiveTrip,
  }) {
    return ChatThread(
      id: id,
      driverName: driverName,
      bodyNumber: bodyNumber,
      todaName: todaName,
      messages: messages ?? this.messages,
      unreadCount: unreadCount ?? this.unreadCount,
      isActiveTrip: isActiveTrip ?? this.isActiveTrip,
      driverVerified: driverVerified,
      tripId: tripId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'driverName': driverName,
    'bodyNumber': bodyNumber,
    'todaName': todaName,
    'unreadCount': unreadCount,
    'isActiveTrip': isActiveTrip,
    'driverVerified': driverVerified,
    if (tripId != null) 'tripId': tripId,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
    id: json['id'] as String,
    driverName: json['driverName'] as String,
    bodyNumber: json['bodyNumber'] as String,
    todaName: json['todaName'] as String,
    unreadCount: json['unreadCount'] as int? ?? 0,
    isActiveTrip: json['isActiveTrip'] as bool? ?? false,
    driverVerified: json['driverVerified'] as bool? ?? true,
    tripId: json['tripId'] as String?,
    messages: (json['messages'] as List<dynamic>? ?? [])
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList(),
  );
}
