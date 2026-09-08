import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class AdminSnapshot {
  const AdminSnapshot({
    required this.drivers,
    required this.reports,
    required this.complaints,
    required this.ratings,
    required this.fareClassClaims,
    required this.reportedChats,
    required this.rides,
    required this.boundaries,
    required this.feedbackSummaries,
    required this.feedbackResponses,
    required this.feedbackInterval,
    required this.respondentTarget,
    required this.repeatFeedback,
  });

  final List<Driver> drivers;
  final List<SafetyReport> reports;
  final List<Complaint> complaints;
  final List<TripRating> ratings;
  final List<FareClassClaim> fareClassClaims;
  final List<ReportedTripChat> reportedChats;
  final List<Ride> rides;
  final List<Boundary> boundaries;
  final List<TodaFeedbackSummary> feedbackSummaries;
  final List<DriverAppFeedback> feedbackResponses;
  final int feedbackInterval;
  final int respondentTarget;
  final bool repeatFeedback;
}

class SupabaseAdminRepository {
  SupabaseAdminRepository(this.client);

  final SupabaseClient client;
  RealtimeChannel? _channel;
  Timer? _refreshDebounce;

  bool get hasSession => client.auth.currentSession != null;

  Future<AdminSession> signIn({
    required String email,
    required String password,
  }) async {
    final result = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = result.user;
    if (user == null) {
      throw StateError('Sign-in did not return an administrator account.');
    }
    try {
      return await _resolveSession(user);
    } catch (_) {
      await client.auth.signOut();
      rethrow;
    }
  }

