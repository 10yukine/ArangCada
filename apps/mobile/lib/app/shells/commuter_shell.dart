import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/floating_tab_bar.dart';
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
                icon: Icons.account_balance_wallet_outlined,
                selectedIcon: Icons.account_balance_wallet,
                label: 'Wallet',
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
