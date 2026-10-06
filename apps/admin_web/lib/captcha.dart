import 'captcha_stub.dart' if (dart.library.js_interop) 'captcha_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String? captchaFailureMessage(Object error) =>
    error is AuthException && error.code == 'captcha_failed'
    ? 'The security check did not finish. Please try again.'
    : null;

/// The Turnstile widget that Supabase Auth checks tokens against. Empty in a
/// build made without one, and then no token is asked for.
const turnstileSiteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');

/// A fresh, single-use token for one sign-in or reset request, or null when no
/// site key is built in or the check could not be completed.
///
/// A missing token is not an error here. Auth decides what it means: nothing
/// while CAPTCHA is off, a refusal once it is on.
Future<String?> captchaToken() => turnstileToken(turnstileSiteKey);
