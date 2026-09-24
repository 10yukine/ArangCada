import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/app_notification.dart';

/// Real notification history, not the fixed three-entry mock list this
/// screen used to render regardless of what actually happened. See
/// .pipeline/specs.md Spec 16.
///
/// Backed by a local Hive cache PushNotificationService's own
/// `onMessage`/`onMessageOpenedApp` handlers already write to -- there is
/// no server table and no cross-device sync, deliberately (see the spec's
/// "smallest option" rationale). Tapping an entry marks it read; there is
/// no detail screen, since every notification type already has its own
/// one-tap "Resume" destination via the same routing
/// PushNotificationService uses for a tapped push.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late List<AppNotificationRecord> _items;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _items = ref.read(notificationsRepositoryProvider).history();
    });
  }

  Future<void> _open(AppNotificationRecord item) async {
    if (!item.read) {
      await ref.read(notificationsRepositoryProvider).markRead(item.id);
      // markRead() is awaited above -- the user can navigate away (or the
      // screen can otherwise be disposed) while it is in flight. setState
      // via _refresh() on a disposed State throws. Independent review
      // finding (Copilot, PR #17 council-review snapshot, 6 Sep 2026).
      if (!mounted) return;
      _refresh();
    }
    if (!mounted) return;
    // Same routing PushNotificationService._navigateForData uses when a
    // tapped push opens the app -- driver-targeted notifications land on /driver,
    // commuter notifications land on /trips where the existing per-status
    // "Resume" button takes over.
    final targetRole = item.data['target_role'] as String?;
    final route = switch (targetRole) {
      'driver' => '/driver',
      'commuter' => '/trips',
      _ => switch (item.data['type']) {
        'ride_offer' || 'ride_cancelled' || 'ride_expired' => '/driver',
        _ => '/trips',
      },
    };
    GoRouter.maybeOf(context)?.go(route);
  }

  static IconData _iconFor(AppNotificationRecord item) =>
      switch (item.data['type']) {
        'ride_offer' => Icons.electric_rickshaw_outlined,
        'ride_cancelled' => Icons.cancel_outlined,
        'ride_expired' => Icons.timer_off_outlined,
        'ride_updated' => Icons.directions_car_filled_outlined,
        _ => Icons.notifications_outlined,
      };

  static String _relativeTime(DateTime value) {
    final now = DateTime.now();
    final diff = now.difference(value);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    final isYesterday =
        now.difference(DateTime(value.year, value.month, value.day)).inDays ==
        1;
    if (isYesterday) return 'Yesterday';
    return DateFormat('MMM d').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
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
                    const Divider(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    onTap: () => _open(item),
                    child: SectionCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppRowIcon(_iconFor(item)),
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
                                    if (!item.read)
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
                                Text(item.body),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  _relativeTime(item.receivedAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
