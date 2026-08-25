import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

final adminProvider = NotifierProvider<AdminController, AdminState>(
  AdminController.new,
);

class AdminController extends Notifier<AdminState> {
  @override
  AdminState build() => seedAdminState();

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

  void recordSurveyResponse(AdminSession session, String toda) {
    if (session.role == AdminRole.toda && session.toda != toda) {
      throw StateError('Survey responses must stay within the assigned TODA.');
    }
    final count = state.surveyCounts[toda];
    if (count == null) throw ArgumentError.value(toda, 'toda', 'Unknown TODA');
    state = state.copyWith(
      surveyCounts: {...state.surveyCounts, toda: count + 1},
      audit: [
        AuditEvent(
          'Survey response recorded',
          '$toda · eligible respondent',
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
    final id =
        state.drivers.fold<int>(
          0,
          (max, item) => item.id > max ? item.id : max,
        ) +
        1;
    final driver = Driver(
      id: id,
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

  void updateDriver(int id, DriverStatus status, String reason) {
    final current = state.drivers.firstWhere((driver) => driver.id == id);
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

  void transitionReport(String id, ReportStatus status, String note) {
    final current = state.reports.firstWhere((report) => report.id == id);
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
}

AdminState seedAdminState() {
  final now = DateTime(2026, 8, 22, 10, 30);
  return AdminState(
    surveyCounts: const {'Brgy. Real': 8, 'Parian': 7, 'Canlubang': 5},
    drivers: [
      Driver(
        id: 123,
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
        id: 124,
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
        id: 125,
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
        id: 126,
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
        id: 127,
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
    boundaries: const [
      Boundary('Brgy. Real', 0xFFB4552F, [
        [121.1570, 14.2060],
        [121.1690, 14.2060],
        [121.1690, 14.2160],
        [121.1570, 14.2160],
        [121.1570, 14.2060],
      ]),
      Boundary('Parian', 0xFF56876D, [
        [121.1510, 14.1970],
        [121.1630, 14.1970],
        [121.1630, 14.2070],
        [121.1510, 14.2070],
        [121.1510, 14.1970],
      ]),
      Boundary('Canlubang', 0xFF8573B3, [
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
