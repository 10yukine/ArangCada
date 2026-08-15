import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/floating_tab_bar.dart';

class CommuterShell extends StatelessWidget {
  const CommuterShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
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
        destinations: const [
          FloatingTabDestination(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: 'Home',
          ),
          FloatingTabDestination(
            icon: Icons.route_outlined,
            selectedIcon: Icons.route,
            label: 'Trips',
            showNotification: true,
          ),
          FloatingTabDestination(
            icon: Icons.account_balance_wallet_outlined,
            selectedIcon: Icons.account_balance_wallet,
            label: 'Wallet',
          ),
          FloatingTabDestination(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
