import 'dart:convert';
import 'dart:io';

import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/remote/push/push_notification_service.dart';
import 'package:arangcada/data/remote/supabase_auth_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/models/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sign_out_cleanup_test_');
    Hive.init(directory.path);
    await Hive.openBox<String>(PushNotificationService.notificationsBoxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  // The inbox is one Hive box per device, not per account. Without this the
  // next person to sign in on a shared phone reads the last account's ride
  // notifications (driver names, pickup places).
  test('signing out empties the notification inbox', () async {
    final record = AppNotificationRecord(
      id: 'message-1',
      title: 'Driver on the way',
      body: 'Mang Ben is heading to your pickup.',
      receivedAt: DateTime(2026, 10, 1),
      data: const {'type': 'trip_update'},
      read: false,
    );
    await Hive.box<String>(
      PushNotificationService.notificationsBoxName,
    ).put(record.id, jsonEncode(record.toJson()));
    expect(PushNotificationService.history(), hasLength(1));

    final client = SupabaseClient(
      'https://example.test',
      'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );
    // The same goes for what is held in memory: the next account must not open
    // on the last one's destination or trip.
    final state = DemoState()
      ..setDestination(DemoData.places.first)
      ..liveTripId = 'trip-1';
    await SupabaseAuthRepository(client, state).signOut();

    expect(PushNotificationService.history(), isEmpty);
    expect(state.destination, isNull);
    expect(state.liveTripId, isNull);
  });
}
