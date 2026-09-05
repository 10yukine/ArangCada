import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/app_tab_bar.dart';
import '../../data/providers/repository_providers.dart';

/// Commuter tab tree.
///
/// Five tabs: the prototype's Home / Chat / History / Profile, plus the
/// Wallet added by the Flutter build. Chat is not dropped to make room --
/// it is a primary surface in the approved design.
class CommuterShell extends ConsumerWidget {
  const CommuterShell({required this.navigationShell, super.key});

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
            icon: Icons.account_balance_wallet_outlined,
            selectedIcon: Icons.account_balance_wallet,
            label: 'Wallet',
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

/// Bottom [AppTabBar] below [AppBreakpoints.compact]; a side
/// [NavigationRail] at [AppBreakpoints.compact] and above, matching
/// Material's adaptive navigation guidance (rail replaces bottom bar once a
/// window has room for one). Shared by [CommuterShell] and `DriverShell` so
/// the two role tab trees stay visually and behaviorally identical.
class AdaptiveTabShell extends StatelessWidget {
  const AdaptiveTabShell({
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
    required this.body,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<AppTabDestination> destinations;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (AppBreakpoints.isCompact(context)) {
      return Scaffold(
        body: body,
        bottomNavigationBar: AppTabBar(
          selectedIndex: selectedIndex,
          onSelected: onSelected,
          destinations: destinations,
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: AppSizes.navigationRailWidth,
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              backgroundColor: AppColors.surface,
              indicatorColor: AppColors.primaryFill,
              selectedIconTheme: const IconThemeData(color: AppColors.primary),
              unselectedIconTheme: const IconThemeData(
                color: AppColors.textMuted,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: Badge(
                      isLabelVisible: destination.showNotification,
                      backgroundColor: AppColors.danger,
                      smallSize: 8,
                      child: Icon(destination.icon),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: destination.showNotification,
                      backgroundColor: AppColors.danger,
                      smallSize: 8,
                      child: Icon(destination.selectedIcon),
                    ),
                    label: Text(destination.label),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, color: AppColors.dividerLight),
          Expanded(child: body),
        ],
      ),
    );
  }
}
