import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/section_card.dart';

class DemoAppNotification {
  const DemoAppNotification({
    required this.title,
    required this.message,
    required this.timeLabel,
    required this.icon,
    this.isUnread = false,
  });

  final String title;
  final String message;
  final String timeLabel;
  final IconData icon;
  final bool isUnread;
}

const _mockNotifications = [
  DemoAppNotification(
    title: 'Driver assigned',
    message: 'Marco Dela Cruz is heading to your pickup point.',
    timeLabel: '2 min ago',
    icon: Icons.electric_rickshaw_outlined,
    isUnread: true,
  ),
  DemoAppNotification(
    title: 'Receipt ready',
    message: 'Your completed ride receipt is available in Trips.',
    timeLabel: 'Yesterday',
    icon: Icons.receipt_long_outlined,
  ),
  DemoAppNotification(
    title: 'Safety reminder',
    message: 'Confirm the tricycle body number before boarding.',
    timeLabel: '2 days ago',
    icon: Icons.shield_outlined,
  ),
];

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({this.notifications, super.key});

  final List<DemoAppNotification>? notifications;

  @override
  Widget build(BuildContext context) {
    final items = notifications ?? _mockNotifications;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: SafeArea(
        child: items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: EmptyStateCard(
                  icon: Icons.notifications_none,
                  title: 'No notifications',
                  message:
                      'Ride updates and safety reminders will appear here.',
                  actionLabel: 'Back to Home',
                  onAction: () => context.go('/home'),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return SectionCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppRowIcon(item.icon),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                  if (item.isUnread)
                                    const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: AppColors.danger,
                                        shape: BoxShape.circle,
                                      ),
                                      child: SizedBox.square(dimension: 9),
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(item.message),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                item.timeLabel,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
