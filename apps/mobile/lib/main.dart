import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hybrid composition is the plugin default, but setting it explicitly makes
  // the Android side send textureMode(true) with the view creation params
  // rather than relying on detection order.
  MapLibreMap.useHybridComposition = true;

  await Hive.initFlutter();
  await Hive.openBox<String>('arangcada_demo');

  if (AppConfig.isFullyConfigured) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
    } catch (_) {
      // Never interpolate an SDK error: rejected configuration can be echoed
      // by exception messages. The offline demo remains available.
      debugPrint(
        'Supabase initialization unavailable; continuing in demo mode.',
      );
    }
  }

  runApp(const ProviderScope(child: ArangCadaApp()));
}
