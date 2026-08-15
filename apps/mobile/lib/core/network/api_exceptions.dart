/// Typed failures for the live API layer.
///
/// Screens react to the *kind* of failure, never to a raw HTTP code or an SDK
/// exception. Nothing here may carry an API key, an Authorization header, or a
/// raw provider error body, because those get logged.
library;

sealed class ApiException implements Exception {
  const ApiException(this.message);

  /// Safe to show to a user. Never contains credentials or provider internals.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// No usable connection, DNS failure, or the request timed out.
class ApiNetworkException extends ApiException {
  const ApiNetworkException([
    super.message = 'No connection. Check your network and try again.',
  ]);
}

/// HTTP 429. openrouteservice enforces a per-minute request limit; HeiGIT
/// explicitly asks that clients not retry into it. Callers must serve cached
/// data and back off rather than loop.
class ApiRateLimitedException extends ApiException {
  const ApiRateLimitedException([
    super.message = 'Routing is busy right now. Showing the last known route.',
  ]);

  /// How long to refuse further automatic attempts.
  Duration get cooldown => const Duration(minutes: 1);
}

/// HTTP 403. On openrouteservice this means the authorization is not valid for
/// this request or the daily allowance is spent. Either way, retrying is
/// pointless and abusive, so the caller stops for the rest of the session.
class ApiQuotaException extends ApiException {
  const ApiQuotaException([
    super.message = 'Routing is unavailable right now.',
  ]);
}

/// HTTP 401 or a rejected key.
class ApiUnauthorizedException extends ApiException {
  const ApiUnauthorizedException([
    super.message = 'Routing is unavailable right now.',
  ]);
}

/// Anything else the provider returned, or a malformed body.
class ApiUnexpectedException extends ApiException {
  const ApiUnexpectedException([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// The feature is not configured in this build (missing compile-time key).
class ApiNotConfiguredException extends ApiException {
  const ApiNotConfiguredException([
    super.message = 'This feature is not configured in this build.',
  ]);
}
