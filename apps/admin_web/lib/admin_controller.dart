import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'models.dart';
import 'supabase_admin_repository.dart';

final adminRepositoryProvider = Provider<SupabaseAdminRepository?>((ref) {
  if (!AdminAppConfig.isSupabaseConfigured) return null;
  try {
    final repository = SupabaseAdminRepository(Supabase.instance.client);
    ref.onDispose(repository.dispose);
    return repository;
  } on AssertionError {
    return null;
  } on StateError {
    return null;
  }
});

final adminProvider = NotifierProvider<AdminController, AdminState>(
  AdminController.new,
);

class AdminController extends Notifier<AdminState> {
  AdminSession? _connectedSession;
  bool _refreshing = false;
  bool _refreshPending = false;

  @override
  AdminState build() => seedAdminState();

  Future<void> connect(AdminSession session) async {
    if (!session.connected) {
      _connectedSession = null;
      state = seedAdminState();
      return;
    }
    if (ref.read(adminRepositoryProvider) == null) {
      throw StateError('The Supabase administrator connection is unavailable.');
    }
    _connectedSession = session;
    state = const AdminState(
      drivers: [],
      reports: [],
      rides: [],
      boundaries: [],
      audit: [],
      feedbackCounts: {},
      connected: true,
      loading: true,
    );
    await refresh();
    if (_connectedSession != session) return;
    ref
        .read(adminRepositoryProvider)!
        .subscribe(
          session: session,
          onDataChanged: () => unawaited(refresh()),
          onSafetyInserted: _notifyNewSafetyReport,
        );
  }

  Future<void> refresh() async {
    final session = _connectedSession;
    final repository = ref.read(adminRepositoryProvider);
    if (session == null || repository == null) return;
    if (_refreshing) {
      _refreshPending = true;
      return;
    }
    _refreshing = true;
    try {
      final snapshot = await repository.load(session);
      if (_connectedSession != session) return;
      state = state.copyWith(
        drivers: snapshot.drivers,
        reports: snapshot.reports,
        complaints: snapshot.complaints,
        ratings: snapshot.ratings,
        reportedChats: snapshot.reportedChats,
        rides: snapshot.rides,
        boundaries: snapshot.boundaries,
        feedbackSummaries: snapshot.feedbackSummaries,
        feedbackResponses: snapshot.feedbackResponses,
        feedbackCounts: {
          for (final item in snapshot.feedbackSummaries)
            item.toda: item.uniqueDrivers,
        },
        feedbackInterval: snapshot.feedbackInterval,
        respondentTarget: snapshot.respondentTarget,
        repeatFeedback: snapshot.repeatFeedback,
        connected: true,
        loading: false,
        clearConnectionError: true,
      );
    } catch (_) {
      if (_connectedSession == session) {
        state = state.copyWith(
          loading: false,
          connectionError:
              'Connected records could not be refreshed. Check your administrator scope and deployed database migrations.',
        );
      }
      rethrow;
    } finally {
      _refreshing = false;
      if (_refreshPending) {
        _refreshPending = false;
        unawaited(refresh());
      }
    }
  }

  Future<void> disconnect() async {
    final session = _connectedSession;
    _connectedSession = null;
    if (session != null) await ref.read(adminRepositoryProvider)?.signOut();
    state = seedAdminState();
  }

  void _notifyNewSafetyReport() {
    state = state.copyWith(unreadSafetyAlerts: state.unreadSafetyAlerts + 1);
    if (state.desktopAlerts) {
      unawaited(SystemSound.play(SystemSoundType.alert).catchError((_) {}));
    }
  }

  void clearSafetyNotifications() =>
      state = state.copyWith(unreadSafetyAlerts: 0);

  List<Driver> scopedDrivers(AdminSession session) => state.drivers
      .where(
        (driver) =>
            session.role == AdminRole.lgu || driver.toda == session.toda,
      )
      .toList();

  List<Driver> visibleDrivers(AdminSession session) {
    final query = state.driverQuery.toLowerCase();
    return scopedDrivers(session).where((driver) {
      final matchesQuery =
          query.isEmpty ||
          '${driver.name} ${driver.plate} ${driver.enrollmentCode}'
              .toLowerCase()
              .contains(query);
      final matchesStatus =
          state.driverStatus == 'All statuses' ||
          (state.driverStatus == 'Needs review' &&
              (driver.status == DriverStatus.submitted ||
                  driver.status == DriverStatus.review)) ||
          driverStatusLabel(driver.status) == state.driverStatus;
      final matchesToda =
          state.driverToda == 'All TODAs' || driver.toda == state.driverToda;
      return matchesQuery && matchesStatus && matchesToda;
    }).toList();
  }

