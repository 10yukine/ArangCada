import 'package:arangcada/domain/models/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toJson/fromJson round-trips every field', () {
    final original = AppNotificationRecord(
      id: 'msg-1',
      title: 'Driver assigned',
      body: 'Marco Dela Cruz is heading to your pickup point.',
      receivedAt: DateTime.utc(2026, 9, 6, 12, 30),
      data: const {'type': 'ride_offer', 'trip_id': 'trip-123'},
      read: false,
    );

    final restored = AppNotificationRecord.fromJson(
      original.id,
      original.toJson(),
    );

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.body, original.body);
    expect(restored.receivedAt, original.receivedAt);
    expect(restored.data, original.data);
    expect(restored.read, original.read);
  });

  test('copyWithRead flips only the read flag', () {
    final original = AppNotificationRecord(
      id: 'msg-1',
      title: 'Title',
      body: 'Body',
      receivedAt: DateTime.utc(2026, 9, 6),
      data: const {},
      read: false,
    );

    final read = original.copyWithRead(true);

    expect(read.read, isTrue);
    expect(read.id, original.id);
    expect(read.title, original.title);
    expect(read.body, original.body);
    expect(read.receivedAt, original.receivedAt);
  });

  test(
    'fromJson tolerates missing/malformed fields instead of throwing -- a '
    'single corrupt Hive entry must not crash the whole inbox',
    () {
      final restored = AppNotificationRecord.fromJson('msg-2', const {});

      expect(restored.title, '');
      expect(restored.body, '');
      expect(restored.data, isEmpty);
      expect(restored.read, isFalse);
      // receivedAt falls back to "now" rather than throwing on an
      // unparsable/absent timestamp.
      expect(
        DateTime.now().difference(restored.receivedAt).inMinutes,
        lessThan(1),
      );
    },
  );
}
