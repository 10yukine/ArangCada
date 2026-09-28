import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/adaptive_screen_frame.dart';
import '../data/providers/repository_providers.dart';
import '../core/geo/haversine.dart';
import '../demo/demo_data.dart';
import '../domain/models/demo_user.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/verify_phone_screen.dart';
import '../features/profile/change_password_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/complete_mobile_profile_screen.dart';
import '../features/auth/sign_up_screen.dart';
import '../features/booking/ride_options_screen.dart';
import '../features/booking/booking_review_screen.dart';
import '../features/booking/driver_matched_screen.dart';
import '../features/booking/searching_for_driver_screen.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/chat/chat_thread_screen.dart';
import '../features/driver/driver_screens.dart';
import '../features/fare/fare_matrix_screen.dart';
import '../features/driver/driver_earnings_screen.dart';
import '../features/home/commuter_home_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/about_screen.dart';
import '../features/profile/developer_panel_screen.dart';
import '../features/profile/discount_eligibility_screen.dart';
import '../features/profile/profile_detail_screens.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/driver_documents_screen.dart';
import '../features/profile/support_screen.dart';
import '../features/rating/driver_rating_screen.dart';
import '../features/rating/driver_app_feedback_screen.dart';
import '../features/rating/rating_screen.dart';
import '../features/receipt/digital_receipt_screen.dart';
import '../features/search/destination_search_screen.dart';
import '../features/search/pin_on_map_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/trips/trips_screen.dart';
import '../features/trip/active_trip_screen.dart';
import 'shells/commuter_shell.dart';
import 'shells/driver_shell.dart';
import 'theme/app_dimensions.dart';

