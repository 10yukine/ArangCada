enum AdminRole { lgu, toda }

enum DriverStatus {
  enrolled,
  submitted,
  review,
  approved,
  rejected,
  suspended,
  expired,
}

enum ReportStatus {
  newReport,
  acknowledged,
  investigating,
  resolved,
  escalated,
  dismissed,
}

class AdminSession {
  const AdminSession({
    required this.name,
    required this.role,
    this.email,
    this.toda,
    this.todaZoneId,
    this.userId,
    this.connected = false,
    this.avatarUrl,
  });

  factory AdminSession.fromProfile(
    Map<String, dynamic> profile, {
    String? todaZoneId,
    String? toda,
    String? adminRole,
    String? email,
    String? avatarUrl,
  }) {
    if (profile['role'] != 'admin' || profile['status'] != 'active') {
      throw StateError('An active administrator profile is required.');
    }
    final scoped = adminRole == 'toda' || todaZoneId != null;
    if (scoped && (todaZoneId == null || toda == null)) {
      throw StateError('A TODA administrator requires an assigned TODA.');
    }
    return AdminSession(
      name: (profile['display_name'] as String?) ?? 'Administrator',
      email: email,
      role: scoped ? AdminRole.toda : AdminRole.lgu,
      toda: scoped ? toda : null,
      todaZoneId: scoped ? todaZoneId : null,
      userId: profile['id']?.toString(),
      connected: true,
      avatarUrl: avatarUrl,
    );
  }

  final String name;
  final String? email;
  final AdminRole role;
  final String? toda;
  final String? todaZoneId;
  final String? userId;
  final bool connected;
  // Short-lived signed URL into the shared profile-photos bucket (same
  // bucket/RLS the mobile app's own profile photo, already
  // established -- profiles.avatar_path and its Storage policies are
  // role-agnostic, so an admin account needed no new migration here).
  // Re-minted on every sign-in/session-restore/photo change, never cached
  // longer than that.
  final String? avatarUrl;

  String get scope =>
      role == AdminRole.lgu ? 'LGU · All TODAs' : 'TODA · $toda';

  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final value = words.take(2).map((word) => word[0]).join().toUpperCase();
    return value.isEmpty ? 'A' : value;
  }

  String get roleLabel =>
      role == AdminRole.lgu ? 'LGU administrator' : 'TODA administrator';

  String get deskLabel =>
      role == AdminRole.lgu ? 'LGU transport desk' : '${toda ?? 'TODA'} desk';
}

class Driver {
  const Driver({
    required this.id,
    required this.name,
    required this.toda,
    required this.phone,
    required this.plate,
    required this.status,
    required this.documents,
    required this.enrollmentCode,
    required this.updated,
    this.online = false,
    this.latitude,
    this.longitude,
    this.todaZoneId,
    this.bodyNumber,
    this.licenseExpiresOn,
    this.documentStatuses = const {},
    this.documentIds = const {},
    this.documentPaths = const {},
    this.firstName,
    this.lastName,
  });

