import 'package:arangcada/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

/// The driver profile links to the same detail screens as the commuter one.
///
/// The role redirect used to bounce anything outside `/driver` back to the
/// driver dashboard, so every one of those rows silently did nothing: the
/// Profile tab highlighted while the dashboard stayed on screen. Caught on a
/// physical device, pinned here.
///
/// These exercise `isSharedFullScreenPath` from `router.dart` directly, not a
/// copy of the rule, so the test fails if the real predicate changes.
void main() {
  group('driver can reach the shared detail screens', () {
    const reachableByBothRoles = [
      '/profile/saved-places',
      '/profile/discount-eligibility',
      '/profile/support',
      '/profile/app-settings',
      '/profile/about',
      '/profile/demo-tools',
      '/fare-matrix',
      '/notifications',
      '/chat/thread-active',
    ];

    for (final path in reachableByBothRoles) {
      test(path, () => expect(isSharedFullScreenPath(path), isTrue));
    }
  });

  group('role-owned routes stay role-owned', () {
    // `/profile` exactly is the commuter tab branch. Only its subroutes are
    // shared, otherwise a driver could land on the commuter profile tab.
    const notShared = [
      '/profile',
      '/home',
      '/wallet',
      '/trips',
      '/booking/review',
      '/booking/searching',
      '/booking/driver-matched',
      '/trip/active',
      '/trip/approach',
      '/receipt',
      '/rating',
      '/driver',
      '/driver/earnings',
    ];

    for (final path in notShared) {
      test(path, () => expect(isSharedFullScreenPath(path), isFalse));
    }
  });
}
