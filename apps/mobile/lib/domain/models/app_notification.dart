/// A single entry in the notifications inbox, reconstructed from real FCM
/// deliveries rather than a fixed mock list.
/// -- deliberately backed by a local Hive cache, not a server table (no
/// cross-device history requirement has been stated yet).
class AppNotificationRecord {
  const AppNotificationRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.receivedAt,
    required this.data,
    required this.read,
  });

  /// The FCM message id when available, otherwise a timestamp-derived
  /// fallback -- either way, stable enough to use as the Hive key so
  /// [markRead] can address one entry without rewriting the whole box.
  final String id;
  final String title;
  final String body;
  final DateTime receivedAt;

  /// The same `data` payload PushNotificationService already routes taps
  /// with (`type`, `trip_id`) -- carried through so the inbox can reuse
  /// that routing instead of inventing a second copy of it.
  final Map<String, dynamic> data;
  final bool read;

  factory AppNotificationRecord.fromJson(String id, Map<String, dynamic> json) {
    return AppNotificationRecord(
      id: id,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      receivedAt:
          DateTime.tryParse(json['receivedAt'] as String? ?? '') ??
          DateTime.now(),
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      read: json['read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'receivedAt': receivedAt.toIso8601String(),
    'data': data,
    'read': read,
  };

  AppNotificationRecord copyWithRead(bool value) => AppNotificationRecord(
    id: id,
    title: title,
    body: body,
    receivedAt: receivedAt,
    data: data,
    read: value,
  );
}