CustomTransitionPage<T> _screenPage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    transitionDuration: AppMotion.screen,
    reverseTransitionDuration: AppMotion.screen,
    child: AdaptiveScreenFrame(child: child),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final eased = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      // The platform's "remove animations" accessibility setting gets a
      // plain cross-fade, not the slide -- reduced motion means gentler
      // feedback, not none.
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        return FadeTransition(opacity: eased, child: child);
      }
      return FadeTransition(
        opacity: eased,
        child: AnimatedBuilder(
          animation: eased,
          child: child,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, 4 * (1 - eased.value)),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Full-screen destinations both roles push on top of their own tab tree.
///
/// These are not owned by either shell, so a driver reaching one must not be
/// bounced back to the driver dashboard. `/profile` exactly is the commuter
/// tab and stays commuter-only; `/profile/...` are the shared detail screens
/// the driver profile links to as well. Getting this wrong silently
/// redirects the driver home and makes every row on their profile look dead.
///
/// Exported so the role-access test exercises this rule rather than a copy.
bool isSharedFullScreenPath(String path) =>
    path.startsWith('/chat/') ||
    path.startsWith('/profile/') ||
    path == '/fare-matrix' ||
    path == '/notifications';

/// Lets code outside the widget tree (specifically the FCM tap handler in
/// PushNotificationService, which runs from a plugin callback with no
/// BuildContext of its own) navigate through the same router the rest of
/// the app uses, instead of maintaining a second navigation mechanism.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Set by main.dart when a password-reset email link opens the app
/// (Supabase's passwordRecovery event). While set, the only screen is
/// /reset-password; ResetPasswordScreen clears it and signs out.
final passwordRecoveryPending = ValueNotifier<bool>(false);

final appRouterProvider = Provider<GoRouter>((ref) {
  final demoState = ref.watch(demoStateProvider);
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: Listenable.merge([demoState, passwordRecoveryPending]),
    redirect: (context, state) {
      final path = state.uri.path;
      final restoration = ref.read(sessionRestorationProvider);
      if (restoration.isLoading || restoration.hasError) {
        return path == '/splash' ? null : '/splash';
      }
      if (passwordRecoveryPending.value) {
        return path == '/reset-password' ? null : '/reset-password';
      }
      if (path == '/reset-password') return '/splash';

      final user = demoState.currentUser;
      if (path == '/splash') {
        if (user == null) return '/login';
        if (user.needsPhoneSetup) return '/complete-mobile-profile';
        if (user.needsPhoneVerification) return '/verify-phone';
        return user.role == DemoRole.commuter ? '/home' : '/driver';
      }
      final isAuthPath =
          path == '/login' || path == '/signup' || path == '/forgot-password';
      if (user == null) return isAuthPath ? null : '/login';

      // Phone verification gate. An account that has not proved control of its
      // mobile number is signed in but goes nowhere except the verify screen.
      //
      // This is a convenience gate, not the access control: request_ride,
      // can_driver_go_online and create_ride_share_link each refuse an
      // unverified account server-side, so forcing past this redirect gains a
      // tampered client nothing (CLAUDE.md rule 6).
      if (user.needsPhoneVerification) {
        if (path == '/complete-mobile-profile') return null;
        if (user.needsPhoneSetup) return '/complete-mobile-profile';
        return path == '/verify-phone' ? null : '/verify-phone';
      }
      if (path == '/verify-phone' || path == '/complete-mobile-profile') {
        return user.role == DemoRole.commuter ? '/home' : '/driver';
      }

      final roleHome = user.role == DemoRole.commuter ? '/home' : '/driver';
      if (isAuthPath || path == '/') return roleHome;
      if (user.role == DemoRole.commuter && path.startsWith('/driver')) {
        return '/home';
      }
      if (user.role == DemoRole.driver &&
          !path.startsWith('/driver') &&
          !isSharedFullScreenPath(path)) {
        return '/driver';
      }
      if (user.role == DemoRole.driver &&
          demoState.driverFeedbackPending &&
          path != '/driver/rating' &&
          path != '/driver/app-feedback') {
        return '/driver/app-feedback';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/splash'),
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) =>
            _screenPage(state, const SplashScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _screenPage(
          state,
          LoginScreen(existingAccountEmail: state.extra as String?),
        ),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) =>
            _screenPage(state, const ResetPasswordScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) =>
            _screenPage(state, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: '/complete-mobile-profile',
        pageBuilder: (context, state) =>
            _screenPage(state, const CompleteMobileProfileScreen()),
      ),
      GoRoute(
        path: '/verify-phone',
        pageBuilder: (context, state) => _screenPage(
          state,
          // Survives the redirect above: an account that still needs
          // verification returns null for this path rather than redirecting,
          // so `extra` is not discarded on the way in.
          VerifyPhoneScreen(initialError: state.extra as String?),
        ),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) =>
            _screenPage(state, const SignUpScreen()),
      ),
      GoRoute(
        path: '/booking/review',
        pageBuilder: (context, state) =>
            _screenPage(state, const BookingReviewScreen()),
      ),
      GoRoute(
        path: '/booking/searching',
        pageBuilder: (context, state) =>
            _screenPage(state, const SearchingForDriverScreen()),
      ),
      GoRoute(
        path: '/booking/driver-matched',
        pageBuilder: (context, state) =>
            _screenPage(state, const DriverMatchedScreen()),
      ),
      // Kept as a redirect rather than deleted. The approach screen merged into
      // driver-matched on 4 Sep 2026, but this path is still reachable from
      // notifications, a resumed session, and anything that stored a deep link
      // before the merge -- and a dead route would strand those on a 404.
      GoRoute(
        path: '/trip/approach',
        redirect: (context, state) => '/booking/driver-matched',
      ),
      GoRoute(
        path: '/trip/active',
        pageBuilder: (context, state) =>
            _screenPage(state, const ActiveTripScreen()),
      ),
      GoRoute(
        path: '/receipt',
        pageBuilder: (context, state) => _screenPage(
          state,
          DigitalReceiptScreen(tripId: state.uri.queryParameters['trip']),
        ),
      ),
      GoRoute(
        path: '/rating',
        pageBuilder: (context, state) =>
            _screenPage(state, const RatingScreen()),
      ),
      GoRoute(
        path: '/driver/rating',
        pageBuilder: (context, state) =>
            _screenPage(state, const DriverRatingScreen()),
      ),
      // Opened from the Earnings row on Driver Home, so both roles share the
      // same four tabs (Home / Chat / Trips / Profile).
      GoRoute(
        path: '/driver/earnings',
        pageBuilder: (context, state) =>
            _screenPage(state, const DriverEarningsScreen()),
      ),
      GoRoute(
        path: '/driver/app-feedback',
        pageBuilder: (context, state) =>
            _screenPage(state, const DriverAppFeedbackScreen()),
      ),
      GoRoute(
        path: '/chat/:threadId',
        pageBuilder: (context, state) => _screenPage(
          state,
          ChatThreadScreen(threadId: state.pathParameters['threadId']!),
        ),
      ),
      GoRoute(
        path: '/fare-matrix',
        pageBuilder: (context, state) =>
            _screenPage(state, const FareMatrixScreen()),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) =>
            _screenPage(state, const NotificationsScreen()),
      ),
      GoRoute(
        path: '/profile/edit',
        pageBuilder: (context, state) =>
            _screenPage(state, const EditProfileScreen()),
      ),
      GoRoute(
        path: '/profile/change-password',
        pageBuilder: (context, state) =>
            _screenPage(state, const ChangePasswordScreen()),
      ),
      GoRoute(
        path: '/profile/saved-places',
        pageBuilder: (context, state) =>
            _screenPage(state, const SavedPlacesScreen()),
      ),
      GoRoute(
        path: '/profile/driver-documents',
        pageBuilder: (context, state) =>
            _screenPage(state, const DriverDocumentsScreen()),
      ),
      GoRoute(
        path: '/profile/discount-eligibility',
        pageBuilder: (context, state) =>
            _screenPage(state, const DiscountEligibilityScreen()),
      ),
      GoRoute(
        path: '/profile/support',
        pageBuilder: (context, state) =>
            _screenPage(state, const SupportScreen()),
      ),
      GoRoute(
        path: '/profile/app-settings',
        pageBuilder: (context, state) =>
            _screenPage(state, const AppSettingsScreen()),
      ),
      GoRoute(
        path: '/profile/about',
        pageBuilder: (context, state) =>
            _screenPage(state, const AboutArangCadaScreen()),
      ),
      GoRoute(
        path: '/profile/demo-tools',
        pageBuilder: (context, state) =>
            _screenPage(state, const DeveloperPanelScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return CommuterShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (context, state) =>
                    _screenPage(state, const CommuterHomeScreen()),
                routes: [
                  GoRoute(
                    path: 'search',
                    pageBuilder: (context, state) =>
                        _screenPage(state, const DestinationSearchScreen()),
                  ),
                  // Pickup is always the device's GPS position; this only
                  // nudges it within a short radius. Without a fix to leash
                  // to (e.g. a deep link) there is nothing to adjust.
                  GoRoute(
                    path: 'adjust-pickup',
                    redirect: (context, state) =>
                        state.extra is GeoCoordinate ? null : '/home',
                    pageBuilder: (context, state) => _screenPage<DemoPlace>(
                      state,
                      PinOnMapScreen(
                        pickupAnchor: state.extra! as GeoCoordinate,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'pin-on-map',
                    pageBuilder: (context, state) =>
                        _screenPage<DemoPlace>(state, const PinOnMapScreen()),
                  ),
                  GoRoute(
                    path: 'ride-options',
                    pageBuilder: (context, state) =>
                        _screenPage(state, const RideOptionsScreen()),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chat',
                pageBuilder: (context, state) =>
                    _screenPage(state, const ChatListScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/trips',
                pageBuilder: (context, state) =>
                    _screenPage(state, const TripsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) =>
                    _screenPage(state, const ProfileScreen()),
              ),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return DriverShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver',
                pageBuilder: (context, state) =>
                    _screenPage(state, const DriverHomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver/chat',
                pageBuilder: (context, state) =>
                    _screenPage(state, const ChatListScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver/trips',
                pageBuilder: (context, state) =>
                    _screenPage(state, const TripsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver/profile',
                // Both roles render the same ProfileScreen; it branches on
                // role internally so the two cannot drift apart.
                pageBuilder: (context, state) =>
                    _screenPage(state, const ProfileScreen()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.listen(sessionRestorationProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});
