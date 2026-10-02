import 'package:http/http.dart';
import 'package:http/retry.dart';

/// The HTTP client handed to Supabase.
///
/// The hosted API (PostgREST 14.5) caches its clock. On the first request after
/// it has been idle it can refuse a valid token as "JWT issued at future" (401,
/// PGRST303; fixed upstream in 14.18). The request was not run, so it is safe
/// to send again, and a moment later the same token is accepted.
Client staleClockRetryClient([Client? inner]) => RetryClient(
  inner ?? Client(),
  retries: 1,
  when: (response) =>
      response.statusCode == 401 &&
      (response.request?.url.path.startsWith('/rest/v1/') ?? false),
);
