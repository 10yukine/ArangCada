import 'dart:typed_data';

import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/supabase_admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('server-authoritative administrator sessions', () {
    test('a citywide admin is resolved from the trusted profile', () {
      final session = AdminSession.fromProfile({
        'id': '31f15b01-8114-41e6-9bde-901ad9a58295',
        'role': 'admin',
        'display_name': 'LGU Evaluator',
        'status': 'active',
      }, email: 'lgu.evaluator@arangcada.example.com');

      expect(session.role, AdminRole.lgu);
      expect(session.userId, '31f15b01-8114-41e6-9bde-901ad9a58295');
      expect(session.connected, isTrue);
      expect(session.toda, isNull);
      expect(session.email, 'lgu.evaluator@arangcada.example.com');
      expect(session.initials, 'LE');
      expect(session.roleLabel, 'LGU administrator');
      expect(session.deskLabel, 'LGU transport desk');
    });

    test('a TODA administrator inherits only the assigned server scope', () {
      final session = AdminSession.fromProfile(
        {
          'id': '28b42fba-c52c-48a8-a447-2dd89191d68a',
          'role': 'admin',
          'display_name': 'SJVTODA Coordinator',
          'status': 'active',
        },
        todaZoneId: '2917d4ee-69d0-494c-ab51-438f2614cce4',
        toda: 'SJVTODA',
      );

      expect(session.role, AdminRole.toda);
      expect(session.todaZoneId, '2917d4ee-69d0-494c-ab51-438f2614cce4');
      expect(session.toda, 'SJVTODA');
    });

    test(
      'commuters, drivers, and suspended admins cannot open the console',
      () {
        for (final profile in [
          {'id': '1', 'role': 'commuter', 'status': 'active'},
          {'id': '2', 'role': 'driver', 'status': 'active'},
          {'id': '3', 'role': 'admin', 'status': 'suspended'},
        ]) {
          expect(
            () => AdminSession.fromProfile(profile),
            throwsA(isA<StateError>()),
          );
        }
      },
    );
  });

  group('driver app feedback privacy and measurement', () {
    test('anonymous responses never expose a returned driver name', () {
      final response = DriverAppFeedback.fromRow({
        'id': 'feedback-1',
        'toda_name': 'SJVTODA',
        'is_anonymous': true,
        'driver_name': 'Name that must never be rendered',
        'answers': {
          'ease_of_use': 5,
          'booking_clarity': 4,
          'navigation_clarity': 4,
          'fare_fairness': 5,
          'reliability': 4,
          'safety_confidence': 5,
          'continued_use': 5,
        },
        'comment': 'Mas malinaw ang pila.',
        'created_at': '2026-08-25T10:00:00Z',
      });

      expect(response.anonymous, isTrue);
      expect(response.displayName, 'Anonymous driver');
      expect(response.identifiedDriverName, isNull);
      expect(response.scores['ease_of_use'], 5);
    });

    test('identified responses show a name only after explicit opt-in', () {
      final response = DriverAppFeedback.fromRow({
        'id': 'feedback-2',
        'toda_name': 'SJVTODA',
        'is_anonymous': false,
        'driver_display_name': 'Marco Dela Cruz',
        'answers': {
          'ease_of_use': 4,
          'booking_clarity': 4,
          'navigation_clarity': 3,
          'fare_fairness': 5,
          'reliability': 4,
          'safety_confidence': 5,
          'continued_use': 4,
        },
        'created_at': '2026-08-25T11:00:00Z',
      });

      expect(response.displayName, 'Marco Dela Cruz');
      expect(response.identifiedDriverName, 'Marco Dela Cruz');
    });

    test(
      'unique-driver participation stays distinct from repeat responses',
      () {
        const summary = TodaFeedbackSummary(
          toda: 'SJVTODA',
          responseCount: 4,
          uniqueDrivers: 2,
          target: 10,
        );

        expect(summary.progress, closeTo(.2, .0001));
        expect(summary.responseCount, 4);
        expect(summary.uniqueDrivers, 2);
      },
    );
  });

  test(
    'connected driver models preserve UUID identities and server statuses',
    () {
      final driver = Driver.fromRow({
        'id': 'ff54a443-a34d-4d9e-8558-3783a757077f',
        'verification_status': 'pending_review',
        'body_number': '024',
        'plate_number': 'ABC 1234',
        'updated_at': '2026-08-25T10:00:00Z',
        'profiles': {'display_name': 'Marco Dela Cruz', 'phone': '09170000000'},
        'toda_zones': {'name': 'SJVTODA'},
      });

      expect(driver.id, 'ff54a443-a34d-4d9e-8558-3783a757077f');
      expect(driver.name, 'Marco Dela Cruz');
      expect(driver.toda, 'SJVTODA');
      expect(driver.status, DriverStatus.review);
    },
  );

  test('driver approval requires four actually approved document records', () {
    final driver = Driver.fromRow({
      'driver_id': 'ff54a443-a34d-4d9e-8558-3783a757077f',
      'display_name': 'Marco Dela Cruz',
      'toda_name': 'SJVTODA',
      'verification_status': 'pending_review',
      'document_statuses': {
        'drivers_license': 'approved',
        'mtop_franchise': 'approved',
        'toda_membership': 'approved',
        'or_cr': 'pending',
      },
    });

    expect(driver.documents, 4);
    expect(driver.approvedDocuments, 3);
  });

  test(
    'live SOS reports preserve safe display identity, priority, and location',
    () {
      final report = SafetyReport.fromRow({
        'id': 'ab54a443-a34d-4d9e-8558-3783a757077f',
        'trip_id': 'trip-1',
        'reporter_role': 'commuter',
        'reporter_display_name': 'Ana Reyes',
        'driver_display_name': 'Marco Dela Cruz',
        'toda_name': 'SJVTODA',
        'reason': 'Emergency during the ride',
        'status': 'new',
        'priority': 'critical',
        'latitude': 14.27711,
        'longitude': 121.12555,
        'created_at': '2026-08-25T10:00:00Z',
      });

      expect(safetyReportLabel(report.id), 'SOS-AB54A443');
      expect(report.rider, 'Ana Reyes');
      expect(report.driver, 'Marco Dela Cruz');
      expect(report.priority, 'critical');
      expect(report.latitude, closeTo(14.27711, .00001));
    },
  );

  group('explicitly consented reported conversations', () {
    test(
      'snapshots resolve trip participants without querying private chats',
      () {
        final reported = ReportedTripChat.fromRow({
          'id': 'chat-report-1',
          'trip_id': 'trip-1',
          'reporter_id': 'commuter-1',
          'reason': 'Threatening language during pickup',
          'consented_at': '2026-08-25T10:07:00Z',
          'created_at': '2026-08-25T10:07:00Z',
          'messages': [
            {
              'id': 'message-1',
              'sender_id': 'commuter-1',
              'body': 'I am at the terminal entrance.',
              'created_at': '2026-08-25T10:01:00Z',
            },
            {
              'id': 'message-2',
              'sender_id': 'driver-1',
              'body': 'I can see you now.',
              'created_at': '2026-08-25T10:02:00Z',
            },
          ],
          'trips': {
            'rider_id': 'commuter-1',
            'driver_id': 'driver-1',
            'rider_display_name': 'Ana Reyes',
            'driver_display_name': 'Marco Dela Cruz',
            'toda_name': 'SJVTODA',
          },
        });

        expect(reported.reporterName, 'Ana Reyes');
        expect(reported.toda, 'SJVTODA');
        expect(reported.messages, hasLength(2));
        expect(reported.messages.first.senderRole, 'Commuter');
        expect(reported.messages.first.senderName, 'Ana Reyes');
        expect(reported.messages.last.senderRole, 'Driver');
        expect(reported.messages.last.senderName, 'Marco Dela Cruz');
      },
    );

    test('a snapshot without an explicit consent timestamp is rejected', () {
      expect(
        () => ReportedTripChat.fromRow({
          'id': 'chat-report-2',
          'trip_id': 'trip-2',
          'reporter_id': 'commuter-2',
          'reason': 'Missing explicit consent',
          'messages': const [],
        }),
        throwsFormatException,
      );
    });

    test(
      'a TODA session is rejected before any snapshot request is issued',
      () async {
        final repository = SupabaseAdminRepository(
          SupabaseClient('https://example.supabase.co', 'public-placeholder'),
        );
        const session = AdminSession(
          name: 'TODA coordinator',
          role: AdminRole.toda,
          toda: 'SJVTODA',
        );

        await expectLater(
          repository.loadReportedChats(session),
          throwsStateError,
        );
      },
    );
  });

  test('live dispatch statuses preserve server lifecycle names', () {
    expect(rideStatusLabel('searching_driver'), 'Searching');
    expect(rideStatusLabel('driver_assigned'), 'En route');
    expect(rideStatusLabel('driver_en_route'), 'En route');
    expect(rideStatusLabel('emergency_reported'), 'Emergency');
    expect(rideStatusLabel('cancelled_by_rider'), 'Cancelled by rider');
    expect(rideStatusLabel('cancelled_by_driver'), 'Cancelled by driver');
    expect(rideStatusLabel('no_driver_available'), 'No driver');
  });

  test(
    'cancelled, completed, and expired trips never appear on the live map',
    () {
      for (final active in const [
        'requested',
        'searching_driver',
        'driver_assigned',
        'accepted',
        'driver_en_route',
        'arrived',
        'in_progress',
        'emergency_reported',
      ]) {
        expect(isActiveTripStatus(active), isTrue);
      }
      for (final closed in const [
        'completed',
        'cancelled_by_rider',
        'cancelled_by_driver',
        'no_driver_available',
      ]) {
        expect(isActiveTripStatus(closed), isFalse);
      }
      expect(isActiveTripStatus(null), isFalse);
    },
  );

  test('PostGIS hexadecimal EWKB polygons decode only for map rendering', () {
    const polygon = [
      [121.120, 14.270],
      [121.130, 14.270],
      [121.130, 14.280],
      [121.120, 14.280],
      [121.120, 14.270],
    ];
    final data = ByteData(17 + polygon.length * 16)
      ..setUint8(0, 1)
      ..setUint32(1, 0x20000003, Endian.little)
      ..setUint32(5, 4326, Endian.little)
      ..setUint32(9, 1, Endian.little)
      ..setUint32(13, polygon.length, Endian.little);
    for (var index = 0; index < polygon.length; index++) {
      data.setFloat64(17 + index * 16, polygon[index][0], Endian.little);
      data.setFloat64(25 + index * 16, polygon[index][1], Endian.little);
    }
    final hex = data.buffer
        .asUint8List()
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();

    final decoded = polygonBoundaryCoordinates(hex);

    expect(decoded, hasLength(5));
    expect(decoded.first[0], closeTo(121.120, .000001));
    expect(decoded.first[1], closeTo(14.270, .000001));
    expect(polygonBoundaryCoordinates('not-valid-wkb'), isEmpty);
  });
}
