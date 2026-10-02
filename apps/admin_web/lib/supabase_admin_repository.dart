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
    this.driverCancellations = const [],
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
  final List<DriverCancellation> driverCancellations;
  final int feedbackInterval;
  final int respondentTarget;
  final bool repeatFeedback;
}

/// LGU-only, loaded on demand by AdminsScreen -- see AdminSnapshot's own
/// docstring precedent (reportedChats) for why this is not folded into the
/// main snapshot.
class AdminAccountsSnapshot {
  const AdminAccountsSnapshot({
    required this.accounts,
    required this.invites,
    required this.todaZoneOptions,
  });

  final List<AdminAccount> accounts;
  final List<AdminInvite> invites;
  final List<(String id, String name)> todaZoneOptions;
}

/// Redeems the one link this console accepts a session from: the
/// password-reset link it asked for (see [SupabaseAdminRepository.sendPasswordReset]).
///
/// supabase_flutter's own handling is switched off in main.dart because it
/// also takes an `access_token`/`refresh_token` pair from any URL and replaces
/// the signed-in session with it, so a crafted link could sign an
/// administrator's browser into somebody else's account. A `code` is only
/// exchanged together with the verifier this browser stored when it requested
/// the reset, so a link made anywhere else is refused.
Future<void> redeemResetLink(Uri uri, GoTrueClient auth) async {
  final code = uri.queryParameters['code'];
  if (uri.path != '/reset-password' || code == null) return;
  try {
    await auth.exchangeCodeForSession(code);
  } on AuthException {
    // Expired, already used, or not requested from this browser. The reset
    // page then says the link has expired.
  }
}

class SupabaseAdminRepository {
  SupabaseAdminRepository(this.client);

  final SupabaseClient client;
  RealtimeChannel? _channel;
  Timer? _refreshDebounce;

  bool get hasSession => client.auth.currentSession != null;

