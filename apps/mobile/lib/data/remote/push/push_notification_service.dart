import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/router.dart';

/// FCM is used ONLY as a push-delivery transport for ride-offer and
/// ride-status alerts. Supabase remains the system of record for the trip
/// itself -- every screen this taps into (the driver offer card, the
/// commuter Trips screen) already renders from Supabase Realtime state, not
/// from anything carried in the push payload. No Firestore, Firebase Auth,
/// Firebase Storage, or Cloud Functions are used.
///
/// Expected `data` payload contract (produced by a future trusted
/// server-side sender -- see the STOP-boundary note in
/// docs/COMPETITOR_TECH_DECISIONS.md):
/// ```
/// { "type": "ride_offer" | "ride_cancelled" | "ride_expired" | "ride_updated",
///   "trip_id": "<uuid>" }
/// ```
class PushNotificationService {
  PushNotificationService._();

  static const _channel = AndroidNotificationChannel(
    'ride_offers',
    'Ride offers',
    description:
        'Alerts a driver to a new ride offer and lets a rider know when a '
        'trip status changes.',
    importance: Importance.high,
  );

  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String? _registeredToken;
  // Every reauthenticate() call (password change, mobile/email change on the
  // Account & Security screen) fires another AuthChangeEvent.signedIn, and
  // main.dart's listener calls registerForSession() again. Without tracking
  // this subscription, each call attached a second onTokenRefresh listener
  // with no way to cancel the first -- N reauths in one session meant N
  // duplicate register_push_token RPCs per token refresh, and N closures
  // pinning a SupabaseClient for the rest of the process's life.
  static StreamSubscription<String>? _tokenRefreshSub;

  /// Only Android is wired for push right now -- google-services.json only
  /// registers an Android app, and iOS/Web are out of this project's
  /// platform scope (see CLAUDE.md, Android + Web only, and FCM was
  /// requested for the Android client specifically).
  static bool get _supportsPush => !kIsWeb && Platform.isAndroid;

  /// Call once, early in `main()`, before `runApp`. Safe to call even when
  /// Firebase is not configured for this build (no google-services.json) --
  /// every step is guarded so a missing/broken Firebase setup only disables
  /// push, it never crashes app startup.
  static Future<void> bootstrap() async {
    if (!_supportsPush || _initialized) return;
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // No google-services.json, or Firebase project not reachable: push is
      // simply unavailable this session. Every other feature (Supabase
      // dispatch, chat, SOS, fare) does not depend on this succeeding.
      return;
    }

    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        _navigateForPayload(payload);
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _navigateForData(message.data);
    });
    final initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();
    if (initialMessage != null) _navigateForData(initialMessage.data);

    _initialized = true;
  }

  /// Call after a real (non-demo) Supabase session is established. Requests
  /// the Android 13+ notification permission, gets the current FCM token,
  /// registers it against `register_push_token`, and keeps it in sync on
  /// refresh for the lifetime of the app process.
  static Future<void> registerForSession(SupabaseClient client) async {
    if (!_supportsPush || !_initialized) return;
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _syncToken(client, token);
      // Replace, never accumulate: a stale listener from an earlier
      // reauthenticate() in this same session would otherwise keep syncing
      // tokens against whatever SupabaseClient it closed over.
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((
        refreshed,
      ) {
        unawaited(_syncToken(client, refreshed));
      });
    } catch (_) {
      // Token registration is a best-effort convenience layer; a failure
      // here must never block sign-in or ride flows.
    }
  }

  /// Call on sign-out so a shared/reused device stops receiving a
  /// now-signed-out account's ride-offer pushes.
  static Future<void> unregisterForSession(SupabaseClient client) async {
    final token = _registeredToken;
    if (!_supportsPush || token == null) return;
    try {
      await client.rpc('unregister_push_token', params: {'p_fcm_token': token});
    } catch (_) {
      // Best-effort: an unreachable backend during sign-out must not block it.
    } finally {
      _registeredToken = null;
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
    }
  }

  static Future<void> _syncToken(SupabaseClient client, String token) async {
    try {
      await client.rpc(
        'register_push_token',
        params: {'p_fcm_token': token, 'p_platform': 'android'},
      );
      _registeredToken = token;
    } catch (_) {
      // Retried automatically on the next onTokenRefresh/app-open; a single
      // failed sync must not surface to the user.
    }
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final tripId = message.data['trip_id'] as String?;
    await _localNotifications.show(
      id: _notificationId(tripId),
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// A stable per-trip notification id lets an expired/cancelled push
  /// dismiss the exact offer alert it supersedes instead of stacking a
  /// second, stale-looking notification for the same ride.
  static int _notificationId(String? tripId) =>
      tripId == null ? 0 : tripId.hashCode & 0x7fffffff;

  /// Called when a ride-offer/status push arrives for a trip that is no
  /// longer relevant (offer expired, ride cancelled). Cancels the specific
  /// tray notification for that trip if one is currently showing.
  static Future<void> dismissForTrip(String tripId) =>
      _localNotifications.cancel(id: _notificationId(tripId));

  static void _navigateForPayload(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _navigateForData(data);
    } catch (_) {
      // Malformed/unexpected payload: do nothing rather than crash on tap.
    }
  }

  static void _navigateForData(Map<String, dynamic> data) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final type = data['type'] as String?;
    switch (type) {
      case 'ride_offer':
      case 'ride_cancelled':
      case 'ride_expired':
        // The driver dashboard already renders the live offer/cancellation
        // state the moment Supabase Realtime delivers it; the push only
        // needs to bring the app to that screen.
        GoRouter.of(context).go('/driver');
      default:
        // Commuter-side status changes (driver assigned, arrived, trip
        // started) already have a one-tap "Resume" to the exact right
        // screen from Trips, reusing that existing, tested routing instead
        // of duplicating a per-status deep-link table here.
        GoRouter.of(context).go('/trips');
    }
  }
}

/// Runs in a separate background isolate with no access to the app's widget
/// tree, Riverpod containers, or GoRouter instance -- it must re-initialize
/// Firebase itself and must not touch any of that state. A `notification`
/// payload is already shown by the OS automatically in this case; this
/// handler exists so `onBackgroundMessage` is registered at all, which FCM
/// requires even when there is nothing extra to do here.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
