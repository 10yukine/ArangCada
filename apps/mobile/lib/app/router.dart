import 'package:flutter/material.dart';
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
import '../features/chat/chat_list_screen.dart';
import '../features/chat/chat_thread_screen.dart';
import '../features/driver/driver_screens.dart';
import '../features/driver/driver_earnings_screen.dart';
import '../features/home/commuter_home_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/about_screen.dart';
import '../features/profile/developer_panel_screen.dart';
import '../features/profile/profile_detail_screens.dart';
import '../features/profile/profile_screen.dart';
import '../features/rating/rating_screen.dart';
import '../features/receipt/digital_receipt_screen.dart';
import '../features/search/destination_search_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/trips/trips_screen.dart';
import '../features/trip/active_trip_screen.dart';
import '../features/trip/driver_approach_screen.dart';
import '../features/wallet/wallet_screen.dart';
import 'shells/commuter_shell.dart';
import 'shells/driver_shell.dart';
import 'theme/app_dimensions.dart';

CustomTransitionPage<void> _screenPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: AppMotion.screen,
    reverseTransitionDuration: AppMotion.screen,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final eased = CurvedAnimation(parent: animation, curve: Curves.easeOut);
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
      if (user.role == DemoRole.commuter &&
          path.startsWith('/driver')) {
        return '/home';
      }
      // A chat thread is opened full-screen by both roles, so it is not
      // owned by either role's tab tree.
      final isSharedPath = path.startsWith('/chat/');
      if (user.role == DemoRole.driver &&
          !path.startsWith('/driver') &&
          !isSharedPath) {
        return '/driver';
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
        pageBuilder: (context, state) =>
            _screenPage(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) =>
            _screenPage(state, const ForgotPasswordScreen()),
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
      GoRoute(
        path: '/trip/approach',
        pageBuilder: (context, state) =>
            _screenPage(state, const DriverApproachScreen()),
      ),
      GoRoute(
        path: '/trip/active',
        pageBuilder: (context, state) =>
            _screenPage(state, const ActiveTripScreen()),
      ),
      GoRoute(
        path: '/receipt',
        pageBuilder: (context, state) =>
            _screenPage(state, const DigitalReceiptScreen()),
      ),
      GoRoute(
        path: '/rating',
        pageBuilder: (context, state) =>
            _screenPage(state, const RatingScreen()),
      ),
      GoRoute(
        path: '/chat/:threadId',
        pageBuilder: (context, state) => _screenPage(
          state,
          ChatThreadScreen(threadId: state.pathParameters['threadId']!),
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) =>
            _screenPage(state, const NotificationsScreen()),
      ),
      GoRoute(
        path: '/profile/personal-information',
        pageBuilder: (context, state) =>
            _screenPage(state, const PersonalInformationScreen()),
      ),
      GoRoute(
        path: '/profile/saved-places',
        pageBuilder: (context, state) =>
            _screenPage(state, const SavedPlacesScreen()),
      ),
      GoRoute(
        path: '/profile/discount-eligibility',
        pageBuilder: (context, state) =>
            _screenPage(state, const DiscountEligibilityScreen()),
      ),
      GoRoute(
        path: '/profile/safety',
        pageBuilder: (context, state) =>
            _screenPage(state, const SafetySettingsScreen()),
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
                path: '/wallet',
                pageBuilder: (context, state) =>
                    _screenPage(state, const WalletScreen()),
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
                path: '/driver/earnings',
                pageBuilder: (context, state) =>
                    _screenPage(state, const DriverEarningsScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver/profile',
                pageBuilder: (context, state) =>
                    _screenPage(state, const DriverProfileScreen()),
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