  Future<AdminSession> restoreSession() async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('No administrator session exists.');
    return _resolveSession(user);
  }

  Future<AdminSession> _resolveSession(User user) async {
    final profile = await client
        .from('profiles')
        .select('id, role, display_name, status')
        .eq('id', user.id)
        .single();
    final result = await client.rpc('get_admin_scope');
    if (result is! Map) {
      throw StateError('Administrator scope could not be verified.');
    }
    final scope = Map<String, dynamic>.from(result);
    final adminRole = scope['admin_role']?.toString();
    if (adminRole != 'lgu' && adminRole != 'toda') {
      throw StateError('Administrator scope is not recognized.');
    }

    String? todaZoneId;
    String? toda;
    if (adminRole == 'toda') {
      todaZoneId = scope['toda_zone_id']?.toString();
      if (todaZoneId == null || todaZoneId.isEmpty) {
        throw StateError('No TODA jurisdiction is assigned to this account.');
      }
      final zone = await client
          .from('toda_zones')
          .select('name')
          .eq('id', todaZoneId)
          .single();
      toda = zone['name']?.toString();
    }

    return AdminSession.fromProfile(
      profile,
      email: user.email,
      adminRole: adminRole,
      todaZoneId: todaZoneId,
      toda: toda,
    );
  }

  Future<void> updateOwnPassword({
    required String expectedUserId,
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    final result = await client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    if (result.user?.id != expectedUserId) {
      await client.auth.signOut();
      throw StateError('Administrator identity changed during confirmation.');
    }
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<AdminSnapshot> load(AdminSession session) async {
    final results = await Future.wait<dynamic>([
      client.rpc('admin_list_drivers'),
      client
          .from('trips')
          .select(
            'id, driver_id, toda_zone_id, status, requested_at, '
            'pickup_lat, pickup_lng, destination_lat, destination_lng, '
            'pickup_label, destination_label, rider_display_name, '
            'driver_display_name, toda_name',
          )
          .order('requested_at', ascending: false)
          .limit(100),
      client
          .from('driver_availability')
          .select(
            'driver_id, toda_zone_id, is_online, latitude, longitude, updated_at',
          ),
      client
          .from('sos_reports')
          .select(
            'id, trip_id, toda_zone_id, reporter_role, reason, status, priority, '
            'latitude, longitude, reporter_display_name, driver_display_name, '
            'toda_name, created_at, updated_at, admin_note',
          )
          .order('created_at', ascending: false)
          .limit(100),
      client
          .from('driver_app_feedback')
          .select(
            'id, toda_zone_id, answers, comment, is_anonymous, '
            'driver_display_name, submitted_at',
          )
          .order('submitted_at', ascending: false)
          .limit(100),
      session.todaZoneId == null
          ? client.rpc('get_feedback_summary')
          : client.rpc(
              'get_feedback_summary',
              params: {'p_toda_zone_id': session.todaZoneId},
            ),
      client.rpc('get_feedback_settings'),
      client.from('toda_zones').select('id, name, boundary'),
      client
          .from('driver_documents')
          .select('id, driver_id, document_type, status, storage_path'),
      client
          .from('complaints')
          .select(
            'id, trip_id, toda_zone_id, complainant_role, '
            'complainant_display_name, respondent_display_name, toda_name, '
            'category, description, status, admin_note, created_at, updated_at',
          )
          .order('created_at', ascending: false)
          .limit(100),
      client
          .from('trip_ratings')
          .select(
            'id, trip_id, toda_zone_id, toda_name, rater_role, '
            'rater_display_name, ratee_display_name, stars, comment, created_at',
          )
          .order('created_at', ascending: false)
          .limit(100),
      if (session.role == AdminRole.lgu) loadReportedChats(session),
      // Always last in this list: RLS on fare_class_claims (is_admin() only,
      // no TODA scoping -- commuters have no TODA affiliation to scope by)
      // already returns zero rows for a TODA-scoped admin, so no client-side
      // role branch is needed here the way reportedChats needs one above.
      client
          .from('fare_class_claims')
          .select(
            'id, claimant_display_name, requested_class, id_photo_path, '
            'status, rejection_reason, created_at',
          )
          .order('created_at', ascending: false)
          .limit(100),
    ]);

    final driverRows = _rows(results[0]);
    final tripRows = _rows(results[1]);
    final availabilityRows = _rows(results[2]);
    final reportRows = _rows(results[3]);
    final feedbackRows = _rows(results[4]);
    final summaryRows = _rows(results[5]);
    final settings = _row(results[6]);
    final zoneRows = _rows(results[7]);
    final documentRows = _rows(results[8]);
    final complaintRows = _rows(results[9]);
    final ratingRows = _rows(results[10]);
    final reportedChats = session.role == AdminRole.lgu
        ? results[11] as List<ReportedTripChat>
        : const <ReportedTripChat>[];
    // Always the last element (see the comment where it is queried above),
    // regardless of whether the conditional reportedChats entry shifted it.
    final fareClassClaimRows = _rows(results.last);
    final zones = {
      for (final zone in zoneRows)
        zone['id'].toString(): zone['name'].toString(),
    };
    final locations = {
      for (final row in availabilityRows) row['driver_id'].toString(): row,
    };
    final documentStatuses = <String, Map<String, String>>{};
    final documentIds = <String, Map<String, String>>{};
    final documentPaths = <String, Map<String, String>>{};
    for (final row in documentRows) {
      final driverId = row['driver_id']?.toString();
      final type = row['document_type']?.toString();
      if (driverId == null || type == null) continue;
      (documentStatuses[driverId] ??= {})[type] =
          row['status']?.toString() ?? 'pending';
      final documentId = row['id']?.toString();
      if (documentId != null) (documentIds[driverId] ??= {})[type] = documentId;
      final path = row['storage_path']?.toString();
      if (path != null) (documentPaths[driverId] ??= {})[type] = path;
    }

    final rides = <Ride>[];
    for (final row in tripRows) {
      if (!isActiveTripStatus(row['status']?.toString())) {
        continue;
      }
      try {
        rides.add(
          Ride.fromRow(
            row,
            availability: locations[row['driver_id']?.toString()],
          ),
        );
      } on FormatException {
        // An active trip without coordinates cannot be represented on the map.
      }
    }

    return AdminSnapshot(
      drivers: [
        for (final row in driverRows)
          Driver.fromRow({
            ...row,
            'document_statuses':
                documentStatuses[row['driver_id']?.toString()] ??
                const <String, String>{},
            'document_ids':
                documentIds[row['driver_id']?.toString()] ??
                const <String, String>{},
            'document_paths':
                documentPaths[row['driver_id']?.toString()] ??
                const <String, String>{},
          }),
      ],
      reports: [for (final row in reportRows) SafetyReport.fromRow(row)],
      complaints: [for (final row in complaintRows) Complaint.fromRow(row)],
      ratings: [for (final row in ratingRows) TripRating.fromRow(row)],
      fareClassClaims: [
        for (final row in fareClassClaimRows) FareClassClaim.fromRow(row),
      ],
      reportedChats: reportedChats,
      rides: rides,
      boundaries: _boundaries(zoneRows),
      feedbackSummaries: [
        for (final row in summaryRows) TodaFeedbackSummary.fromRow(row),
      ],
      feedbackResponses: [
        for (final row in feedbackRows)
          DriverAppFeedback.fromRow(
            row,
            todaName: zones[row['toda_zone_id']?.toString()],
          ),
      ],
      feedbackInterval: (settings['feedback_interval'] as num?)?.toInt() ?? 1,
      respondentTarget: (settings['respondent_target'] as num?)?.toInt() ?? 10,
      repeatFeedback: settings['repeat_feedback'] as bool? ?? true,
    );
  }

  Future<List<ReportedTripChat>> loadReportedChats(AdminSession session) async {
    if (session.role != AdminRole.lgu) {
      throw StateError(
        'Reported conversations can only be reviewed by an LGU administrator.',
      );
    }
    final rows = await client
        .from('reported_trip_chats')
        .select(
          'id, trip_id, reporter_id, reason, messages, consented_at, created_at, '
          'trips(rider_id, driver_id, rider_display_name, driver_display_name, toda_name)',
        )
        .order('created_at', ascending: false)
        .limit(50);
    final reports = <ReportedTripChat>[];
    for (final row in rows) {
      try {
        reports.add(ReportedTripChat.fromRow(row));
      } on FormatException {
        // Refuse to render malformed or non-consented conversation snapshots.
      }
    }
    return reports;
  }

  void subscribe({
    required AdminSession session,
    required VoidCallback onDataChanged,
    required VoidCallback onSafetyInserted,
  }) {
    _removeChannel();
    final channel = client.channel('admin-console:${session.userId}');
    for (final table in const [
      'trips',
      'driver_availability',
      'driver_profiles',
      'driver_documents',
      'sos_reports',
      'complaints',
      'trip_ratings',
      'driver_app_feedback',
      'app_evaluation_settings',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (payload) {
          if (table == 'sos_reports' &&
              payload.eventType == PostgresChangeEvent.insert) {
            onSafetyInserted();
          }
          _refreshDebounce?.cancel();
          _refreshDebounce = Timer(
            const Duration(milliseconds: 180),
            onDataChanged,
          );
        },
      );
    }
    _channel = channel.subscribe();
  }

  Future<void> updateDriver({
    required Driver driver,
    required DriverStatus status,
    required String reason,
    required AdminSession session,
  }) async {
    if (status == DriverStatus.suspended) {
      if (session.role != AdminRole.lgu) {
        throw StateError('Only an LGU administrator can suspend a driver.');
      }
      await client.rpc(
        'admin_set_profile_status',
        params: {
          'p_profile_id': driver.id,
          'p_status': 'suspended',
          'p_reason': reason.trim(),
        },
      );
      return;
    }
    if (status == DriverStatus.rejected && session.role != AdminRole.lgu) {
      throw StateError(
        'TODA administrators may approve, but cannot reject, drivers.',
      );
    }
    if (driver.status == DriverStatus.suspended &&
        status == DriverStatus.approved) {
      if (session.role != AdminRole.lgu) {
        throw StateError('Only an LGU administrator can reinstate a driver.');
      }
      await client.rpc(
        'admin_set_profile_status',
        params: {
          'p_profile_id': driver.id,
          'p_status': 'active',
          'p_reason': reason.trim(),
        },
      );
      return;
    }

    final decision = switch (status) {
      DriverStatus.approved => 'approve',
      DriverStatus.rejected => 'reject',
      _ => throw StateError('This driver transition is not available.'),
    };
    await client.rpc(
      'admin_review_scoped_driver',
      params: {
        'p_driver_id': driver.id,
        'p_decision': decision,
        'p_reason': reason.trim(),
      },
    );
  }

  Future<void> updateSafetyReport({
    required String reportId,
    required ReportStatus status,
    required String note,
    required AdminSession session,
  }) async {
    if (session.role != AdminRole.lgu) {
      throw StateError('TODA administrators have read-only safety access.');
    }
    await client.rpc(
      'update_sos_status',
      params: {
        'p_report_id': reportId,
        'p_status': reportStatusToServer(status),
        'p_note': note.trim(),
      },
    );
  }

  // Unlike updateSafetyReport(), both LGU and TODA-scoped admins may act --
  // "driver was late" is exactly the kind of thing a TODA officer should
  // resolve locally, not escalate. update_complaint_status() (server-side)
  // already enforces is_admin() regardless of scope.
  Future<void> updateComplaint({
    required String complaintId,
    required ReportStatus status,
    required String note,
  }) async {
    await client.rpc(
      'update_complaint_status',
      params: {
        'p_complaint_id': complaintId,
        'p_status': reportStatusToServer(status),
        'p_note': note.trim(),
      },
    );
  }

  Future<void> reviewFareClassClaim({
    required String claimId,
    required bool approve,
    String? rejectionReason,
  }) async {
    await client.rpc(
      'review_fare_class_claim',
      params: {
        'p_claim_id': claimId,
        'p_approve': approve,
        'p_rejection_reason': rejectionReason?.trim(),
      },
    );
  }

  /// A short-lived signed URL for a submitted ID photo. Never a public read
  /// grant -- `discount_id_select_own_or_admin`'s RLS policy on
  /// `storage.objects` is what actually decides an admin may read this
  /// specific path, exactly the same gate the commuter's own client-side read
  /// of their own photo goes through. See .pipeline/specs.md Spec 14.
  Future<String> fareClassClaimPhotoUrl(String path) async {
    final signed = await client.storage
        .from('discount-eligibility-ids')
        .createSignedUrl(path, 300);
    return signed;
  }

  /// A short-lived signed URL for a driver's uploaded document -- same
  /// shape as fareClassClaimPhotoUrl, gated by
  /// driver_documents_photos_select_own_or_admin instead. See
  /// .pipeline/specs.md Spec 18.
  Future<String> driverDocumentPhotoUrl(String path) async {
    final signed = await client.storage
        .from('driver-documents')
        .createSignedUrl(path, 300);
    return signed;
  }

  /// Uploads (or replaces) a driver's document on their behalf: the file
  /// goes to Storage first, then admin_upsert_driver_document() records
  /// the path -- that RPC is what actually resets status to pending and
  /// writes the audit row, not this method. Path convention matches
  /// profile-photos: {driver_id}/{document_type}-{timestamp}.{ext}.
  Future<void> uploadDriverDocument({
    required String driverId,
    required String documentType,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final path =
        '$driverId/$documentType-${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    await client.storage
        .from('driver-documents')
        .uploadBinary(path, bytes);
    await client.rpc(
      'admin_upsert_driver_document',
      params: {
        'p_driver_id': driverId,
        'p_document_type': documentType,
        'p_storage_path': path,
      },
    );
  }

  Future<void> reviewDriverDocument({
    required String documentId,
    required bool approve,
    String? rejectionReason,
  }) async {
    await client.rpc(
      'admin_review_driver_document',
      params: {
        'p_document_id': documentId,
        'p_approve': approve,
        'p_rejection_reason': rejectionReason?.trim(),
      },
    );
  }

  Future<void> updateFeedbackSettings({
    required int feedbackInterval,
    required int respondentTarget,
    required bool repeatFeedback,
  }) async {
    await client.rpc(
      'update_feedback_settings',
      params: {
        'p_feedback_interval': feedbackInterval,
        'p_respondent_target': respondentTarget,
        'p_repeat_feedback': repeatFeedback,
      },
    );
  }

  Future<void> signOut() async {
    _removeChannel();
    await client.auth.signOut();
  }

  void dispose() {
    _refreshDebounce?.cancel();
    _removeChannel();
  }

  void _removeChannel() {
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(client.removeChannel(channel));
  }

  static List<Map<String, dynamic>> _rows(dynamic result) {
    if (result is! List) return const [];
    return [for (final row in result) Map<String, dynamic>.from(row as Map)];
  }

  static Map<String, dynamic> _row(dynamic result) {
    if (result is List && result.isNotEmpty) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    if (result is Map) return Map<String, dynamic>.from(result);
    return const {};
  }

  static List<Boundary> _boundaries(List<Map<String, dynamic>> zones) {
    const colors = [0xFF1262D0, 0xFF2A79B8, 0xFF008578, 0xFF8555A4];
    final results = <Boundary>[];
    for (final zone in zones) {
      final coordinates = polygonBoundaryCoordinates(zone['boundary']);
      if (coordinates.length >= 4) {
        results.add(
          Boundary(
            zone['name'].toString(),
            colors[results.length % colors.length],
            coordinates,
          ),
        );
      }
    }
    return results;
  }
}

/// Decodes PostGIS polygons for display only; dispatch remains server-trusted.
List<List<double>> polygonBoundaryCoordinates(dynamic geometry) {
  if (geometry is Map && geometry['coordinates'] is List) {
    final rings = geometry['coordinates'] as List;
    if (rings.isEmpty || rings.first is! List) return const [];
    return [
      for (final point in rings.first as List)
        if (point is List &&
            point.length >= 2 &&
            point[0] is num &&
            point[1] is num)
          [(point[0] as num).toDouble(), (point[1] as num).toDouble()],
    ];
  }
  if (geometry is! String) return const [];
  final hex = geometry.startsWith(r'\x') ? geometry.substring(2) : geometry;
  if (hex.length < 26 ||
      hex.length > 1000000 ||
      hex.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    return const [];
  }

  try {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = int.parse(
        hex.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    final data = ByteData.sublistView(bytes);
    final endian = switch (data.getUint8(0)) {
      0 => Endian.big,
      1 => Endian.little,
      _ => throw const FormatException('Invalid WKB byte order.'),
    };
    final type = data.getUint32(1, endian);
    if ((type & 0xFF) != 3) return const [];

    var offset = 5;
    if ((type & 0x20000000) != 0) offset += 4;
    final rings = data.getUint32(offset, endian);
    offset += 4;
    if (rings == 0) return const [];
    final points = data.getUint32(offset, endian);
    offset += 4;
    if (points < 4 || points > 50000) return const [];
    final dimensions =
        2 +
        ((type & 0x80000000) != 0 ? 1 : 0) +
        ((type & 0x40000000) != 0 ? 1 : 0);
    final coordinates = <List<double>>[];
    for (var point = 0; point < points; point++) {
      final longitude = data.getFloat64(offset, endian);
      final latitude = data.getFloat64(offset + 8, endian);
      if (!longitude.isFinite || !latitude.isFinite) return const [];
      coordinates.add([longitude, latitude]);
      offset += dimensions * 8;
    }
    return coordinates;
  } on RangeError {
    return const [];
  } on FormatException {
    return const [];
  }
}
