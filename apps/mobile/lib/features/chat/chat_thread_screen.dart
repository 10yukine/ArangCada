import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/relative_time.dart';
import '../../core/widgets/arang_ui.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/chat.dart';

const _quickReplies = ['Where po kayo?', 'Salamat po!'];

class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({required this.threadId, super.key});

  final String threadId;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Clearing unread touches the repository, so it must not happen during
    // build. One frame later is early enough for the badge to settle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatRepositoryProvider).markRead(widget.threadId);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppMotion.sheet,
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String body) async {
    if (body.trim().isEmpty) return;
    _controller.clear();
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendMessage(threadId: widget.threadId, body: body);
      _scrollToEnd();
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(chatRepositoryProvider);

    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final thread = repository.threadById(widget.threadId);
        if (thread == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chat')),
            body: const Center(child: Text('Conversation not found.')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                ArangAvatar(
                  name: thread.driverName,
                  size: 34,
                  background: AppColors.primary,
                  foreground: Colors.white,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              thread.driverName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          if (thread.driverVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              size: 14,
                              color: AppColors.green,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Body no. ${thread.bodyNumber} · ${thread.todaName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Call driver',
                icon: const Icon(Icons.call_outlined),
                onPressed: () => _showCallSheet(context, thread),
              ),
              PopupMenuButton<String>(
                tooltip: 'More options',
                onSelected: (value) => _onMenu(context, value, thread),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'profile', child: Text('View profile')),
                  PopupMenuItem(
                    value: 'report',
                    child: Text(
                      'Report driver',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: thread.messages.length,
                  itemBuilder: (context, i) => _Bubble(
                    message: thread.messages[i],
                    onRetry: () => repository.retryMessage(
                      threadId: thread.id,
                      messageId: thread.messages[i].id,
                    ),
                  ),
                ),
              ),
              if (thread.isReadOnly)
                _ClosedConversationNotice()
              else
                _Composer(
                  controller: _controller,
                  onSend: _send,
                ),
            ],
          ),
        );
      },
    );
  }

  void _showCallSheet(BuildContext context, ChatThread thread) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Call ${thread.driverName}', style: AppTypography.displaySm),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Driver phone numbers are issued by the TODA once dispatch is '
              'connected. No number is dialled from this build.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.lg),
            ArangButton(
              label: 'Close',
              variant: ArangButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _onMenu(BuildContext context, String value, ChatThread thread) {
    if (value == 'profile') {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ArangAvatar(name: thread.driverName, size: 64),
              const SizedBox(height: AppSpacing.sm),
              Text(thread.driverName, style: AppTypography.displaySm),
              const SizedBox(height: 4),
              Text(
                'Body no. ${thread.bodyNumber} · ${thread.todaName}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              ArangButton(
                label: 'Close',
                variant: ArangButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report driver'),
        content: Text(
          'Submit a safety concern about ${thread.driverName} to ArangCada '
          'administrators for review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Report recorded for ArangCada administrators.',
                  ),
                ),
              );
            },
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onRetry});

  final ChatMessage message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            '${message.body} · ${RelativeTime.timeOfDay(message.sentAt)}',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
        ),
      );
    }

    final mine = message.author == ChatMessageAuthor.commuter;
    final failed = message.status == ChatMessageStatus.failed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.74,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : AppColors.surface,
              border: mine ? null : Border.all(color: AppColors.border),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
            ),
            child: Text(
              message.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: mine ? Colors.white : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                RelativeTime.timeOfDay(message.sentAt),
                style: AppTypography.caption.copyWith(fontSize: 11),
              ),
              if (mine) ...[
                const SizedBox(width: 4),
                // Status is text + icon, never colour alone.
                if (message.status == ChatMessageStatus.sending)
                  Text(
                    '· Sending',
                    style: AppTypography.caption.copyWith(fontSize: 11),
                  )
                else if (failed)
                  GestureDetector(
                    onTap: onRetry,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 12,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Not sent · Retry',
                          style: AppTypography.caption.copyWith(
                            fontSize: 11,
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Icon(
                    Icons.check,
                    size: 12,
                    color: AppColors.textMuted,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ClosedConversationNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.neutralFill,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: const Text(
          'This ride is complete. The conversation is read-only.',
          textAlign: TextAlign.center,
          style: AppTypography.caption,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final reply in _quickReplies)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ArangChip(
                      label: reply,
                      selected: false,
                      onTap: () => onSend(reply),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: onSend,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Semantics(
                  button: true,
                  label: 'Send message',
                  child: Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onSend(controller.text),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
