import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_tab_bar.dart';
import '../../data/providers/repository_providers.dart';
import 'commuter_shell.dart' show AdaptiveTabShell;

/// Driver tab tree: Home / Chat / Trips / Profile, the same four as the
/// commuter. Earnings opens from its row on Driver Home.
///
class DriverShell extends ConsumerWidget {
  const DriverShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatRepository = ref.watch(chatRepositoryProvider);

    return ListenableBuilder(
      listenable: chatRepository,
      builder: (context, _) {
        final hasUnread = chatRepository.totalUnread > 0;
        final destinations = [
          const AppTabDestination(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: 'Home',
          ),
          AppTabDestination(
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            label: 'Chat',
            showNotification: hasUnread,
          ),
          const AppTabDestination(
            // A clock, not a receipt. receipt_long carries ruled lines and a
            // torn edge that turn to noise at 22px, and it was the busiest
            // glyph in the row. This tab is trip history, so a clock says the
            // same thing with a fraction of the detail. access_time over
            // history because history's arrow is more ink for no more meaning,
            // and because access_time has a filled twin -- every other
            // destination pairs an outline with a fill, and history has none.
            icon: Icons.access_time,
            selectedIcon: Icons.access_time_filled,
            label: 'Trips',
          ),
          const AppTabDestination(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: 'Profile',
          ),
        ];

        return AdaptiveTabShell(
          selectedIndex: navigationShell.currentIndex,
          onSelected: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
          destinations: destinations,
          body: navigationShell,
        );
      },
    );
  }
}
