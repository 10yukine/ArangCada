import 'package:flutter/foundation.dart';

import 'models.dart';

final auth = ValueNotifier<AdminSession?>(null);

/// True while a persisted administrator session from local storage is being
/// verified and connected with Supabase. Route guards must not redirect to
/// /login while this is true so deep links and reloaded URLs are preserved.
final authRestoring = ValueNotifier<bool>(false);

/// Optional error message from a failed session restoration (e.g. expired
/// session) to display on the login screen.
final authError = ValueNotifier<String?>(null);
