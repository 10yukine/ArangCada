import '../../domain/models/app_notification.dart';
import '../repositories/notifications_repository.dart';
import 'push/push_notification_service.dart';

/// Thin wrapper over PushNotificationService's own history/markRead --
/// that service already owns the Hive box (it is the writer, from
/// `onMessage`/`onMessageOpenedApp`), so this is the one reader rather than
/// a second class touching the same box with its own key/JSON conventions.
class HiveNotificationsRepository implements NotificationsRepository {
  const HiveNotificationsRepository();

  @override
  List<AppNotificationRecord> history() => PushNotificationService.history();

  @override
  Future<void> markRead(String id) => PushNotificationService.markRead(id);
}