  /// Self-service email password reset -- staff are always email-bound now
  /// (direct promotion and the invite flow, both require a real
  /// address), so a server-verified admin-to-admin reset workflow is no
  /// longer needed for this. Supabase does not reveal whether the address
  /// belongs to an account either way, matching how every other auth
  /// surface in this project avoids account-enumeration.
  ///
  /// The email link returns to this console's /reset-password page, where
  /// the person chooses a new password (see ResetPasswordScreen). The URL must
  /// be in Supabase Auth's allowed redirect URLs; otherwise Supabase falls
  /// back to the project's Site URL.
  Future<void> sendPasswordReset(String email) async {
    await client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: kIsWeb ? '${Uri.base.origin}/reset-password' : null,
    );
  }

  /// Sets the new password with the short-lived recovery session from the
  /// reset link, then ends that session so the person signs in normally.
  Future<void> completePasswordReset(String newPassword) async {
    await client.auth.updateUser(UserAttributes(password: newPassword));
    await client.auth.signOut();
  }

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
        .select('id, role, display_name, status, avatar_path')
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
      avatarUrl: await _signedAvatarUrl(profile['avatar_path'] as String?),
    );
  }

  /// A fresh signed URL for [avatarPath], or null when there is no photo or
  /// minting one fails -- mirrors apps/mobile's own
  /// SupabaseAuthRepository._signedAvatarUrl exactly: an unreadable avatar
  /// must never block the rest of session resolution.
  Future<String?> _signedAvatarUrl(String? avatarPath) async {
    if (avatarPath == null || avatarPath.isEmpty) return null;
    try {
      return await client.storage
          .from('profile-photos')
          .createSignedUrl(avatarPath, 300);
    } on StorageException {
      return null;
    }
  }

  /// Uploads a new profile photo for the signed-in admin. Same bucket/path
  /// shape as apps/mobile's own uploadProfilePhoto -- profile-photos'
  /// Storage RLS is role-agnostic (any authenticated user owns their own
  /// auth.uid() folder), so nothing new was needed server-side for this.
  Future<String> uploadProfilePhoto({
    required List<int> bytes,
    required String fileExtension,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in again to change your photo.');
    }
    final path =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    try {
      await client.storage
          .from('profile-photos')
          .uploadBinary(path, Uint8List.fromList(bytes));
    } on StorageException catch (error) {
      throw StateError(
        error.message.isEmpty
            ? 'Could not upload that photo. Try again.'
            : error.message,
      );
    }
    return path;
  }

  /// Points profiles.avatar_path at the newly uploaded photo and returns a
  /// freshly resolved session (mints the new signed URL the UI displays) --
  /// same re-read-rather-than-patch shape apps/mobile's own
  /// updateAvatarPath uses.
  Future<AdminSession> updateAvatarPath(String path) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in again to change your photo.');
    }
    try {
      await client
          .from('profiles')
          .update({'avatar_path': path})
          .eq('id', user.id);
    } on PostgrestException {
      throw StateError('Could not save your photo. Try again.');
    }
    return _resolveSession(user);
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
            'pickup_label, destination_label, rider_display_name, '
            'driver_display_name, toda_name, updated_at, cancellation_reason',
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

    // Known limit: only sees driver cancellations among the 100 most recent
    // trips; query them separately if volume outgrows that.
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final driverCancellations = <DriverCancellation>[
      for (final row in tripRows)
        if (row['status'] == 'cancelled_by_driver')
          if (DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal()
              case final at? when at.isAfter(weekAgo))
            DriverCancellation(
              driver: row['driver_display_name']?.toString() ?? 'Driver',
              toda: row['toda_name']?.toString() ?? 'Assigned TODA',
              reason: driverCancelReasonLabel(
                row['cancellation_reason']?.toString(),
              ),
              at: at,
            ),
    ];

    final rides = <Ride>[];
    for (final row in tripRows) {
      if (!isActiveTripStatus(row['status']?.toString())) {
        continue;
      }
      rides.add(
        Ride.fromRow(
          row,
          availability: locations[row['driver_id']?.toString()],
        ),
      );
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
      driverCancellations: driverCancellations,
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
      // fare_class_claims/driver_invites added 9 Sep 2026 -- the owner
      // reported a driver's enrolled status and a submitted discount claim
      // both needing a manual page reload to appear. driver_profiles was
      // already covered; these two were not.
      'fare_class_claims',
      'driver_invites',
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

  Future<void> updateDriverName({
    required String driverId,
    required String firstName,
    required String lastName,
    String? reason,
  }) async {
    await client.rpc(
      'admin_update_driver_name',
      params: {
        'p_driver_id': driverId,
        'p_first_name': firstName.trim(),
        'p_last_name': lastName.trim(),
        'p_reason': reason?.trim(),
      },
    );
  }

  Future<void> updateDriverRecord({
    required String driverId,
    required String firstName,
    required String lastName,
    required String plateNumber,
    required String bodyNumber,
    required String todaZoneId,
    DateTime? licenseExpiresOn,
  }) async {
    await client.rpc(
      'admin_update_driver_record',
      params: {
        'p_driver_id': driverId,
        'p_first_name': firstName.trim(),
        'p_last_name': lastName.trim(),
        'p_plate_number': plateNumber.trim(),
        'p_body_number': bodyNumber.trim(),
        'p_toda_zone_id': todaZoneId,
        'p_license_expires_on': licenseExpiresOn == null
            ? null
            : '${licenseExpiresOn.year.toString().padLeft(4, '0')}-${licenseExpiresOn.month.toString().padLeft(2, '0')}-${licenseExpiresOn.day.toString().padLeft(2, '0')}',
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
  /// of their own photo goes through.
  Future<String> fareClassClaimPhotoUrl(String path) async {
    final signed = await client.storage
        .from('discount-eligibility-ids')
        .createSignedUrl(path, 300);
    return signed;
  }

  /// A short-lived signed URL for a driver's uploaded document -- same
  /// shape as fareClassClaimPhotoUrl, gated by
  /// driver_documents_photos_select_own_or_admin instead.
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
    await client.storage.from('driver-documents').uploadBinary(path, bytes);
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

  /// LGU admin accounts, TODA admin accounts, pending invites, and the
  /// TODA-zone picker options for the invite dialog -- one on-demand load,
  /// not part of the main snapshot (see AdminAccountsSnapshot above).
  Future<AdminAccountsSnapshot> loadAdminAccounts() async {
    final results = await Future.wait<dynamic>([
      client
          .from('profiles')
          .select('id, first_name, last_name, email')
          .eq('role', 'admin')
          .eq('status', 'active'),
      client
          .from('admin_scopes')
          .select('admin_id, scope, toda_zone_id, toda_zones(name)'),
      client
          .from('admin_invites')
          .select(
            'id, email, scope, toda_zone_id, status, created_at, toda_zones(name)',
          )
          .eq('status', 'pending')
          .order('created_at', ascending: false),
      client
          .from('toda_zones')
          .select('id, name')
          .eq('is_active', true)
          .order('name'),
      // Traces each existing admin back to whoever invited them, for the
      // Admins screen's own accountability trail -- an account that
      // predates the invite system (e.g. a direct database promotion)
      // simply has no row here, which is correct, not a data gap.
      client
          .from('admin_invites')
          .select('accepted_user_id, invited_by')
          .eq('status', 'accepted'),
    ]);

    final profileRows = _rows(results[0]);
    final scopeRows = _rows(results[1]);
    final inviteRows = _rows(results[2]);
    final zoneRows = _rows(results[3]);
    final acceptedRows = _rows(results[4]);

    final scopeByAdmin = <String, Map<String, dynamic>>{
      for (final row in scopeRows) row['admin_id'].toString(): row,
    };
    final invitedByAdminId = <String, String>{
      for (final row in acceptedRows)
        if (row['accepted_user_id'] != null && row['invited_by'] != null)
          row['accepted_user_id'].toString(): row['invited_by'].toString(),
    };

    final accounts = [
      for (final row in profileRows)
        AdminAccount.fromRow(
          {...row, 'scope': scopeByAdmin[row['id'].toString()]?['scope']},
          toda:
              (scopeByAdmin[row['id'].toString()]?['toda_zones']
                      as Map?)?['name']
                  ?.toString(),
        ),
    ];
    final accountsById = {for (final account in accounts) account.id: account};

    return AdminAccountsSnapshot(
      accounts: [
        for (final account in accounts)
          AdminAccount(
            id: account.id,
            email: account.email,
            role: account.role,
            firstName: account.firstName,
            lastName: account.lastName,
            toda: account.toda,
            invitedByName: accountsById[invitedByAdminId[account.id]]?.name,
          ),
      ],
      invites: [
        for (final row in inviteRows)
          AdminInvite.fromRow(
            row,
            toda: (row['toda_zones'] as Map?)?['name']?.toString(),
          ),
      ],
      todaZoneOptions: [
        for (final row in zoneRows)
          (row['id'].toString(), row['name'].toString()),
      ],
    );
  }

  /// Sends an LGU or TODA admin invite by email. Calls the send-admin-invite
  /// Edge Function -- the RPC it wraps (admin_create_invite) cannot send
  /// email itself, and the Resend API key must never reach this client.
  Future<void> sendAdminInvite({
    required String email,
    required String scope,
    String? todaZoneId,
  }) async {
    try {
      await client.functions.invoke(
        'send-admin-invite',
        body: {'email': email, 'scope': scope, 'toda_zone_id': todaZoneId},
      );
    } on FunctionException catch (error) {
      throw StateError(
        _functionErrorMessage(error) ?? 'The invite could not be sent.',
      );
    }
  }

  Future<void> revokeAdminInvite(String inviteId) async {
    await client.rpc('admin_revoke_invite', params: {'p_invite_id': inviteId});
  }

  /// Turns another administrator back into an ordinary account (LGU only;
  /// never the caller). See admin_remove_admin (20260929020000).
  Future<void> removeAdmin(String adminId) async {
    try {
      await client.rpc('admin_remove_admin', params: {'p_admin_id': adminId});
    } on PostgrestException catch (error) {
      throw StateError(
        error.code == '22023'
            ? error.message
            : 'This administrator could not be removed.',
      );
    }
  }

  /// Resolves an invite token to its locked email for the public accept
  /// page. Called with the anon key -- no session exists yet.
  Future<String> lookupAdminInvite(String token) async {
    final rows = _rows(
      await client.rpc('admin_invite_lookup', params: {'p_token': token}),
    );
    final email = rows.isEmpty ? null : rows.first['email']?.toString();
    if (email == null || email.isEmpty) {
      throw StateError('This invite is invalid or has expired.');
    }
    return email;
  }

  /// Creates the invited administrator's account. Calls the
  /// accept-admin-invite Edge Function -- only the Auth Admin API can create
  /// this account, and it requires the service-role key this client never
  /// holds. Does not sign the caller in; the accept-invite screen does that
  /// itself afterwards via signIn(), the same one the login screen uses.
  Future<void> acceptAdminInvite({
    required String token,
    required String firstName,
    required String lastName,
    required String password,
  }) async {
    try {
      await client.functions.invoke(
        'accept-admin-invite',
        body: {
          'token': token,
          'first_name': firstName,
          'last_name': lastName,
          'password': password,
        },
      );
    } on FunctionException catch (error) {
      throw StateError(
        _functionErrorMessage(error) ?? 'The account could not be created.',
      );
    }
  }

  static String? _functionErrorMessage(FunctionException error) {
    final details = error.details;
    return details is Map ? details['error']?.toString() : null;
  }

  /// Existing-account candidates matching an email, for the "enroll driver"
  /// dialog's first step. Deliberately returns whatever
  /// admin_preview_driver_candidate() returns -- no uuid, a masked name --
  /// and does not decide anything; the caller (the dialog) shows this to
  /// the admin and asks them to confirm before promoting.
  Future<List<DriverCandidate>> previewDriverCandidate(String email) async {
    final rows = _rows(
      await client.rpc(
        'admin_preview_driver_candidate',
        params: {'p_email': email},
      ),
    );
    return [for (final row in rows) DriverCandidate.fromRow(row)];
  }

  /// Promotes an existing account to driver. p_confirm_value is the email
  /// re-typed by hand -- the RPC's own safeguard against a mistyped
  /// identifier silently promoting an uninvolved commuter, not something
  /// this method adds on top.
  Future<void> promoteCommuterToDriver({
    required String email,
    required String confirmValue,
    required String todaZoneId,
    String? bodyNumber,
    String? reason,
  }) async {
    await client.rpc(
      'admin_promote_commuter_to_driver',
      params: {
        'p_match_by': 'email',
        'p_email': email,
        'p_confirm_value': confirmValue,
        'p_toda_zone_id': todaZoneId,
        'p_body_number': bodyNumber,
        'p_reason': reason,
      },
    );
  }

  /// Sends a driver enrollment invite by email. Calls the
  /// send-driver-invite Edge Function -- the RPC it wraps
  /// (admin_create_driver_invite) cannot send email itself, and the Resend
  /// API key must never reach this client.
  Future<void> sendDriverInvite({
    required String email,
    required String todaZoneId,
    String? bodyNumber,
  }) async {
    try {
      await client.functions.invoke(
        'send-driver-invite',
        body: {
          'email': email,
          'toda_zone_id': todaZoneId,
          'body_number': bodyNumber,
        },
      );
    } on FunctionException catch (error) {
      throw StateError(
        _functionErrorMessage(error) ?? 'The invite could not be sent.',
      );
    }
  }

  Future<void> revokeDriverInvite(String inviteId) async {
    await client.rpc(
      'admin_revoke_driver_invite',
      params: {'p_invite_id': inviteId},
    );
  }

  /// Pending driver invites and the TODA-zone picker options for the
  /// enroll-driver dialog -- one on-demand load, not part of the main
  /// snapshot, same reasoning loadAdminAccounts() establishes.
  Future<({List<DriverInvite> invites, List<(String id, String name)> zones})>
  loadDriverInvites() async {
    final results = await Future.wait<dynamic>([
      client
          .from('driver_invites')
          .select(
            'id, email, toda_zone_id, body_number, status, created_at, toda_zones(name)',
          )
          .eq('status', 'pending')
          .order('created_at', ascending: false),
      client.from('toda_zones').select('id, name').order('name'),
    ]);

    final inviteRows = _rows(results[0]);
    final zoneRows = _rows(results[1]);

    return (
      invites: [
        for (final row in inviteRows)
          DriverInvite.fromRow(
            row,
            toda: (row['toda_zones'] as Map?)?['name']?.toString(),
          ),
      ],
      zones: [
        for (final row in zoneRows)
          (row['id'].toString(), row['name'].toString()),
      ],
    );
  }

  /// Resolves a driver invite token to its locked email and TODA zone
  /// name, for the public accept page. Called with the anon key -- no
  /// session exists yet.
  Future<({String email, String todaZoneName})> lookupDriverInvite(
    String token,
  ) async {
    final rows = _rows(
      await client.rpc('driver_invite_lookup', params: {'p_token': token}),
    );
    final email = rows.isEmpty ? null : rows.first['email']?.toString();
    final zone = rows.isEmpty ? null : rows.first['toda_zone_name']?.toString();
    if (email == null || email.isEmpty) {
      throw StateError('This invite is invalid or has expired.');
    }
    return (email: email, todaZoneName: zone ?? 'your TODA');
  }

  /// Creates the invited driver's account. Calls the accept-driver-invite
  /// Edge Function -- only the Auth Admin API can create this account, and
  /// it requires the service-role key this client never holds. Does not
  /// sign the driver in anywhere -- a driver account cannot open an
  /// admin_web session at all (see AcceptDriverInviteScreen).
  Future<void> acceptDriverInvite({
    required String token,
    required String displayName,
    required String mobileNumber,
    required String password,
  }) async {
    try {
      await client.functions.invoke(
        'accept-driver-invite',
        body: {
          'token': token,
          'display_name': displayName,
          'mobile_number': mobileNumber,
          'password': password,
        },
      );
    } on FunctionException catch (error) {
      throw StateError(
        _functionErrorMessage(error) ?? 'The account could not be created.',
      );
    }
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
