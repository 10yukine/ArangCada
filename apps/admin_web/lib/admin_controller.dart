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
  AdminState build() => emptyAdminState;

  /// The live repository for a write, or a clear error when there is no
  /// signed-in, connected administrator session to act with.
  SupabaseAdminRepository _live(String action) {
    final repository = ref.read(adminRepositoryProvider);
    if (!state.connected || repository == null) {
      throw StateError('$action requires a signed-in administrator session.');
    }
    return repository;
  }

  Future<void> connect(AdminSession session) async {
    if (!session.connected) {
      throw StateError('Only a signed-in administrator session can connect.');
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
          onDataChanged: () {
            unawaited(refresh());
            // driver_invites is LGU-only and not part of refresh()'s main
            // snapshot (see refreshDriverInvites()'s own header comment) --
            // needs its own call so the pending-invites panel live-updates
            // too, matching the fix for state.drivers/fareClassClaims above.
            if (session.role == AdminRole.lgu) {
              unawaited(refreshDriverInvites());
            }
          },
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
        // Bug found by the owner, 9 Sep 2026: a real discount claim never
        // appeared on the Claims screen even after a page reload.
        // fareClassClaims was fetched into every AdminSnapshot from the
        // start, but never actually wired into state here -- ClaimsScreen
        // read state.fareClassClaims forever, which stayed at its
        // empty default.
        fareClassClaims: snapshot.fareClassClaims,
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
    state = emptyAdminState;
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

  /// Uploads a new profile photo and returns the freshly resolved session
  /// (new avatarUrl included) -- the caller sets auth.value from it, same
  /// pattern sign-in/session-restore already use, since AdminSession lives
  /// outside this controller's own AdminState.
  Future<AdminSession> changeProfilePhoto({
    required List<int> bytes,
    required String fileExtension,
  }) async {
    final repository = ref.read(adminRepositoryProvider);
    final session = _connectedSession;
    if (session == null || !session.connected || repository == null) {
      throw StateError('Photo changes require a connected account.');
    }
    final path = await repository.uploadProfilePhoto(
      bytes: bytes,
      fileExtension: fileExtension,
    );
    return repository.updateAvatarPath(path);
  }

  void resetViewFilters() => state = state.copyWith(
    driverQuery: '',
    driverStatus: 'All statuses',
    driverToda: 'All TODAs',
    clearSelectedRide: true,
  );

  Future<void> updateDriver(
    String id,
    DriverStatus status,
    String reason,
  ) async {
    final current = state.drivers.firstWhere((driver) => driver.id == id);
    final repository = _live('Updating a driver');
    final session = _connectedSession;
    if (session == null) throw StateError('Administrator session expired.');
    await repository.updateDriver(
      driver: current,
      status: status,
      reason: reason,
      session: session,
    );
    await refresh();
  }

  Future<void> updateDriverName({
    required String driverId,
    required String firstName,
    required String lastName,
    String? reason,
  }) async {
    final first = firstName.trim();
    final last = lastName.trim();
    if (first.isEmpty || last.isEmpty) {
      throw ArgumentError('First and last name are required.');
    }
    await _live('Renaming a driver').updateDriverName(
      driverId: driverId,
      firstName: first,
      lastName: last,
      reason: reason,
    );
    await refresh();
  }

  Future<void> updateDriverRecord({
    required String driverId,
    required String firstName,
    required String lastName,
    required String plateNumber,
    required String bodyNumber,
    String? todaZoneId,
    DateTime? licenseExpiresOn,
    bool clearLicenseExpiry = false,
  }) async {
    final first = firstName.trim();
    final last = lastName.trim();
    if (first.isEmpty || last.isEmpty) {
      throw ArgumentError('First and last name are required.');
    }
    final current = state.drivers.firstWhere((driver) => driver.id == driverId);
    final zoneId = todaZoneId ?? current.todaZoneId;
    final repository = _live('Updating a driver record');
    if (zoneId == null) throw StateError('Choose an active TODA.');
    await repository.updateDriverRecord(
      driverId: driverId,
      firstName: first,
      lastName: last,
      plateNumber: plateNumber,
      bodyNumber: bodyNumber,
      todaZoneId: zoneId,
      licenseExpiresOn: clearLicenseExpiry ? null : licenseExpiresOn,
    );
    await refresh();
  }

  Future<void> transitionReport(
    String id,
    ReportStatus status,
    String note,
  ) async {
    final repository = _live('Updating a safety report');
    final session = _connectedSession;
    if (session == null) throw StateError('Administrator session expired.');
    await repository.updateSafetyReport(
      reportId: id,
      status: status,
      note: note,
      session: session,
    );
    await refresh();
  }

  Future<void> transitionComplaint(
    String id,
    ReportStatus status,
    String note,
  ) async {
    await _live('Updating a complaint').updateComplaint(
      complaintId: id,
      status: status,
      note: note,
    );
    await refresh();
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
        StateError(
          'Viewing a claim photo requires the live Supabase connection.',
        ),
      );
    }
    return repository.fareClassClaimPhotoUrl(path);
  }

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
        StateError(
          'Viewing a driver document requires the live Supabase connection.',
        ),
      );
    }
    return repository.driverDocumentPhotoUrl(path);
  }

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
    await _live('Changing feedback settings').updateFeedbackSettings(
      feedbackInterval: feedbackInterval,
      respondentTarget: target,
      repeatFeedback: repeat,
    );
    await refresh();
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

  /// Existing-account candidates for an email, for the enroll-driver
  /// dialog's first step.
  Future<List<DriverCandidate>> previewDriverCandidate(String email) async {
    if (!state.connected) {
      throw StateError(
        'Looking up an existing account requires the live Supabase connection.',
      );
    }
    return ref.read(adminRepositoryProvider)!.previewDriverCandidate(email);
  }

  Future<void> promoteCommuterToDriver({
    required String email,
    required String confirmValue,
    required String todaZoneId,
    String? bodyNumber,
    String? reason,
  }) async {
    if (!state.connected) {
      throw StateError(
        'Promoting a driver requires the live Supabase connection.',
      );
    }
    await ref
        .read(adminRepositoryProvider)!
        .promoteCommuterToDriver(
          email: email,
          confirmValue: confirmValue,
          todaZoneId: todaZoneId,
          bodyNumber: bodyNumber,
          reason: reason,
        );
    await refresh();
  }

  Future<void> sendDriverInvite({
    required String email,
    required String todaZoneId,
    String? bodyNumber,
  }) async {
    if (!state.connected) {
      throw StateError(
        'Sending a driver invite requires the live Supabase connection.',
      );
    }
    await ref
        .read(adminRepositoryProvider)!
        .sendDriverInvite(
          email: email,
          todaZoneId: todaZoneId,
          bodyNumber: bodyNumber,
        );
    final session = _connectedSession;
    if (session != null) await refreshDriverInvites();
  }

  Future<void> revokeDriverInvite(String inviteId) async {
    if (!state.connected) {
      throw StateError(
        'Revoking a driver invite requires the live Supabase connection.',
      );
    }
    await ref.read(adminRepositoryProvider)!.revokeDriverInvite(inviteId);
    await refreshDriverInvites();
  }

  /// LGU-only, loaded on demand by DriversScreen -- not part of the main
  /// refresh() snapshot, same reasoning refreshAdminAccounts (Spec 19)
  /// establishes for its own LGU-only, low-frequency data.
  Future<void> refreshDriverInvites() async {
    if (!state.connected) return;
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) throw StateError('Administrator session expired.');
    final result = await repository.loadDriverInvites();
    state = state.copyWith(
      driverInvites: result.invites,
      todaZoneOptions: result.zones,
    );
  }

  /// Thin pass-throughs for the public accept-driver-invite screen, which
  /// runs before any admin session exists -- no state to refresh, same
  /// rejected-Future-not-a-throw shape lookupAdminInvite (Spec 19) uses.
  Future<({String email, String todaZoneName})> lookupDriverInvite(
    String token,
  ) {
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) {
      return Future.error(
        StateError('This invite page requires the live Supabase connection.'),
      );
    }
    return repository.lookupDriverInvite(token);
  }

  Future<void> acceptDriverInvite({
    required String token,
    required String displayName,
    required String mobileNumber,
    required String password,
  }) {
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null) {
      return Future.error(
        StateError('This invite page requires the live Supabase connection.'),
      );
    }
    return repository.acceptDriverInvite(
      token: token,
      displayName: displayName,
      mobileNumber: mobileNumber,
      password: password,
    );
  }
}

/// Before sign-in and after sign-out there are no records at all -- the
/// console only ever shows live Supabase data.
const emptyAdminState = AdminState(
  drivers: [],
  reports: [],
  rides: [],
  boundaries: [],
  audit: [],
  feedbackCounts: {},
);
