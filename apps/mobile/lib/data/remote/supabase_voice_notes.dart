import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Transport only: signed URLs and microphone bytes never enter persisted state.
class SupabaseVoiceNotes {
  SupabaseVoiceNotes(this.client);
  final SupabaseClient client;
  static const bucket = 'trip-voice-notes';
  static const maxBytes = 1048576;

  Future<Map<String, dynamic>> send({
    required String tripId,
    required String messageId,
    required Uint8List bytes,
    required int durationMs,
  }) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to send a voice note.');
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        durationMs < 1 ||
        durationMs > 60000) {
      throw StateError('Voice notes must be at most 60 seconds and 1 MB.');
    }
    final path = '$tripId/$userId/$messageId.m4a';
    // A fixed message ID makes both upload retries and a lost RPC response safe.
    try {
      await client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'audio/mp4',
              upsert: false,
            ),
          )
          .timeout(const Duration(seconds: 30));
    } on StorageException catch (error) {
      if (error.error != 'Duplicate' && error.statusCode != '409') rethrow;
    }
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Account changed.');
    }
    final result = await client
        .rpc(
          'send_trip_voice_message',
          params: {
            'p_trip_id': tripId,
            'p_message_id': messageId,
            'p_duration_ms': durationMs,
          },
        )
        .timeout(const Duration(seconds: 30));
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Account changed.');
    }
    return Map<String, dynamic>.from(
      result is List ? result.single as Map : result as Map,
    );
  }

  Future<String> playbackUrl(String messageId) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in to listen.');
    // Recheck row visibility on every play; never trust a caller-supplied path.
    final row = await client
        .from('trip_messages')
        .select('voice_path')
        .eq('id', messageId)
        .single()
        .timeout(const Duration(seconds: 15));
    final path = row['voice_path'] as String?;
    if (path == null) throw StateError('Voice note unavailable.');
    final url = await client.storage
        .from(bucket)
        .createSignedUrl(path, 60)
        .timeout(const Duration(seconds: 15));
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Account changed.');
    }
    return url;
  }
}
