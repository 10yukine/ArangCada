import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/auth_captcha.dart';
import 'app/mobile_settings.dart';
import 'app/router.dart';
import 'config/app_config.dart';
import 'data/providers/repository_providers.dart';
import 'data/remote/push/push_notification_service.dart';
import 'data/remote/reset_link.dart';
import 'data/repositories/saved_places_repository.dart';
import 'data/remote/stale_clock_retry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Make system bars transparent so the app draws edge-to-edge.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );

  // Hybrid composition is the plugin default, but setting it explicitly makes
  // the Android side send textureMode(true) with the view creation params
  // rather than relying on detection order.
  MapLibreMap.useHybridComposition = true;

  await Hive.initFlutter();
  final storage = await Hive.openBox<String>('arangcada_demo');
  await SavedPlacesRepository.purgeGoogleContent(storage);
  // Real notification history, not the fixed mock list
  // notifications_screen.dart used to render. Opened here, before
  // bootstrap(), so it exists regardless of whether push itself is
  // supported on this platform/build.
  await Hive.openBox<String>(PushNotificationService.notificationsBoxName);

  // FCM push transport only -- Supabase stays the backend for every
  // business decision. Safe to call even without google-services.json;
  // every step inside is individually guarded.
  await PushNotificationService.bootstrap();

  if (AppConfig.isSupabaseConfigured) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
        // The SDK's own observer signs the app into whatever access_token a
        // link carries. Only the reset link is redeemed; see redeemResetLink.
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: staleClockRetryClient(),
      );
      final client = Supabase.instance.client;
      unawaited(loadMobileSettings(client));
      // Kept for the life of the process: asks again each time the app comes
      // back to the foreground, so a switch reaches a phone left running.
      AppLifecycleListener(
        onResume: () => unawaited(loadMobileSettings(client)),
      );
      client.auth.onAuthStateChange.listen((data) {
        switch (data.event) {
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.initialSession:
            if (data.session != null) {
              unawaited(PushNotificationService.registerForSession(client));
            }
          case AuthChangeEvent.passwordRecovery:
            // The reset email's link came back into the app (see
            // SupabaseAuthRepository.sendPasswordReset).
            passwordRecoveryPending.value = true;
          case AuthChangeEvent.signedOut:
            unawaited(PushNotificationService.unregisterForSession(client));
          default:
            break;
        }
      });
      // The link the app was opened with arrives on this stream too.
      AppLinks().uriLinkStream.listen(
        (uri) => unawaited(redeemResetLink(uri, client.auth)),
        onError: (_) {},
      );
    } catch (_) {
      // Never interpolate an SDK error: rejected configuration can be echoed
      // by exception messages. Hidden local test accounts remain available.
      debugPrint(
        'Supabase initialization unavailable; remote sign-in is disabled.',
      );
    }
  }

  runApp(
    ProviderScope(
      overrides: [authCaptchaProvider.overrideWithValue(authCaptchaToken)],
      child: const ArangCadaApp(),
    ),
  );
}
