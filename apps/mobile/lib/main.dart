import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'config/app_config.dart';
import 'data/remote/push/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hybrid composition is the plugin default, but setting it explicitly makes
  // the Android side send textureMode(true) with the view creation params
  // rather than relying on detection order.
  MapLibreMap.useHybridComposition = true;

  await Hive.initFlutter();
  await Hive.openBox<String>('arangcada_demo');

  // FCM push transport only -- Supabase stays the backend for every
  // business decision. Safe to call even without google-services.json;
  // every step inside is individually guarded.
  await PushNotificationService.bootstrap();

  if (AppConfig.isSupabaseConfigured) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
      final client = Supabase.instance.client;
      client.auth.onAuthStateChange.listen((data) {
        switch (data.event) {
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.initialSession:
            if (data.session != null) {
              unawaited(PushNotificationService.registerForSession(client));
            }
          case AuthChangeEvent.signedOut:
            unawaited(PushNotificationService.unregisterForSession(client));
          default:
            break;
        }
      });
    } catch (_) {
      // Never interpolate an SDK error: rejected configuration can be echoed
      // by exception messages. Hidden local test accounts remain available.
      debugPrint(
        'Supabase initialization unavailable; remote sign-in is disabled.',
      );
    }
  }

  runApp(const ProviderScope(child: ArangCadaApp()));
}