  List<Ride> visibleRides(AdminSession session) => state.rides
      .where(
        (ride) => session.role == AdminRole.lgu || ride.toda == session.toda,
      )
      .toList();

  List<SafetyReport> visibleReports(AdminSession session) => state.reports
      .where(
        (report) =>
            session.role == AdminRole.lgu || report.toda == session.toda,
      )
      .toList();

  List<Complaint> visibleComplaints(AdminSession session) => state.complaints
      .where(
        (complaint) =>
            session.role == AdminRole.lgu || complaint.toda == session.toda,
      )
      .toList();

  List<TripRating> visibleRatings(AdminSession session) => state.ratings
      .where(
        (rating) =>
            session.role == AdminRole.lgu || rating.toda == session.toda,
      )
      .toList();

  List<ReportedTripChat> visibleReportedChats(AdminSession session) =>
      session.role == AdminRole.lgu
      ? List.unmodifiable(state.reportedChats)
      : const [];

  /// LGU-only, same as visibleReportedChats -- commuters have no TODA
  /// affiliation, so there is no per-TODA scope for a discount claim to
  /// belong to. A TODA-scoped admin sees none, not an error.
  List<FareClassClaim> visibleFareClassClaims(AdminSession session) =>
      session.role == AdminRole.lgu
      ? List.unmodifiable(state.fareClassClaims)
      : const [];

