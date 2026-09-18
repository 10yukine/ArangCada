import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/driver_documents_repository.dart';

class SupabaseDriverDocumentsRepository implements DriverDocumentsRepository {
  SupabaseDriverDocumentsRepository(this._client, this._http);

  final SupabaseClient _client;
  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  String _userId() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Sign in again to view your records.');
    return id;
  }

  void _checkSession(String id) {
    if (_userId() != id) throw StateError('The account has changed.');
  }

  @override
  Future<DriverRecords?> load() async {
    final id = _userId();
    final results = await Future.wait<dynamic>([
      _client
          .from('driver_profiles')
          .select(
            'body_number, plate_number, license_expires_on, verification_status, '
            'rejection_reason, toda_zones(name)',
          )
          .eq('id', id)
          .maybeSingle(),
      _client.from('profiles').select('status').eq('id', id).single(),
      _client
          .from('driver_documents')
          .select('id, document_type, status, rejection_reason')
          .eq('driver_id', id)
          .order('created_at'),
    ]).timeout(_timeout);
    _checkSession(id);
    final profile = results[0] as Map<String, dynamic>?;
    if (profile == null) return null;
    return DriverRecords(
      status: results[1]['status'] == 'suspended'
          ? 'suspended'
          : profile['verification_status'] as String,
      toda: (profile['toda_zones'] as Map?)?['name'] as String?,
      bodyNumber: profile['body_number'] as String?,
      plateNumber: profile['plate_number'] as String?,
      licenceExpiresOn: profile['license_expires_on'] as String?,
      rejectionReason: profile['rejection_reason'] as String?,
      documents: [
        for (final row in results[2] as List)
          DriverDocument(
            id: row['id'] as String,
            type: row['document_type'] as String,
            status: row['status'] as String,
            rejectionReason: row['rejection_reason'] as String?,
          ),
      ],
    );
  }

  @override
  Future<Uint8List> loadDocument(String documentId) async {
    final id = _userId();
    // Re-read the path on every open/retry, including after admin replacement.
    final row = await _client
        .from('driver_documents')
        .select('storage_path')
        .eq('id', documentId)
        .eq('driver_id', id)
        .single()
        .timeout(_timeout);
    _checkSession(id);
    final path = row['storage_path'] as String;
    if (!path.startsWith('$id/') || path.split('/').contains('..')) {
      throw StateError('This document is unavailable.');
    }
    final url = await _client.storage
        .from('driver-documents')
        .createSignedUrl(path, 300)
        .timeout(_timeout);
    _checkSession(id);
    final response = await _http.get(Uri.parse(url)).timeout(_timeout);
    _checkSession(id);
    if (response.statusCode != 200) {
      throw StateError('This document could not be downloaded.');
    }
    return response.bodyBytes;
  }
}