  factory Driver.fromRow(Map<String, dynamic> row) {
    final profile = row['profiles'] is Map
        ? Map<String, dynamic>.from(row['profiles'] as Map)
        : const <String, dynamic>{};
    final zone = row['toda_zones'] is Map
        ? Map<String, dynamic>.from(row['toda_zones'] as Map)
        : const <String, dynamic>{};
    final accountStatus =
        row['account_status'] as String? ?? profile['status'] as String?;
    final verification = row['verification_status'] as String?;
    final status = accountStatus == 'suspended'
        ? DriverStatus.suspended
        : switch (verification) {
            'approved' => DriverStatus.approved,
            'rejected' => DriverStatus.rejected,
            'pending_review' => DriverStatus.review,
            'submitted' => DriverStatus.submitted,
            _ => DriverStatus.enrolled,
          };
    final id = (row['driver_id'] ?? row['id'])?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('Driver row does not include an identity.');
    }
    final body = row['body_number'] as String?;
    final documentStatuses = row['document_statuses'] is Map
        ? <String, String>{
            for (final entry in Map<String, dynamic>.from(
              row['document_statuses'] as Map,
            ).entries)
              entry.key: entry.value.toString(),
          }
        : const <String, String>{};
    final documentIds = row['document_ids'] is Map
        ? <String, String>{
            for (final entry in Map<String, dynamic>.from(
              row['document_ids'] as Map,
            ).entries)
              entry.key: entry.value.toString(),
          }
        : const <String, String>{};
    final documentPaths = row['document_paths'] is Map
        ? <String, String>{
            for (final entry in Map<String, dynamic>.from(
              row['document_paths'] as Map,
            ).entries)
              entry.key: entry.value.toString(),
          }
        : const <String, String>{};
    return Driver(
      id: id,
      name:
          row['display_name'] as String? ??
          profile['display_name'] as String? ??
          'Unnamed driver',
      firstName:
          row['first_name'] as String? ?? profile['first_name'] as String?,
      lastName: row['last_name'] as String? ?? profile['last_name'] as String?,
      toda:
          row['toda_name'] as String? ??
          zone['name'] as String? ??
          'Unassigned TODA',
      phone:
          row['phone'] as String? ??
          profile['phone'] as String? ??
          'Not shared',
      plate: row['plate_number'] as String? ?? 'Not recorded',
      bodyNumber: body,
      licenseExpiresOn: DateTime.tryParse(
        row['license_expires_on']?.toString() ?? '',
      ),
      status: status,
      documents: (row['documents'] as num?)?.toInt() ?? documentStatuses.length,
      enrollmentCode: body == null
          ? id.substring(0, id.length < 8 ? id.length : 8)
          : 'Body $body',
      updated:
          DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      online: row['is_online'] as bool? ?? false,
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      todaZoneId: row['toda_zone_id']?.toString(),
      documentStatuses: documentStatuses,
      documentIds: documentIds,
      documentPaths: documentPaths,
    );
  }

  final String id;
  final String name;
  final String? firstName;
  final String? lastName;
  final String toda;
  final String phone;
  final String plate;
  final DriverStatus status;
  final int documents;
  final String enrollmentCode;
  final DateTime updated;
  final bool online;
  final double? latitude;
  final double? longitude;
  final String? todaZoneId;
  final String? bodyNumber;
  final DateTime? licenseExpiresOn;
  final Map<String, String> documentStatuses;
  final Map<String, String> documentIds;
  final Map<String, String> documentPaths;

  String get effectiveFirstName {
    if (firstName != null && firstName!.trim().isNotEmpty) {
      return firstName!.trim();
    }
    final trimmed = name.trim();
    final idx = trimmed.indexOf(' ');
    return idx == -1 ? trimmed : trimmed.substring(0, idx);
  }

  String get effectiveLastName {
    if (lastName != null && lastName!.trim().isNotEmpty) {
      return lastName!.trim();
    }
    final trimmed = name.trim();
    final idx = trimmed.indexOf(' ');
    return idx == -1 ? '' : trimmed.substring(idx + 1).trim();
  }

  int get approvedDocuments => documentStatuses.isEmpty
      ? documents
      : documentStatuses.values.where((status) => status == 'approved').length;

  Driver copyWith({
    DriverStatus? status,
    DateTime? updated,
    String? name,
    String? firstName,
    String? lastName,
    String? toda,
    String? plate,
    String? bodyNumber,
    bool clearBodyNumber = false,
    String? todaZoneId,
    DateTime? licenseExpiresOn,
    bool clearLicenseExpiry = false,
  }) => Driver(
    id: id,
    name:
        name ??
        (firstName != null || lastName != null
            ? '${firstName ?? effectiveFirstName} ${lastName ?? effectiveLastName}'
                  .trim()
            : this.name),
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    toda: toda ?? this.toda,
    phone: phone,
    plate: plate ?? this.plate,
    status: status ?? this.status,
    documents: documents,
    enrollmentCode: enrollmentCode,
    updated: updated ?? this.updated,
    online: online,
    latitude: latitude,
    longitude: longitude,
    todaZoneId: todaZoneId ?? this.todaZoneId,
    bodyNumber: clearBodyNumber ? null : bodyNumber ?? this.bodyNumber,
    licenseExpiresOn: clearLicenseExpiry
        ? null
        : licenseExpiresOn ?? this.licenseExpiresOn,
    documentStatuses: documentStatuses,
    documentIds: documentIds,
    documentPaths: documentPaths,
  );
}

class Complaint {
  const Complaint({
    required this.id,
    required this.tripId,
    required this.complainantName,
    required this.complainantRole,
    required this.respondentName,
    required this.toda,
    required this.category,
    required this.description,
    required this.status,
    required this.created,
    required this.notes,
  });

  factory Complaint.fromRow(Map<String, dynamic> row) => Complaint(
    id: row['id'].toString(),
    tripId: row['trip_id']?.toString() ?? '',
    complainantName: row['complainant_display_name']?.toString() ?? 'Unknown',
    complainantRole: row['complainant_role']?.toString() ?? 'commuter',
    respondentName: row['respondent_display_name']?.toString() ?? 'Unknown',
    toda: row['toda_name']?.toString() ?? 'Assigned TODA',
    category: row['category']?.toString() ?? 'other',
    description: row['description']?.toString() ?? '',
    status: reportStatusFromServer(row['status']?.toString()),
    created:
        DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    notes: [
      if ((row['admin_note'] as String?)?.trim().isNotEmpty ?? false)
        (row['admin_note'] as String).trim(),
    ],
  );