  Future<void> refreshReportedChats(AdminSession session) async {
    if (session.role != AdminRole.lgu) {
      throw StateError('Reported conversations are restricted to LGU review.');
    }
    if (!state.connected || _connectedSession != session) return;
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) throw StateError('Administrator session expired.');
    final reports = await repository.loadReportedChats(session);
    if (_connectedSession == session) {
      state = state.copyWith(reportedChats: reports);
    }
  }

  List<AuditEvent> visibleAudit(AdminSession session) => state.audit
      .where(
        (event) => session.role == AdminRole.lgu || event.toda == session.toda,
      )
      .toList();

  void setDriverQuery(String value) =>
      state = state.copyWith(driverQuery: value);
  void setDriverStatus(String value) =>
      state = state.copyWith(driverStatus: value);
  void setDriverToda(String value) => state = state.copyWith(driverToda: value);
  void selectRide(String? id) =>
      state = state.copyWith(selectedRide: id, clearSelectedRide: id == null);
  void setCompactDensity(bool value) =>
      state = state.copyWith(compactDensity: value);
  void setDesktopAlerts(bool value) =>
      state = state.copyWith(desktopAlerts: value);

  Future<void> updateOwnPassword({
    required AdminSession session,
    required String currentPassword,
    required String newPassword,
  }) async {
    final repository = ref.read(adminRepositoryProvider);
    final email = session.email;
    final userId = session.userId;
    if (!session.connected ||
        repository == null ||
        email == null ||
        userId == null) {
      throw StateError('Password changes require a connected account.');
    }
    await repository.updateOwnPassword(
      expectedUserId: userId,
      email: email,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  void recordDemoFeedbackResponse(AdminSession session, String toda) {
    if (state.connected) {
      throw StateError('Connected feedback can only be submitted by drivers.');
    }
    if (session.role == AdminRole.toda && session.toda != toda) {
      throw StateError('Feedback must stay within the assigned TODA.');
    }
    final count = state.feedbackCounts[toda];
    if (count == null) throw ArgumentError.value(toda, 'toda', 'Unknown TODA');
    state = state.copyWith(
      feedbackCounts: {...state.feedbackCounts, toda: count + 1},
      audit: [
        AuditEvent(
          'Driver app feedback received',
          '$toda · unique driver participant',
          DateTime.now(),
          toda: toda,
        ),
        ...state.audit,
      ],
    );
  }

  void resetViewFilters() => state = state.copyWith(
    driverQuery: '',
    driverStatus: 'All statuses',
    driverToda: 'All TODAs',
    clearSelectedRide: true,
  );

  Driver enrollDriver({
    required String name,
    required String toda,
    required String phone,
    required String plate,
  }) {
    if (state.connected) {
      throw StateError('Connected driver onboarding starts in the mobile app.');
    }
    final id =
        state.drivers.fold<int>(0, (max, item) {
          final value = int.tryParse(item.id) ?? 0;
          return value > max ? value : max;
        }) +
        1;
    final driver = Driver(
      id: id.toString(),
      name: name.trim(),
      toda: toda,
      phone: phone.trim(),
      plate: plate.trim().toUpperCase(),
      status: DriverStatus.enrolled,
      documents: 0,
      enrollmentCode: 'AC-2026-${id.toString().padLeft(4, '0')}',
      updated: DateTime.now(),
    );
    state = state.copyWith(
      drivers: [driver, ...state.drivers],
      audit: [
        AuditEvent(
          'Driver enrolled',
          '${driver.name} · ${driver.toda}',
          DateTime.now(),
          toda: driver.toda,
        ),
        ...state.audit,
      ],
    );
    return driver;
  }

  Future<void> updateDriver(
    String id,
    DriverStatus status,
    String reason,
  ) async {
    final current = state.drivers.firstWhere((driver) => driver.id == id);
    final session = _connectedSession;
    if (state.connected) {
      if (session == null) throw StateError('Administrator session expired.');
      await ref
          .read(adminRepositoryProvider)!
          .updateDriver(
            driver: current,
            status: status,
            reason: reason,
            session: session,
          );
      await refresh();
      return;
    }
    state = state.copyWith(
      drivers: [
        for (final driver in state.drivers)
          if (driver.id == id)
            driver.copyWith(status: status, updated: DateTime.now())
          else
            driver,
      ],
      audit: [
        AuditEvent(
          '${driverStatusLabel(status)} driver',
          '${current.name} · $reason',
          DateTime.now(),
          toda: current.toda,
        ),
        ...state.audit,
      ],
    );
  }

  Future<void> transitionReport(
    String id,
    ReportStatus status,
    String note,
  ) async {
    final current = state.reports.firstWhere((report) => report.id == id);
    final session = _connectedSession;
    if (state.connected) {
      if (session == null) throw StateError('Administrator session expired.');
      await ref
          .read(adminRepositoryProvider)!
          .updateSafetyReport(
            reportId: id,
            status: status,
            note: note,
            session: session,
          );
      await refresh();
      return;
    }
    state = state.copyWith(
      reports: [
        for (final report in state.reports)
          if (report.id == id)
            report.copyWith(
              status: status,
              notes: [
                ...report.notes,
                note.trim().isEmpty
                    ? 'Status changed to ${reportStatusLabel(status)}.'
                    : note.trim(),
              ],
            )
          else
            report,
      ],
      audit: [
        AuditEvent(
          'Safety report updated',
          '$id · ${reportStatusLabel(status)}',
          DateTime.now(),
          toda: current.toda,
        ),
        ...state.audit,
      ],
    );
  }

  Future<void> transitionComplaint(
    String id,
    ReportStatus status,
    String note,
  ) async {
    final current = state.complaints.firstWhere(
      (complaint) => complaint.id == id,
    );
    final session = _connectedSession;
    if (state.connected) {
      if (session == null) throw StateError('Administrator session expired.');
      await ref
          .read(adminRepositoryProvider)!
          .updateComplaint(complaintId: id, status: status, note: note);
      await refresh();
      return;
    }
    state = state.copyWith(
      complaints: [
        for (final complaint in state.complaints)
          if (complaint.id == id)
            complaint.copyWith(
              status: status,
              notes: [
                ...complaint.notes,
                note.trim().isEmpty
                    ? 'Status changed to ${reportStatusLabel(status)}.'
                    : note.trim(),
              ],
            )
          else
            complaint,
      ],
      audit: [
        AuditEvent(
          'Complaint updated',
          '$id · ${reportStatusLabel(status)}',
          DateTime.now(),
          toda: current.toda,
        ),
        ...state.audit,
      ],
    );
  }

  /// A short-lived signed URL for a claim's submitted ID photo. Thin
  /// passthrough kept here rather than read directly off the repository
  /// provider, matching how every other screen action goes through this
  /// controller instead of the repository.
  Future<String> fareClassClaimPhotoUrl(String path) {
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) {
      // A rejected Future, not a synchronous throw: _ClaimPhoto calls this
      // from initState() and hands the result straight to a FutureBuilder,
      // which can only show an error state for a Future that actually
      // completes with one -- a synchronous throw here crashed the whole
      // console instead (caught by a widget test, not manually).
      return Future.error(
        StateError('Viewing a claim photo requires the live Supabase connection.'),
      );
    }
    return repository.fareClassClaimPhotoUrl(path);
  }

  /// Real-data-only, unlike transitionComplaint above: there is no seeded
  /// demo claim to mutate (seedAdminState() carries none, matching how
  /// reportedChats stays empty in demo mode too), so this always requires the
  /// live Supabase connection rather than offering a local-mutation fallback.
  Future<void> reviewFareClassClaim({
    required String claimId,
    required bool approve,
    String? rejectionReason,
  }) async {
    if (!state.connected) {
      throw StateError(
        'Discount claim review requires the live Supabase connection.',
      );
    }
    await ref
        .read(adminRepositoryProvider)!
        .reviewFareClassClaim(
          claimId: claimId,
          approve: approve,
          rejectionReason: rejectionReason,
        );
    await refresh();
  }

  /// A short-lived signed URL for a driver's uploaded document. Same
  /// rejected-Future-not-a-throw shape as fareClassClaimPhotoUrl above, and
  /// for the same reason.
  Future<String> driverDocumentPhotoUrl(String path) {
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) {
      return Future.error(
        StateError('Viewing a driver document requires the live Supabase connection.'),
      );
    }
    return repository.driverDocumentPhotoUrl(path);
  }

  /// Real-data-only, matching reviewFareClassClaim above -- local demo mode
  /// has no Storage bucket and no RPC to call, so this always requires the
  /// live Supabase connection rather than a local-mutation fallback.
  Future<void> uploadDriverDocument({
    required String driverId,
    required String documentType,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    if (!state.connected) {
      throw StateError(
        'Uploading a driver document requires the live Supabase connection.',
      );
    }
    await ref
        .read(adminRepositoryProvider)!
        .uploadDriverDocument(
          driverId: driverId,
          documentType: documentType,
          bytes: bytes,
          fileExtension: fileExtension,
        );
    await refresh();
  }

  Future<void> reviewDriverDocument({
    required String documentId,
    required bool approve,
    String? rejectionReason,
  }) async {
    if (!state.connected) {
      throw StateError(
        'Driver document review requires the live Supabase connection.',
      );
    }
    await ref
        .read(adminRepositoryProvider)!
        .reviewDriverDocument(
          documentId: documentId,
          approve: approve,
          rejectionReason: rejectionReason,
        );
    await refresh();
  }

  Future<void> updateFeedbackSettings({
    required AdminSession session,
    required int feedbackInterval,
    int? respondentTarget,
    bool? repeatFeedback,
  }) async {
    if (session.role != AdminRole.lgu) {
      throw StateError(
        'Only an LGU administrator can change global feedback settings.',
      );
    }
    if (feedbackInterval < 1) {
      throw ArgumentError.value(
        feedbackInterval,
        'feedbackInterval',
        'Must be positive.',
      );
    }
    final target = respondentTarget ?? state.respondentTarget;
    final repeat = repeatFeedback ?? state.repeatFeedback;
    if (state.connected) {
      await ref
          .read(adminRepositoryProvider)!
          .updateFeedbackSettings(
            feedbackInterval: feedbackInterval,
            respondentTarget: target,
            repeatFeedback: repeat,
          );
      await refresh();
      return;
    }
    state = state.copyWith(
      feedbackInterval: feedbackInterval,
      respondentTarget: target,
      repeatFeedback: repeat,
    );
  }
  /// LGU-only. Loaded on demand by AdminsScreen, not part of the main
  /// refresh() snapshot -- same reasoning refreshReportedChats already
  /// establishes for its own LGU-only, low-frequency data.
  Future<void> refreshAdminAccounts(AdminSession session) async {
    if (session.role != AdminRole.lgu) {
      throw StateError(
        'Administrator accounts are managed by an LGU administrator.',
      );
    }
    if (!state.connected || _connectedSession != session) return;
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) throw StateError('Administrator session expired.');
    final snapshot = await repository.loadAdminAccounts();
    if (_connectedSession == session) {
      state = state.copyWith(
        adminAccounts: snapshot.accounts,
        adminInvites: snapshot.invites,
        todaZoneOptions: snapshot.todaZoneOptions,
      );
    }
  }

  /// Real-data-only, matching reviewFareClassClaim/reviewDriverDocument
  /// above -- there is no seeded demo admin roster to mutate.
  Future<void> sendAdminInvite({
    required String email,
    required String scope,
    String? todaZoneId,
  }) async {
    if (!state.connected) {
      throw StateError(
        'Sending an admin invite requires the live Supabase connection.',
      );
    }
    await ref
        .read(adminRepositoryProvider)!
        .sendAdminInvite(email: email, scope: scope, todaZoneId: todaZoneId);
    final session = _connectedSession;
    if (session != null) await refreshAdminAccounts(session);
  }

  Future<void> revokeAdminInvite(String inviteId) async {
    if (!state.connected) {
      throw StateError(
        'Revoking an admin invite requires the live Supabase connection.',
      );
    }
    await ref.read(adminRepositoryProvider)!.revokeAdminInvite(inviteId);
    final session = _connectedSession;
    if (session != null) await refreshAdminAccounts(session);
  }

  /// Thin pass-throughs for the public accept-invite screen, which runs
  /// before any admin session exists -- no state to refresh, same
  /// rejected-Future-not-a-throw shape as driverDocumentPhotoUrl above.
  Future<String> lookupAdminInvite(String token) {
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) {
      return Future.error(
        StateError('This invite page requires the live Supabase connection.'),
      );
    }
    return repository.lookupAdminInvite(token);
  }

  Future<void> acceptAdminInvite({
    required String token,
    required String firstName,
    required String lastName,
    required String password,
  }) {
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) {
      return Future.error(
        StateError('This invite page requires the live Supabase connection.'),
      );
    }
    return repository.acceptAdminInvite(
      token: token,
      firstName: firstName,
      lastName: lastName,
      password: password,
    );
  }
}

