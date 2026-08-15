import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/relative_time.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/slidable.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/chat.dart';

enum _ChatFilter { all, unread }

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  _ChatFilter _filter = _ChatFilter.all;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(chatRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: ListenableBuilder(
        listenable: repository,
        builder: (context, _) {
          final all = repository.threads;
          final threads = _filter == _ChatFilter.unread
              ? all.where((t) => t.unreadCount > 0).toList()
              : all;

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  10,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.dividerLight),
                  ),
                ),
                child: Row(
                  children: [
                    ArangChip(
                      label: 'All',
                      selected: _filter == _ChatFilter.all,
                      onTap: () => setState(() => _filter = _ChatFilter.all),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    ArangChip(
                      label: 'Unread',
                      selected: _filter == _ChatFilter.unread,
                      onTap: () => setState(() => _filter = _ChatFilter.unread),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: threads.isEmpty
                    ? _EmptyChats(filtered: _filter == _ChatFilter.unread)
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: threads.length,
                        itemBuilder: (context, i) =>
                            _ThreadRow(thread: threads[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThreadRow extends ConsumerWidget {
  const _ThreadRow({required this.thread});

  final ChatThread thread;

  /// Prototype behaviour: swiping a row or holding it reveals the same
  /// options card, with a separate Cancel card beneath it.
  void _showOptions(BuildContext context, WidgetRef ref, ChatThread thread) {
    final repository = ref.read(chatRepositoryProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArangCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          thread.driverName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Chat options',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.dividerLight),
                  _OptionButton(
                    label: thread.unreadCount > 0
                        ? 'Mark as read'
                        : 'Mark as unread',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      if (thread.unreadCount > 0) {
                        repository.markRead(thread.id);
                      } else {
                        repository.markUnread(thread.id);
                      }
                    },
                  ),
                  const Divider(height: 1, color: AppColors.dividerLight),
                  _OptionButton(
                    label: 'Mute notifications',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Notifications muted for ${thread.driverName}.',
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, color: AppColors.dividerLight),
                  _OptionButton(
                    label: 'Report safety concern',
                    danger: true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Report recorded for ArangCada administrators.',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ArangCard(
              padding: EdgeInsets.zero,
              child: _OptionButton(
                label: 'Cancel',
                bold: true,
                onTap: () => Navigator.pop(sheetContext),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = thread.unreadCount > 0;
    final last = thread.lastMessage;

    // Swiping reveals a dots button that stays open; tapping it opens the
    // options card. Swiping does NOT jump straight to the popup, and it never
    // deletes a conversation.
    return Slidable(
      onOpenOptions: () => _showOptions(context, ref, thread),
      child: Material(
        color: AppColors.surface,
        child: InkWell(
          onTap: () => context.push('/chat/${thread.id}'),
          onLongPress: () => _showOptions(context, ref, thread),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.dividerLight)),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 14,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArangAvatar(
                  name: thread.driverName,
                  background: thread.isActiveTrip
                      ? AppColors.primary
                      : AppColors.clayFill,
                  foreground: thread.isActiveTrip
                      ? Colors.white
                      : AppColors.clayText,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              thread.driverName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          if (thread.isActiveTrip) ...[
                            const SizedBox(width: 6),
                            const ArangBadge(
                              'Current ride',
                              tone: ArangBadgeTone.green,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Body no. ${thread.bodyNumber} · ${thread.todaName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        thread.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: unread
                              ? AppColors.ink
                              : AppColors.textSecondary,
                          fontWeight: unread
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (last != null)
                      Text(
                        RelativeTime.short(last.sentAt),
                        style: AppTypography.caption,
                      ),
                    const SizedBox(height: 6),
                    if (unread)
                      Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        child: Text(
                          '${thread.unreadCount}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArangRowIcon(
              Icons.forum_outlined,
              size: 56,
              background: AppColors.neutralFill,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              filtered ? 'No unread chats' : 'No chats yet',
              style: AppTypography.h2,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              filtered
                  ? 'You are all caught up.'
                  : 'Chats open when a driver is assigned to your ride.',
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// One row inside the chat options card. Centred, full width, matching the
/// prototype's option list.
class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.onTap,
    this.danger = false,
    this.bold = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: AppSizes.minTapTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: danger ? AppColors.dangerDark : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
