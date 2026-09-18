import 'dart:typed_data';

class DriverDocument {
  const DriverDocument({
    required this.id,
    required this.type,
    required this.status,
    this.rejectionReason,
  });

  final String id;
  final String type;
  final String status;
  final String? rejectionReason;

  static const labels = {
    'drivers_license': 'Driver’s licence',
    'mtop_franchise': 'MTOP / franchise permit',
    'toda_membership': 'TODA membership endorsement',
    'or_cr': 'Vehicle OR / CR registration',
    'barangay_clearance': 'Barangay clearance (optional)',
    'vehicle_photo': 'Vehicle photo (optional)',
  };
  String get label => labels[type] ?? 'Driver document';
}

class DriverRecords {
  const DriverRecords({
    required this.status,
    required this.documents,
    this.toda,
    this.bodyNumber,
    this.plateNumber,
    this.licenceExpiresOn,
    this.rejectionReason,
  });

  final String status;
  final String? toda;
  final String? bodyNumber;
  final String? plateNumber;
  final String? licenceExpiresOn;
  final String? rejectionReason;
  final List<DriverDocument> documents;
}

abstract class DriverDocumentsRepository {
  Future<DriverRecords?> load();

  /// Return image bytes only; paths and signed URLs stay inside the transport.
  Future<Uint8List> loadDocument(String documentId);
}