AdminState seedAdminState() {
  final now = DateTime(2026, 8, 22, 10, 30);
  return AdminState(
    feedbackCounts: const {'Brgy. Real': 8, 'Parian': 7, 'Canlubang': 5},
    drivers: [
      Driver(
        id: '123',
        name: 'Ramon Dela Cruz',
        toda: 'Brgy. Real',
        phone: '0917 555 0123',
        plate: 'TRI-123',
        status: DriverStatus.approved,
        documents: 4,
        enrollmentCode: 'AC-2026-0123',
        updated: now.subtract(const Duration(hours: 2)),
      ),
      Driver(
        id: '124',
        name: 'Joel Mendoza',
        toda: 'Brgy. Real',
        phone: '0918 555 0124',
        plate: 'TRI-124',
        status: DriverStatus.review,
        documents: 3,
        enrollmentCode: 'AC-2026-0124',
        updated: now.subtract(const Duration(hours: 5)),
      ),
      Driver(
        id: '125',
        name: 'Mario Santos',
        toda: 'Parian',
        phone: '0919 555 0125',
        plate: 'TRI-125',
        status: DriverStatus.submitted,
        documents: 4,
        enrollmentCode: 'AC-2026-0125',
        updated: now.subtract(const Duration(days: 1)),
      ),
      Driver(
        id: '126',
        name: 'Benjie Reyes',
        toda: 'Canlubang',
        phone: '0920 555 0126',
        plate: 'TRI-126',
        status: DriverStatus.suspended,
        documents: 4,
        enrollmentCode: 'AC-2026-0126',
        updated: now.subtract(const Duration(days: 2)),
      ),
      Driver(
        id: '127',
        name: 'Arturo Lim',
        toda: 'Brgy. Real',
        phone: '0921 555 0127',
        plate: 'TRI-127',
        status: DriverStatus.rejected,
        documents: 2,
        enrollmentCode: 'AC-2026-0127',
        updated: now.subtract(const Duration(days: 4)),
      ),
    ],
    reports: [
      SafetyReport(
        id: 'SR-1042',
        rider: 'Ana Reyes',
        driver: 'Ramon Dela Cruz',
        toda: 'Brgy. Real',
        summary: 'Driver took an unexpected turn during the trip.',
        status: ReportStatus.newReport,
        created: now.subtract(const Duration(minutes: 18)),
        notes: const ['Report submitted through the active trip safety flow.'],
      ),
      SafetyReport(
        id: 'SR-1041',
        rider: 'Lea Garcia',
        driver: 'Mario Santos',
        toda: 'Parian',
        summary: 'Rider reported aggressive driving near the junction.',
        status: ReportStatus.investigating,
        created: now.subtract(const Duration(hours: 3)),
        notes: const [
          'Acknowledged by the LGU evaluator.',
          'Driver statement requested.',
        ],
      ),
      SafetyReport(
        id: 'SR-1038',
        rider: 'Paolo Cruz',
        driver: 'Joel Mendoza',
        toda: 'Brgy. Real',
        summary: 'Dispute about the recorded pickup point.',
        status: ReportStatus.resolved,
        created: now.subtract(const Duration(days: 1)),
        notes: const [
          'Trip data reviewed.',
          'Rider and TODA coordinator notified of resolution.',
        ],
      ),
    ],
    complaints: [
      Complaint(
        id: 'CPL-2091',
        tripId: 'R-2208',
        complainantName: 'Ana Reyes',
        complainantRole: 'commuter',
        respondentName: 'Ramon Dela Cruz',
        toda: 'Brgy. Real',
        category: 'driver_late',
        description: 'Waited about 20 minutes past the confirmed pickup time.',
        status: ReportStatus.newReport,
        created: now.subtract(const Duration(hours: 1)),
        notes: const [],
      ),
      Complaint(
        id: 'CPL-2088',
        tripId: 'R-2205',
        complainantName: 'Joel Mendoza',
        complainantRole: 'driver',
        respondentName: 'Mika Flores',
        toda: 'Brgy. Real',
        category: 'disputed_fare',
        description: 'Passenger disputed the fare shown on the app after arrival.',
        status: ReportStatus.resolved,
        created: now.subtract(const Duration(days: 2)),
        notes: const ['Fare confirmed correct against the published matrix.'],
      ),
    ],
    ratings: [
      TripRating(
        id: 'RTG-3301',
        tripId: 'R-2208',
        raterName: 'Ana Reyes',
        raterRole: 'commuter',
        rateeName: 'Ramon Dela Cruz',
        toda: 'Brgy. Real',
        stars: 4,
        comment: 'Safe ride, a bit late to pick up.',
        created: now.subtract(const Duration(hours: 1)),
      ),
      TripRating(
        id: 'RTG-3298',
        tripId: 'R-2205',
        raterName: 'Joel Mendoza',
        raterRole: 'driver',
        rateeName: 'Mika Flores',
        toda: 'Brgy. Real',
        stars: 5,
        comment: null,
        created: now.subtract(const Duration(days: 2)),
      ),
    ],
    rides: const [
      Ride(
        id: 'R-2208',
        driver: 'Ramon Dela Cruz',
        rider: 'Ana Reyes',
        toda: 'Brgy. Real',
        status: 'En route',
        latitude: 14.2119,
        longitude: 121.1654,
        updatedMinutes: 1,
      ),
      Ride(
        id: 'R-2207',
        driver: 'Joel Mendoza',
        rider: 'Mika Flores',
        toda: 'Brgy. Real',
        status: 'Arriving',
        latitude: 14.2088,
        longitude: 121.1701,
        updatedMinutes: 2,
      ),
      Ride(
        id: 'R-2206',
        driver: 'Mario Santos',
        rider: 'Lea Garcia',
        toda: 'Parian',
        status: 'On trip',
        latitude: 14.2021,
        longitude: 121.1592,
        updatedMinutes: 1,
      ),
    ],
    // Categorical, not brand-decorative: these three overlays sit on top of
    // each other on the same map, so they are spread across hue *and*
    // lightness rather than being three steps of one blue ramp. The home
    // TODA keeps the brand blue; the other two take a teal and a violet far
    // enough away to stay separable.
    boundaries: const [
      Boundary('Brgy. Real', 0xFF1262D0, [
        [121.1570, 14.2060],
        [121.1690, 14.2060],
        [121.1690, 14.2160],
        [121.1570, 14.2160],
        [121.1570, 14.2060],
      ]),
      Boundary('Parian', 0xFF0E9384, [
        [121.1510, 14.1970],
        [121.1630, 14.1970],
        [121.1630, 14.2070],
        [121.1510, 14.2070],
        [121.1510, 14.1970],
      ]),
      Boundary('Canlubang', 0xFF9A4FBF, [
        [121.1640, 14.1960],
        [121.1760, 14.1960],
        [121.1760, 14.2060],
        [121.1640, 14.2060],
        [121.1640, 14.1960],
      ]),
    ],
    audit: [
      AuditEvent(
        'Safety report acknowledged',
        'SR-1041 · LGU evaluator',
        now.subtract(const Duration(hours: 2)),
        toda: 'Parian',
      ),
      AuditEvent(
        'Driver sent for review',
        'Joel Mendoza · Brgy. Real',
        now.subtract(const Duration(hours: 5)),
        toda: 'Brgy. Real',
      ),
      AuditEvent(
        'Driver suspended',
        'Benjie Reyes · document review',
        now.subtract(const Duration(days: 2)),
        toda: 'Canlubang',
      ),
    ],
  );
}
