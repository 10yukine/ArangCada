import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-tab roots (Chats, Trips, Profile) have nothing
/// for Navigator to pop to, so `AppBar` shows no back arrow by default.
/// This is an explicit shortcut back to the dashboard instead, used the
/// same way on every tab root across both roles.
class DashboardBackButton extends StatelessWidget {
  const DashboardBackButton({required this.isDriver, super.key});

  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: 'Back to dashboard',
      onPressed: () => context.go(isDriver ? '/driver' : '/home'),
    );
  }
}
