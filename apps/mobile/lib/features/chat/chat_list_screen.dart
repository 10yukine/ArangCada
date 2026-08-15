import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/relative_time.dart';
import '../../core/widgets/arang_ui.dart';
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

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread});

  final ChatThread thread;

  @override
  Widget build(BuildContext context) {
    final unread = thread.unreadCount > 0;
    final last = thread.lastMessage;

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => context.push('/chat/${thread.id}'),
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
