import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/providers/repository_providers.dart';
import '../domain/models/demo_user.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/booking/ride_options_screen.dart';
import '../features/booking/booking_review_screen.dart';
import '../features/booking/driver_matched_screen.dart';
import '../features/booking/searching_for_driver_screen.dart';
import '../features/driver/driver_screens.dart';
import '../features/driver/driver_earnings_screen.dart';
import '../features/home/commuter_home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/receipt/digital_receipt_screen.dart';
import '../features/search/destination_search_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/trips/trips_screen.dart';
import '../features/trip/active_trip_screen.dart';
import '../features/trip/driver_approach_screen.dart';
import '../features/wallet/wallet_screen.dart';
import 'shells/commuter_shell.dart';
import 'shells/driver_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final demoState = ref.watch(demoStateProvider);
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: demoState,
    redirect: (context, state) {
      final path = state.uri.path;
      if (path == '/splash') return null;

      final user = demoState.currentUser;
      final isAuthPath = path == '/login' || path == '/forgot-password';
      if (user == null) return isAuthPath ? null : '/login';

      final roleHome = user.role == DemoRole.commuter ? '/home' : '/driver';
      if (isAuthPath || path == '/') return roleHome;
      if (user.role == DemoRole.commuter && path.startsWith('/driver')) {
        return '/home';
      }
      if (user.role == DemoRole.driver && !path.startsWith('/driver')) {
        return '/driver';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/splash'),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/booking/review',
        builder: (context, state) => const BookingReviewScreen(),
      ),
      GoRoute(
        path: '/booking/searching',
        builder: (context, state) => const SearchingForDriverScreen(),
      ),
      GoRoute(
        path: '/booking/driver-matched',
        builder: (context, state) => const DriverMatchedScreen(),
      ),
      GoRoute(
        path: '/trip/approach',
        builder: (context, state) => const DriverApproachScreen(),
      ),
      GoRoute(
        path: '/trip/active',
        builder: (context, state) => const ActiveTripScreen(),
      ),
      GoRoute(
        path: '/receipt',
        builder: (context, state) => const DigitalReceiptScreen(),
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
                builder: (context, state) => const CommuterHomeScreen(),
                routes: [
                  GoRoute(
                    path: 'search',
                    builder: (context, state) =>
                        const DestinationSearchScreen(),
                  ),
                  GoRoute(
                    path: 'ride-options',
                    builder: (context, state) => const RideOptionsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/trips',
                builder: (context, state) => const TripsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/wallet',
                builder: (context, state) => const WalletScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
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
                builder: (context, state) => const DriverHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver/earnings',
                builder: (context, state) => const DriverEarningsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver/profile',
                builder: (context, state) => const DriverProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