  final String id;
  final String tripId;
  final String complainantName;
  final String complainantRole;
  final String respondentName;
  final String toda;
  final String category;
  final String description;
  final ReportStatus status;
  final DateTime created;
  final List<String> notes;

  Complaint copyWith({ReportStatus? status, List<String>? notes}) => Complaint(
    id: id,
    tripId: tripId,
    complainantName: complainantName,
    complainantRole: complainantRole,
    respondentName: respondentName,
    toda: toda,
    category: category,
    description: description,
    status: status ?? this.status,
    created: created,
    notes: notes ?? this.notes,
  );
}

String complaintCategoryLabel(String value) => switch (value) {
  'driver_late' => 'Driver was late',
  'unsafe_driving_non_emergency' => 'Unsafe driving',
  'rude_unprofessional' => 'Rude or unprofessional',
  'wrong_route' => 'Wrong route taken',
  'vehicle_condition' => 'Vehicle condition',
  'overcharged' => 'Overcharged',
  'passenger_late' => 'Passenger was late',
  'damaged_vehicle_non_emergency' => 'Damaged vehicle',
  'disputed_fare' => 'Disputed fare',
  _ => 'Other',
};

class TripRating {
  const TripRating({
    required this.id,
    required this.tripId,
    required this.raterName,
    required this.raterRole,
    required this.rateeName,
    required this.toda,
    required this.stars,
    required this.comment,
    required this.created,
  });

  factory TripRating.fromRow(Map<String, dynamic> row) => TripRating(
    id: row['id'].toString(),
    tripId: row['trip_id']?.toString() ?? '',
    raterName: row['rater_display_name']?.toString() ?? 'Unknown',
    raterRole: row['rater_role']?.toString() ?? 'commuter',
    rateeName: row['ratee_display_name']?.toString() ?? 'Unknown',
    toda: row['toda_name']?.toString() ?? 'Assigned TODA',
    stars: (row['stars'] as num?)?.toInt() ?? 0,
    comment: (row['comment'] as String?)?.trim().isEmpty ?? true
        ? null
        : (row['comment'] as String).trim(),
    created:
        DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );

  final String id;
  final String tripId;
  final String raterName;
  final String raterRole;
  final String rateeName;
  final String toda;
  final int stars;
  final String? comment;
  final DateTime created;
}

/// A Student/Senior Citizen/PWD discount claim, reviewed only by an LGU-wide
/// administrator -- commuters are not TODA-scoped (dispatch is city-wide;
/// only a trip's pickup records a TODA), so there is no per-TODA breakdown
/// for a claim to belong to.
class FareClassClaim {
  const FareClassClaim({
    required this.id,
    required this.claimantName,
    required this.requestedClass,
    required this.idPhotoPath,
    required this.status,
    required this.created,
    this.rejectionReason,
  });

  factory FareClassClaim.fromRow(Map<String, dynamic> row) => FareClassClaim(
    id: row['id'].toString(),
    claimantName: row['claimant_display_name']?.toString() ?? 'Unknown',
    requestedClass: row['requested_class']?.toString() ?? 'student',
    idPhotoPath: row['id_photo_path']?.toString() ?? '',
    status: row['status']?.toString() ?? 'pending_review',
    created:
        DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    rejectionReason:
        (row['rejection_reason'] as String?)?.trim().isEmpty ?? true
        ? null
        : (row['rejection_reason'] as String).trim(),
  );

  final String id;
  final String claimantName;
  final String requestedClass;
  final String idPhotoPath;
  final String status;
  final DateTime created;
  final String? rejectionReason;

  FareClassClaim copyWith({String? status, String? rejectionReason}) =>
      FareClassClaim(
        id: id,
        claimantName: claimantName,
        requestedClass: requestedClass,
        idPhotoPath: idPhotoPath,
        status: status ?? this.status,
        created: created,
        rejectionReason: rejectionReason ?? this.rejectionReason,
      );
}

String fareClassRequestedClassLabel(String value) => switch (value) {
  'student' => 'Student',
  'senior_citizen' => 'Senior Citizen',
  'pwd' => 'PWD',
  _ => 'Unknown',
};

class SafetyReport {
  const SafetyReport({
    required this.id,
    required this.rider,
    required this.driver,
    required this.toda,
    required this.summary,
    required this.status,
    required this.created,
    required this.notes,
    this.tripId,
    this.reporterRole,
    this.priority = 'normal',
    this.latitude,
    this.longitude,
  });

