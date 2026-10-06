import 'captcha_stub.dart' if (dart.library.js_interop) 'captcha_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String? captchaFailureMessage(Object error) =>
    error is AuthException && error.code == 'captcha_failed'
    ? 'The security check did not finish. Please try again.'
    : null;

/// The Turnstile widget that Supabase Auth checks tokens against. Empty in a
/// build made without one, and then no token is asked for.
const turnstileSiteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');

/// A fresh token, or null only when this build has no configured check.
Future<String?> captchaToken() async {
  if (turnstileSiteKey.isEmpty) return null;
  final token = await turnstileToken(turnstileSiteKey);
  if (token == null || token.isEmpty) {
    throw const AuthException(
      'Security check incomplete',
      code: 'captcha_failed',
    );
  }
  return token;
}
