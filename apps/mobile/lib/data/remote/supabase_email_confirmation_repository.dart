import 'package:supabase_flutter/supabase_flutter.dart';

import '../mock/demo_state.dart';
import '../repositories/auth_repository.dart';
import '../repositories/email_confirmation_repository.dart';

/// Asks the `send-email-confirmation` Edge Function for the link and reads
/// `profiles.email_confirmed_at` back. The app never sees the link's token:
/// only opening the email can confirm the address.
class SupabaseEmailConfirmationRepository
    implements EmailConfirmationRepository {
  SupabaseEmailConfirmationRepository(this._client, this._state);

  final SupabaseClient _client;
  final DemoState _state;

  static const _unavailable =
      'Could not send the confirmation email. Try again later.';

  @override
  Future<void> send() async {
    try {
      await _client.functions.invoke('send-email-confirmation');
    } on FunctionException catch (error) {
      // 429 carries the server's own sentence: wait a minute, the day's limit,
      // or that the email is already confirmed.
      final details = error.details;
      final message = details is Map ? details['error'] : null;
      throw error.status == 429 && message is String && message.isNotEmpty
          ? EmailConfirmationWait(message)
          : const DemoAuthException(_unavailable);
    } catch (_) {
      throw const DemoAuthException(_unavailable);
    }
  }

  @override
  Future<void> refresh() async {
    final user = _state.currentUser;
    final id = _client.auth.currentUser?.id;
    if (user == null || id == null || user.emailConfirmed) return;
    try {
      final row = await _client
          .from('profiles')
          .select('email_confirmed_at')
          .eq('id', id)
          .maybeSingle();
      final current = _state.currentUser;
      // Only for the account and address that were asked about.
      if (row?['email_confirmed_at'] != null &&
          _client.auth.currentUser?.id == id &&
          current != null &&
          current.email == user.email) {
        _state.setCurrentUser(current.copyWithEmailConfirmed(true));
      }
    } catch (_) {
      // The prompt stays; it asks again the next time the app is opened.
    }
  }
}
