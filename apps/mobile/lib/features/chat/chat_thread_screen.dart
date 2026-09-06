import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/format/relative_time.dart';
import '../../core/widgets/arang_ui.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/chat.dart';
import '../../domain/models/demo_user.dart';
import '../../core/widgets/arang_dialog.dart';
import '../../core/widgets/voice_record_button.dart';

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

  /// No microphone is opened and no audio is captured or stored -- see
  /// VoiceRecordButton's doc comment. A completed hold sends a plain text
  /// message describing itself honestly, through the same path as every
  /// other message, rather than pretending to be a real voice note.
  Future<void> _sendVoicePlaceholder(Duration duration) async {
    final seconds = duration.inSeconds.clamp(1, 999);
    await _send('🎤 Voice message · 0:${seconds.toString().padLeft(2, '0')}');
  }

  Future<void> _send(String body) async {
    if (body.trim().isEmpty) return;
    _controller.clear();
    try {
      final role = ref.read(demoStateProvider).currentUser?.role;
      await ref
          .read(chatRepositoryProvider)
          .sendMessage(
            threadId: widget.threadId,
            body: body,
            author: role == DemoRole.driver
                ? ChatMessageAuthor.driver
                : ChatMessageAuthor.commuter,
          );
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
    final connected = ref.watch(liveRideRepositoryProvider) != null;

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

        final viewerIsDriver =
            ref.read(demoStateProvider).currentUser?.role == DemoRole.driver;
        final counterparty = viewerIsDriver
            ? thread.commuterName
            : thread.driverName;
        final ownAuthor = viewerIsDriver
            ? ChatMessageAuthor.driver
            : ChatMessageAuthor.commuter;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                ArangAvatar(
                  name: counterparty,
                  size: 34,
                  background: AppColors.primary,
                  foreground: Colors.white,
                  imageUrl: thread.counterpartAvatarUrl,
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
                              counterparty,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          if (!viewerIsDriver && thread.driverVerified) ...[
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
                        viewerIsDriver
                            ? 'Commuter · Current ride'
                            : 'Body no. ${thread.bodyNumber} · ${thread.todaName}',
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
                tooltip: 'Call $counterparty',
                icon: const Icon(Icons.call_outlined),
                onPressed: () => _showCallSheet(context, counterparty),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                color: AppColors.amberFill,
                child: Text(
                  connected
                      ? 'Private trip chat · retained for 30 days'
                      : 'SANDBOX · Messages stay on this device',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: thread.messages.length,
                  itemBuilder: (context, i) => _Bubble(
                    message: thread.messages[i],
                    ownAuthor: ownAuthor,
                    connected: connected,
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
                  onVoiceRecorded: _sendVoicePlaceholder,
                  allowVoicePlaceholder: !connected,
                ),
            ],
          ),
        );
      },
    );
  }

  void _showCallSheet(BuildContext context, String counterparty) {
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
            Text('Call $counterparty', style: AppTypography.displaySm),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Phone contact becomes available once dispatch is connected. '
              'No number is dialled from this build.',
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

  Future<void> _onMenu(
    BuildContext context,
    String value,
    ChatThread thread,
  ) async {
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
              ArangAvatar(
                name: thread.driverName,
                size: 64,
                imageUrl: thread.counterpartAvatarUrl,
              ),
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

    final liveRides = ref.read(liveRideRepositoryProvider);
    if (liveRides != null) {
      var reason = '';
      var consented = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => ArangDialog(
            title: 'Report this conversation',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Only LGU administrators will receive the reported chat '
                  'history. TODA administrators cannot view it.',
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Reason for reporting',
                  ),
                  onChanged: (value) => setDialogState(() => reason = value),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I consent to sharing this conversation with the LGU.',
                  ),
                  value: consented,
                  onChanged: (value) {
                    setDialogState(() => consented = value == true);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: consented && reason.trim().isNotEmpty
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Send report'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      try {
        await liveRides.reportTripChat(
          tripId: thread.tripId ?? thread.id,
          reason: reason,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The LGU received your reported conversation.'),
            ),
          );
        }
      } on Exception {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not send the report. Try again.'),
            ),
          );
        }
      }
      return;
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ArangDialog(
        title: 'Report driver',
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
  const _Bubble({
    required this.message,
    required this.ownAuthor,
    required this.connected,
    required this.onRetry,
  });

  final ChatMessage message;
  final ChatMessageAuthor ownAuthor;
  final bool connected;
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

    final mine = message.author == ownAuthor;
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
                  Text(
                    connected ? '· Delivered' : '· Saved locally',
                    style: AppTypography.caption.copyWith(fontSize: 11),
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

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onVoiceRecorded,
    required this.allowVoicePlaceholder,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final ValueChanged<Duration> onVoiceRecorded;
  final bool allowVoicePlaceholder;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  void initState() {
    super.initState();
    // The trailing button swaps between mic and send as soon as there is
    // text to send, matching every mainstream chat app's composer.
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;

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
                      onTap: () => widget.onSend(reply),
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
                    controller: widget.controller,
                    textInputAction: TextInputAction.send,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: widget.onSend,
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
                // Empty text and a real connected trip used to render
                // neither button at all: allowVoicePlaceholder is false on a
                // real trip (correctly -- VoiceRecordButton is a placeholder
                // that records nothing, and offering it on a trip that is
                // actually live would misrepresent what the app can do), but
                // the `if (hasText) ... else if (allowVoicePlaceholder) ...`
                // had no third branch, so the composer's trailing slot went
                // fully blank until the driver or commuter typed something.
                // A send button that is always visible, just disabled until
                // there is text, is what every mainstream chat app does when
                // it has no recording feature to fall back to -- and it does
                // not claim a capability the app does not have.
                if (hasText || !widget.allowVoicePlaceholder)
                  Semantics(
                    button: true,
                    label: 'Send message',
                    enabled: hasText,
                    child: Material(
                      color: hasText ? AppColors.primary : AppColors.dividerLight,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: hasText
                            ? () => widget.onSend(widget.controller.text)
                            : null,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: hasText
                                ? Colors.white
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  VoiceRecordButton(onRecorded: widget.onVoiceRecorded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