  factory SafetyReport.fromRow(Map<String, dynamic> row) {
    final role = row['reporter_role']?.toString();
    final reporter = row['reporter_display_name']?.toString();
    final driverName = row['driver_display_name']?.toString();
    return SafetyReport(
      id: row['id'].toString(),
      rider: role == 'commuter' ? reporter ?? 'Commuter' : 'Assigned commuter',
      driver:
          driverName ??
          (role == 'driver' ? reporter : null) ??
          'Assigned driver',
      toda: row['toda_name']?.toString() ?? 'Assigned TODA',
      summary: row['reason']?.toString() ?? 'Safety report',
      status: reportStatusFromServer(row['status']?.toString()),
      created:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      notes: [
        if ((row['admin_note'] as String?)?.trim().isNotEmpty ?? false)
          (row['admin_note'] as String).trim(),
      ],
      tripId: row['trip_id']?.toString(),
      reporterRole: role,
      priority: row['priority']?.toString() ?? 'normal',
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String rider;
  final String driver;
  final String toda;
  final String summary;
  final ReportStatus status;
  final DateTime created;
  final List<String> notes;
  final String? tripId;
  final String? reporterRole;
  final String priority;
  final double? latitude;
  final double? longitude;

  SafetyReport copyWith({ReportStatus? status, List<String>? notes}) =>
      SafetyReport(
        id: id,
        rider: rider,
        driver: driver,
        toda: toda,
        summary: summary,
        status: status ?? this.status,
        created: created,
        notes: notes ?? this.notes,
        tripId: tripId,
        reporterRole: reporterRole,
        priority: priority,
        latitude: latitude,
        longitude: longitude,
      );
}

class ReportedTripChat {
  const ReportedTripChat({
    required this.id,
    required this.tripId,
    required this.reporterId,
    required this.reporterName,
    required this.toda,
    required this.reason,
    required this.consentedAt,
    required this.createdAt,
    required this.messages,
  });

  factory ReportedTripChat.fromRow(Map<String, dynamic> row) {
    final consentedAt = DateTime.tryParse(
      row['consented_at']?.toString() ?? '',
    );
    if (consentedAt == null) {
      throw const FormatException(
        'Reported conversation does not include explicit sharing consent.',
      );
    }
    final entries = row['messages'];
    if (entries is! List) {
      throw const FormatException('Reported conversation is not a snapshot.');
    }
    final trip = row['trips'] is Map
        ? Map<String, dynamic>.from(row['trips'] as Map)
        : const <String, dynamic>{};
    final riderId = trip['rider_id']?.toString();
    final driverId = trip['driver_id']?.toString();
    final riderName = trip['rider_display_name']?.toString() ?? 'Commuter';
    final driverName = trip['driver_display_name']?.toString() ?? 'Driver';
    final reporterId = row['reporter_id']?.toString() ?? '';

    return ReportedTripChat(
      id: row['id']?.toString() ?? '',
      tripId: row['trip_id']?.toString() ?? '',
      reporterId: reporterId,
      reporterName: reporterId == riderId
          ? riderName
          : reporterId == driverId
          ? driverName
          : 'Trip participant',
      toda: trip['toda_name']?.toString() ?? 'Assigned TODA',
      reason: row['reason']?.toString() ?? 'Reported conversation',
      consentedAt: consentedAt.toLocal(),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
          consentedAt.toLocal(),
      messages: [
        for (final item in entries)
          if (item is Map)
            ReportedChatMessage.fromRow(
              Map<String, dynamic>.from(item),
              riderId: riderId,
              riderName: riderName,
              driverId: driverId,
              driverName: driverName,
            ),
      ],
    );
  }

  final String id;
  final String tripId;
  final String reporterId;
  final String reporterName;
  final String toda;
  final String reason;
  final DateTime consentedAt;
  final DateTime createdAt;
  final List<ReportedChatMessage> messages;
}

class ReportedChatMessage {
  const ReportedChatMessage({
    required this.senderRole,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  factory ReportedChatMessage.fromRow(
    Map<String, dynamic> row, {
    required String? riderId,
    required String riderName,
    required String? driverId,
    required String driverName,
  }) {
    final senderId = row['sender_id']?.toString();
    final commuter = senderId != null && senderId == riderId;
    final driver = senderId != null && senderId == driverId;
    return ReportedChatMessage(
      senderRole: commuter
          ? 'Commuter'
          : driver
          ? 'Driver'
          : 'Trip participant',
      senderName: commuter
          ? riderName
          : driver
          ? driverName
          : 'Trip participant',
      body: row['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(
        row['created_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  final String senderRole;
  final String senderName;
  final String body;
  final DateTime? createdAt;
}

/// A driver cancelling after accepting a ride. The owner's rule: a driver
/// who does not want a ride declines it; cancelling after accepting is
/// reported to administrators and may be penalised. Surfaced on the
/// dashboard's Needs attention list.
class DriverCancellation {
  const DriverCancellation({
    required this.driver,
    required this.toda,
    required this.reason,
    required this.at,
  });

  final String driver;
  final String toda;
  final String reason;
  final DateTime at;
}

/// Keep in sync with cancel_ride_as_driver (migration 20260928050000) and
/// the mobile SupabaseRideRepository.driverCancelReasons.
String driverCancelReasonLabel(String? value) => switch (value) {
  'passenger_no_show' => 'Passenger did not show up',
  'cannot_reach_pickup' => 'Could not reach the pickup',
  'vehicle_problem' => 'Vehicle problem',
  'safety_concern' => 'Safety concern',
  _ => 'No reason given',
};

class Ride {
  const Ride({
    required this.id,
    required this.driver,
    required this.rider,
    required this.toda,
    required this.status,
    required this.updatedMinutes,
    this.latitude,
    this.longitude,
    this.driverId,
    this.pickupLabel,
    this.destinationLabel,
  });

  factory Ride.fromRow(
    Map<String, dynamic> row, {
    Map<String, dynamic>? availability,
  }) {
    final updated = DateTime.tryParse(
      availability?['updated_at']?.toString() ??
          row['updated_at']?.toString() ??
          row['requested_at']?.toString() ??
          '',
    );
    return Ride(
      id: row['id'].toString(),
      driver: row['driver_display_name']?.toString() ?? 'Awaiting driver',
      rider: row['rider_display_name']?.toString() ?? 'Commuter',
      toda: row['toda_name']?.toString() ?? 'Assigned TODA',
      status: rideStatusLabel(row['status']?.toString() ?? 'requested'),
      // Driver GPS only. The trip's pickup may come from Google in the app,
      // and Google's terms forbid showing it on this MapLibre map.
      latitude: (availability?['latitude'] as num?)?.toDouble(),
      longitude: (availability?['longitude'] as num?)?.toDouble(),
      updatedMinutes: updated == null
          ? 0
          : DateTime.now()
                .difference(updated.toLocal())
                .inMinutes
                .clamp(0, 999),
      driverId: row['driver_id']?.toString(),
      pickupLabel: row['pickup_label']?.toString(),
      destinationLabel: row['destination_label']?.toString(),
    );
  }

  final String id;
  final String driver;
  final String rider;
  final String toda;
  final String status;

  /// Null until the assigned driver shares a location.
  final double? latitude;
  final double? longitude;
  final int updatedMinutes;
  final String? driverId;
  final String? pickupLabel;
  final String? destinationLabel;
}

const feedbackQuestionLabels = <String, String>{
  'ease_of_use': 'Ease of use',
  'booking_clarity': 'Booking and dispatch clarity',
  'navigation_clarity': 'Map and trip information',
  'fare_fairness': 'Trust in the approved fare',
  'reliability': 'Reliable app behavior',
  'safety_confidence': 'Safety visibility',
  'continued_use': 'Intention to keep using ArangCada',
};

class DriverAppFeedback {
  const DriverAppFeedback({
    required this.id,
    required this.toda,
    required this.scores,
    required this.anonymous,
    required this.submittedAt,
    this.comment,
    this.identifiedDriverName,
    this.todaZoneId,
  });

  factory DriverAppFeedback.fromRow(
    Map<String, dynamic> row, {
    String? todaName,
  }) {
    final answers = row['answers'] is Map
        ? Map<String, dynamic>.from(row['answers'] as Map)
        : row;
    final anonymous = row['is_anonymous'] as bool? ?? true;
    return DriverAppFeedback(
      id: row['id'].toString(),
      toda: todaName ?? row['toda_name']?.toString() ?? 'Assigned TODA',
      todaZoneId: row['toda_zone_id']?.toString(),
      scores: {
        for (final key in feedbackQuestionLabels.keys)
          if (answers[key] case final num score) key: score.toInt(),
      },
      anonymous: anonymous,
      identifiedDriverName: anonymous
          ? null
          : row['driver_display_name']?.toString() ??
                row['driver_name']?.toString(),
      comment: row['comment']?.toString(),
      submittedAt:
          DateTime.tryParse(
            row['submitted_at']?.toString() ??
                row['created_at']?.toString() ??
                '',
          )?.toLocal() ??
          DateTime.now(),
    );
  }

  final String id;
  final String toda;
  final String? todaZoneId;
  final Map<String, int> scores;
  final bool anonymous;
  final String? identifiedDriverName;
  final String? comment;
  final DateTime submittedAt;

  String get displayName => anonymous
      ? 'Anonymous driver'
      : identifiedDriverName ?? 'Identified driver';
}

class TodaFeedbackSummary {
  const TodaFeedbackSummary({
    required this.toda,
    required this.responseCount,
    required this.uniqueDrivers,
    required this.target,
    this.todaZoneId,
    this.overallMean,
    this.questionMeans = const {},
  });

  factory TodaFeedbackSummary.fromRow(Map<String, dynamic> row) {
    final means = row['question_means'] is Map
        ? Map<String, dynamic>.from(row['question_means'] as Map)
        : const <String, dynamic>{};
    return TodaFeedbackSummary(
      toda: row['toda_name']?.toString() ?? 'Assigned TODA',
      todaZoneId: row['toda_zone_id']?.toString(),
      responseCount: (row['response_count'] as num?)?.toInt() ?? 0,
      uniqueDrivers: (row['unique_driver_count'] as num?)?.toInt() ?? 0,
      target: (row['respondent_target'] as num?)?.toInt() ?? 10,
      overallMean: (row['overall_mean'] as num?)?.toDouble(),
      questionMeans: {
        for (final entry in means.entries)
          if (entry.value case final num value) entry.key: value.toDouble(),
      },
    );
  }

  final String toda;
  final String? todaZoneId;
  final int responseCount;
  final int uniqueDrivers;
  final int target;
  final double? overallMean;
  final Map<String, double> questionMeans;

  double get progress => target <= 0 ? 0 : (uniqueDrivers / target).clamp(0, 1);
}

class AuditEvent {
  const AuditEvent(this.title, this.detail, this.time, {this.toda});
  final String title;
  final String detail;
  final DateTime time;
  final String? toda;
}

class Boundary {
  const Boundary(this.name, this.color, this.coordinates);
  final String name;
  final int color;
  final List<List<double>> coordinates;
}

class AdminState {
  const AdminState({
    required this.drivers,
    required this.reports,
    required this.rides,
    required this.boundaries,
    required this.audit,
    required this.feedbackCounts,
    this.complaints = const [],
    this.ratings = const [],
    this.fareClassClaims = const [],
    this.reportedChats = const [],
    this.feedbackSummaries = const [],
    this.feedbackResponses = const [],
    this.driverCancellations = const [],
    this.feedbackInterval = 1,
    this.respondentTarget = 10,
    this.repeatFeedback = true,
    this.connected = false,
    this.loading = false,
    this.connectionError,
    this.driverQuery = '',
    this.driverStatus = 'All statuses',
    this.driverToda = 'All TODAs',
    this.compactDensity = false,
    this.desktopAlerts = true,
    this.unreadSafetyAlerts = 0,
    this.selectedRide,
    this.adminAccounts = const [],
    this.adminInvites = const [],
    this.todaZoneOptions = const [],
    this.driverInvites = const [],
  });

  final List<Driver> drivers;
  final List<SafetyReport> reports;
  final List<Complaint> complaints;
  final List<TripRating> ratings;
  final List<FareClassClaim> fareClassClaims;
  final List<Ride> rides;
  final List<Boundary> boundaries;
  final List<AuditEvent> audit;
  final Map<String, int> feedbackCounts;
  final List<ReportedTripChat> reportedChats;
  final List<TodaFeedbackSummary> feedbackSummaries;
  final List<DriverAppFeedback> feedbackResponses;
  final List<DriverCancellation> driverCancellations;
  final int feedbackInterval;
  final int respondentTarget;
  final bool repeatFeedback;
  final bool connected;
  final bool loading;
  final String? connectionError;
  final String driverQuery;
  final String driverStatus;
  final String driverToda;
  final bool compactDensity;
  final bool desktopAlerts;
  final int unreadSafetyAlerts;
  final String? selectedRide;
  // LGU-only, loaded on demand by AdminsScreen -- not part of the
  // main refresh()/AdminSnapshot, same reasoning reportedChats already
  // establishes: low-frequency, LGU-scoped data does not belong in the
  // snapshot every session polls on every table change.
  final List<AdminAccount> adminAccounts;
  final List<AdminInvite> adminInvites;
  final List<(String id, String name)> todaZoneOptions;
  // LGU-only, loaded on demand by DriversScreen -- same
  // on-demand-not-in-the-snapshot reasoning adminInvites above already
  // establishes. todaZoneOptions is shared with the Admins screen's own
  // invite dialog; either on-demand load populates the same field.
  final List<DriverInvite> driverInvites;

  AdminState copyWith({
    List<Driver>? drivers,
    List<SafetyReport>? reports,
    List<Complaint>? complaints,
    List<TripRating>? ratings,
    List<FareClassClaim>? fareClassClaims,
    List<Ride>? rides,
    List<AuditEvent>? audit,
    List<Boundary>? boundaries,
    Map<String, int>? feedbackCounts,
    List<ReportedTripChat>? reportedChats,
    List<TodaFeedbackSummary>? feedbackSummaries,
    List<DriverAppFeedback>? feedbackResponses,
    List<DriverCancellation>? driverCancellations,
    int? feedbackInterval,
    int? respondentTarget,
    bool? repeatFeedback,
    bool? connected,
    bool? loading,
    String? connectionError,
    bool clearConnectionError = false,
    String? driverQuery,
    String? driverStatus,
    String? driverToda,
    bool? compactDensity,
    bool? desktopAlerts,
    int? unreadSafetyAlerts,
    String? selectedRide,
    bool clearSelectedRide = false,
    List<AdminAccount>? adminAccounts,
    List<AdminInvite>? adminInvites,
    List<(String id, String name)>? todaZoneOptions,
    List<DriverInvite>? driverInvites,
  }) => AdminState(
    drivers: drivers ?? this.drivers,
    reports: reports ?? this.reports,
    complaints: complaints ?? this.complaints,
    ratings: ratings ?? this.ratings,
    fareClassClaims: fareClassClaims ?? this.fareClassClaims,
    rides: rides ?? this.rides,
    boundaries: boundaries ?? this.boundaries,
    audit: audit ?? this.audit,
    feedbackCounts: feedbackCounts ?? this.feedbackCounts,
    reportedChats: reportedChats ?? this.reportedChats,
    feedbackSummaries: feedbackSummaries ?? this.feedbackSummaries,
    feedbackResponses: feedbackResponses ?? this.feedbackResponses,
    driverCancellations: driverCancellations ?? this.driverCancellations,
    feedbackInterval: feedbackInterval ?? this.feedbackInterval,
    respondentTarget: respondentTarget ?? this.respondentTarget,
    repeatFeedback: repeatFeedback ?? this.repeatFeedback,
    connected: connected ?? this.connected,
    loading: loading ?? this.loading,
    connectionError: clearConnectionError
        ? null
        : connectionError ?? this.connectionError,
    driverQuery: driverQuery ?? this.driverQuery,
    driverStatus: driverStatus ?? this.driverStatus,
    driverToda: driverToda ?? this.driverToda,
    compactDensity: compactDensity ?? this.compactDensity,
    desktopAlerts: desktopAlerts ?? this.desktopAlerts,
    unreadSafetyAlerts: unreadSafetyAlerts ?? this.unreadSafetyAlerts,
    selectedRide: clearSelectedRide ? null : selectedRide ?? this.selectedRide,
    adminAccounts: adminAccounts ?? this.adminAccounts,
    adminInvites: adminInvites ?? this.adminInvites,
    todaZoneOptions: todaZoneOptions ?? this.todaZoneOptions,
    driverInvites: driverInvites ?? this.driverInvites,
  );
}

String driverStatusLabel(DriverStatus value) => switch (value) {
  DriverStatus.enrolled => 'Enrolled',
  DriverStatus.submitted => 'Documents submitted',
  DriverStatus.review => 'Under review',
  DriverStatus.approved => 'Approved',
  DriverStatus.rejected => 'Rejected',
  DriverStatus.suspended => 'Suspended',
  DriverStatus.expired => 'Expired',
};

String reportStatusLabel(ReportStatus value) => switch (value) {
  ReportStatus.newReport => 'New',
  ReportStatus.acknowledged => 'Acknowledged',
  ReportStatus.investigating => 'Investigating',
  ReportStatus.resolved => 'Resolved',
  ReportStatus.escalated => 'Escalated',
  ReportStatus.dismissed => 'Dismissed',
};

String safetyReportLabel(String value) =>
    value.length > 16 ? 'SOS-${value.substring(0, 8).toUpperCase()}' : value;

ReportStatus reportStatusFromServer(String? value) => switch (value) {
  'acknowledged' => ReportStatus.acknowledged,
  'investigating' => ReportStatus.investigating,
  'resolved' => ReportStatus.resolved,
  'escalated' => ReportStatus.escalated,
  'dismissed' => ReportStatus.dismissed,
  _ => ReportStatus.newReport,
};

String reportStatusToServer(ReportStatus value) => switch (value) {
  ReportStatus.newReport => 'new',
  ReportStatus.acknowledged => 'acknowledged',
  ReportStatus.investigating => 'investigating',
  ReportStatus.resolved => 'resolved',
  ReportStatus.escalated => 'escalated',
  ReportStatus.dismissed => 'dismissed',
};

String rideStatusLabel(String value) => switch (value) {
  'requested' || 'searching' || 'searching_driver' => 'Searching',
  'assigned' ||
  'accepted' ||
  'driver_assigned' ||
  'driver_en_route' => 'En route',
  'arrived' => 'Arriving',
  'started' || 'in_progress' => 'On trip',
  'completed' => 'Completed',
  // Who cancelled matters to TODA/LGU oversight now that drivers can
  // cancel during pickup (e.g. a passenger no-show).
  'cancelled_by_rider' => 'Cancelled by rider',
  'cancelled_by_driver' => 'Cancelled by driver',
  'cancelled' => 'Cancelled',
  'no_driver' || 'no_driver_available' => 'No driver',
  'emergency' || 'emergency_reported' => 'Emergency',
  _ => value,
};

bool isActiveTripStatus(String? value) => const {
  'requested',
  'searching_driver',
  'driver_assigned',
  'accepted',
  'driver_en_route',
  'arrived',
  'in_progress',
  'emergency_reported',
}.contains(value);

/// One LGU or TODA admin account, for the Admins screen.
class AdminAccount {
  const AdminAccount({
    required this.id,
    required this.email,
    required this.role,
    this.firstName,
    this.lastName,
    this.toda,
    this.invitedByName,
  });

  factory AdminAccount.fromRow(
    Map<String, dynamic> row, {
    String? toda,
    String? invitedByName,
  }) => AdminAccount(
    id: row['id'].toString(),
    email: row['email']?.toString() ?? '',
    role: row['scope'] == 'toda' ? AdminRole.toda : AdminRole.lgu,
    firstName: (row['first_name'] as String?)?.trim(),
    lastName: (row['last_name'] as String?)?.trim(),
    toda: toda,
    invitedByName: invitedByName,
  );

  final String id;
  final String email;
  final AdminRole role;
  final String? firstName;
  final String? lastName;
  final String? toda;
  // Name of the LGU admin who sent the invite this account was created
  // from -- null for an account that predates the invite system,
  // e.g. one promoted directly in the database, not a data gap.
  final String? invitedByName;

  String get name {
    final parts = [
      firstName,
      lastName,
    ].where((part) => part != null && part.isNotEmpty);
    if (parts.isNotEmpty) return parts.join(' ');
    // The account that predates invites is the one that started it all.
    return invitedByName == null
        ? 'Founding administrator'
        : 'Unnamed administrator';
  }
}

/// A pending or recently-decided LGU/TODA admin invite, for the Admins
/// screen's "Pending invites" list.
class AdminInvite {
  const AdminInvite({
    required this.id,
    required this.email,
    required this.scope,
    required this.status,
    required this.created,
    this.toda,
  });

  factory AdminInvite.fromRow(Map<String, dynamic> row, {String? toda}) =>
      AdminInvite(
        id: row['id'].toString(),
        email: row['email']?.toString() ?? '',
        scope: row['scope'] == 'toda' ? AdminRole.toda : AdminRole.lgu,
        status: row['status']?.toString() ?? 'pending',
        created:
            DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
        toda: toda,
      );

  final String id;
  final String email;
  final AdminRole scope;
  final String status;
  final DateTime created;
  final String? toda;
}

/// A pending driver enrollment invite, for the Drivers screen's own
/// "Pending driver invites" panel. Same shape as AdminInvite
///, minus the scope concept a driver invite has no use for.
class DriverInvite {
  const DriverInvite({
    required this.id,
    required this.email,
    required this.toda,
    required this.status,
    required this.created,
    this.bodyNumber,
  });

  factory DriverInvite.fromRow(Map<String, dynamic> row, {String? toda}) =>
      DriverInvite(
        id: row['id'].toString(),
        email: row['email']?.toString() ?? '',
        toda: toda,
        status: row['status']?.toString() ?? 'pending',
        created:
            DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
        bodyNumber: (row['body_number'] as String?)?.trim(),
      );

  final String id;
  final String email;
  final String? toda;
  final String status;
  final DateTime created;
  final String? bodyNumber;
}

/// One row from admin_preview_driver_candidate() -- an existing account
/// that already matches the email an LGU admin is trying to enroll as a
/// driver. Deliberately carries no id (the RPC itself returns none, by
/// design -- see the migration comment) and only a masked name.
class DriverCandidate {
  const DriverCandidate({
    required this.maskedName,
    required this.accountRole,
    required this.accountStatus,
    required this.joinedOn,
    required this.tripCount,
  });

  factory DriverCandidate.fromRow(Map<String, dynamic> row) => DriverCandidate(
    maskedName: row['masked_name']?.toString() ?? '',
    accountRole: row['account_role']?.toString() ?? '',
    accountStatus: row['account_status']?.toString() ?? '',
    joinedOn: row['joined_on']?.toString() ?? '',
    tripCount: (row['trip_count'] as num?)?.toInt() ?? 0,
  );

  final String maskedName;
  final String accountRole;
  final String accountStatus;
  final String joinedOn;
  final int tripCount;
}
