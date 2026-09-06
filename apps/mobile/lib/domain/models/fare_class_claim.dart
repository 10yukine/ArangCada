/// The Student/Senior Citizen/PWD discount a commuter is claiming.
///
/// Distinct from [UserFareClass] in `booking.dart`: that enum drives the
/// local demo fare-preview UI, while this one is the wire vocabulary
/// `submit_fare_class_claim`'s `p_class` parameter and
/// `fare_class_claims.requested_class` actually accept. See
/// `.pipeline/specs.md` Spec 14.
enum FareClassRequestedClass { student, seniorCitizen, pwd }

extension FareClassRequestedClassWire on FareClassRequestedClass {
  String get wireValue => switch (this) {
    FareClassRequestedClass.student => 'student',
    FareClassRequestedClass.seniorCitizen => 'senior_citizen',
    FareClassRequestedClass.pwd => 'pwd',
  };

  String get label => switch (this) {
    FareClassRequestedClass.student => 'Student',
    FareClassRequestedClass.seniorCitizen => 'Senior Citizen',
    FareClassRequestedClass.pwd => 'PWD',
  };

  static FareClassRequestedClass fromWire(String value) => switch (value) {
    'student' => FareClassRequestedClass.student,
    'senior_citizen' => FareClassRequestedClass.seniorCitizen,
    'pwd' => FareClassRequestedClass.pwd,
    _ => throw ArgumentError('Unrecognised fare class: $value'),
  };
}

enum FareClassClaimStatus { pendingReview, approved, rejected }

extension FareClassClaimStatusWire on FareClassClaimStatus {
  static FareClassClaimStatus fromWire(String value) => switch (value) {
    'pending_review' => FareClassClaimStatus.pendingReview,
    'approved' => FareClassClaimStatus.approved,
    'rejected' => FareClassClaimStatus.rejected,
    _ => throw ArgumentError('Unrecognised claim status: $value'),
  };
}

/// A commuter's discount-eligibility claim, as reviewed by
/// `review_fare_class_claim()` -- never client-writable beyond the initial
/// `submit_fare_class_claim()` call.
class FareClassClaim {
  const FareClassClaim({
    required this.id,
    required this.requestedClass,
    required this.status,
    required this.createdAt,
    this.rejectionReason,
  });

  factory FareClassClaim.fromRow(Map<String, dynamic> row) => FareClassClaim(
    id: row['id'] as String,
    requestedClass: FareClassRequestedClassWire.fromWire(
      row['requested_class'] as String,
    ),
    status: FareClassClaimStatusWire.fromWire(row['status'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
    rejectionReason: row['rejection_reason'] as String?,
  );

  final String id;
  final FareClassRequestedClass requestedClass;
  final FareClassClaimStatus status;
  final DateTime createdAt;
  final String? rejectionReason;
}
