import '../../domain/models/app_notification.dart';

/// The notifications inbox's read/write seam. See .pipeline/specs.md
/// Spec 16 -- backed by a local Hive cache PushNotificationService already
/// writes to (`onMessage`/`onMessageOpenedApp`), not a server table.
abstract interface class NotificationsRepository {
  /// All recorded notifications, newest first.
  List<AppNotificationRecord> history();

  /// Marks one entry read in place.
  Future<void> markRead(String id);
}
