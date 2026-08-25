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
  const AdminSession({required this.name, required this.role, this.toda});
  final String name;
  final AdminRole role;
  final String? toda;

  String get scope =>
      role == AdminRole.lgu ? 'LGU · All TODAs' : 'TODA · $toda';
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
  });

  final int id;
  final String name;
  final String toda;
  final String phone;
  final String plate;
  final DriverStatus status;
  final int documents;
  final String enrollmentCode;
  final DateTime updated;

  Driver copyWith({DriverStatus? status, DateTime? updated}) => Driver(
    id: id,
    name: name,
    toda: toda,
    phone: phone,
    plate: plate,
    status: status ?? this.status,
    documents: documents,
    enrollmentCode: enrollmentCode,
    updated: updated ?? this.updated,
  );
}

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
  });

  final String id;
  final String rider;
  final String driver;
  final String toda;
  final String summary;
  final ReportStatus status;
  final DateTime created;
  final List<String> notes;

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
      );
}

class Ride {
  const Ride({
    required this.id,
    required this.driver,
    required this.rider,
    required this.toda,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.updatedMinutes,
  });

  final String id;
  final String driver;
  final String rider;
  final String toda;
  final String status;
  final double latitude;
  final double longitude;
  final int updatedMinutes;
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
    required this.surveyCounts,
    this.driverQuery = '',
    this.driverStatus = 'All statuses',
    this.driverToda = 'All TODAs',
    this.compactDensity = false,
    this.desktopAlerts = true,
    this.selectedRide,
  });

  final List<Driver> drivers;
  final List<SafetyReport> reports;
  final List<Ride> rides;
  final List<Boundary> boundaries;
  final List<AuditEvent> audit;
  final Map<String, int> surveyCounts;
  final String driverQuery;
  final String driverStatus;
  final String driverToda;
  final bool compactDensity;
  final bool desktopAlerts;
  final String? selectedRide;

  AdminState copyWith({
    List<Driver>? drivers,
    List<SafetyReport>? reports,
    List<Ride>? rides,
    List<AuditEvent>? audit,
    Map<String, int>? surveyCounts,
    String? driverQuery,
    String? driverStatus,
    String? driverToda,
    bool? compactDensity,
    bool? desktopAlerts,
    String? selectedRide,
    bool clearSelectedRide = false,
  }) => AdminState(
    drivers: drivers ?? this.drivers,
    reports: reports ?? this.reports,
    rides: rides ?? this.rides,
    boundaries: boundaries,
    audit: audit ?? this.audit,
    surveyCounts: surveyCounts ?? this.surveyCounts,
    driverQuery: driverQuery ?? this.driverQuery,
    driverStatus: driverStatus ?? this.driverStatus,
    driverToda: driverToda ?? this.driverToda,
    compactDensity: compactDensity ?? this.compactDensity,
    desktopAlerts: desktopAlerts ?? this.desktopAlerts,
    selectedRide: clearSelectedRide ? null : selectedRide ?? this.selectedRide,
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
