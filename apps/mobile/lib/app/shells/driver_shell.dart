import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/floating_tab_bar.dart';
import '../../data/providers/repository_providers.dart';

/// Driver tab tree: Home / Chat / Earnings / Profile.
///
/// The commuter Wallet deliberately does not appear here. A driver's digital
/// money lives under Earnings as settlement, not as a spendable balance.
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
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: FloatingTabBar(
            selectedIndex: navigationShell.currentIndex,
            onSelected: (index) {
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
            },
            destinations: [
              const FloatingTabDestination(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: 'Home',
              ),
              FloatingTabDestination(
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
                label: 'Chat',
                showNotification: hasUnread,
              ),
              const FloatingTabDestination(
                icon: Icons.receipt_long_outlined,
                selectedIcon: Icons.receipt_long,
                label: 'Trips',
              ),
              const FloatingTabDestination(
                icon: Icons.payments_outlined,
                selectedIcon: Icons.payments,
                label: 'Earnings',
              ),
              const FloatingTabDestination(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}
