import 'package:supabase_flutter/supabase_flutter.dart';

/// Redeems the one deep link this app accepts: the password-reset link it
/// asked for (see SupabaseAuthRepository.sendPasswordReset).
///
/// supabase_flutter's own link observer is switched off in main.dart because
/// it also takes an `access_token`/`refresh_token` pair from any link and
/// silently replaces the signed-in session with it. Any web page or app on the
/// phone could open such a link and sign this app into somebody else's
/// account. A `code` is different: the server only exchanges it together with
/// the verifier this phone stored when it requested the reset, so a link made
/// anywhere else is refused.
Future<void> redeemResetLink(Uri uri, GoTrueClient auth) async {
  if (uri.scheme != 'ph.calamba.arangcada' || uri.host != 'reset-password') {
    return;
  }
  final code = uri.queryParameters['code'];
  if (code == null) return;
  try {
    await auth.exchangeCodeForSession(code);
  } on AuthException {
    // Expired, already used, or not requested from this phone.
  }
}
