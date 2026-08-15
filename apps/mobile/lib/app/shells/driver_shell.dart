import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/floating_tab_bar.dart';

class DriverShell extends StatelessWidget {
  const DriverShell({required this.navigationShell, super.key});

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
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            label: 'Home',
            showNotification: true,
          ),
          FloatingTabDestination(
            icon: Icons.payments_outlined,
            selectedIcon: Icons.payments,
            label: 'Earnings',
          ),
          FloatingTabDestination(
            icon: Icons.badge_outlined,
            selectedIcon: Icons.badge,
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
