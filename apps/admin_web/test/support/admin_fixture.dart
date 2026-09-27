import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/models.dart';

/// Sample records for widget and controller tests. Production starts from
/// emptyAdminState and only ever shows live Supabase data.
AdminState testAdminState() {
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
        description:
            'Passenger disputed the fare shown on the app after arrival.',
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

/// A controller that starts from [testAdminState] instead of the empty
/// production state.
class FixtureAdminController extends AdminController {
  @override
  AdminState build() => testAdminState();
}

/// Overrides for a ProviderScope whose console should show the sample data.
final fixtureOverrides = [adminProvider.overrideWith(FixtureAdminController.new)];
